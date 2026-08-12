"""
Chạy ASR trên audio tách từ video, xuất transcript thống nhất:
data/processed/transcripts/{video_id}.json -> [{"start":.., "end":.., "text":..}]
Xem quy ước format tại docs/pipeline.md

2 engine, chọn qua config.yaml -> asr.engine:
  - "transformers" (mặc định, chạy tốt trên Kaggle, chỉ cần pip install, không cần biên dịch):
    HF transformers pipeline, model wav2vec2-base-vietnamese-250h (primary) /
    whisper-small (fallback), chia audio theo chunk_length_s cố định. Mỗi đoạn được
    gọi độc lập với pipeline() -> không giữ ngữ cảnh câu trước giữa các đoạn.
  - "whisper_cpp" (chạy trên máy có sẵn whisper.cpp, vd. máy local hoặc GPU thuê):
    whisper.cpp CLI (whisper-cli) + model ggml (vd. ggml-small.bin). Dùng -mc 0
    (max-context=0) để mỗi đoạn audio whisper.cpp tự chia được decode độc lập,
    giảm lặp câu/hallucination khi audio dài — theo cách nhóm đã benchmark trong
    final/report.md (script final/extract_audio_transcript.py). Xuất kèm
    .srt/.vtt/.csv/.txt bên cạnh .json (để xem lại nhanh hoặc làm phụ đề), nhưng
    file transcript thống nhất đọc bởi phần index vẫn luôn là .json nói trên.
    Nếu không tìm thấy binary whisper-cli -> tự động chuyển sang engine "transformers"
    (đảm bảo pipeline vẫn chạy được trên Kaggle dù config để whisper_cpp).

Dùng: python run_asr.py --video data/raw/xxx.mp4

Bản này tách riêng từ aic2026-project/indexing/audio_asr/run_asr.py để chạy độc lập trên máy
từng thành viên team (xem README.md ở thư mục này) — output CÙNG SCHEMA với repo chính
(data/processed/transcripts/{video_id}.json) nên gộp thẳng vào aic2026-project/data/processed/
được, không cần chuyển đổi định dạng gì thêm.

Lưu ý hiệu năng: mỗi lần gọi --video sẽ NẠP LẠI model ASR từ đầu (đúng hành vi gốc của repo
chính — scripts/run_indexing_pipeline.py cũng gọi subprocess riêng cho từng video) — không phải
lỗi, nhưng vì vậy chạy song song nhiều video cùng lúc sẽ tốn RAM hơn hẳn bước keyframe (mỗi
tiến trình song song tự nạp 1 bản model riêng). Xem asr_parallel.sh — mặc định chỉ chạy 2 video
song song (thấp hơn nhiều so với extract_parallel.sh của bước keyframe).
"""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

import yaml

from extract_audio import extract_audio


def load_config(config_path="config.yaml"):
    with open(config_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# ---------------------------------------------------------------------------
# Engine 1: HF transformers pipeline (mặc định, pip-installable, chạy tốt trên Kaggle)
# ---------------------------------------------------------------------------

def load_asr_pipeline(cfg):
    import torch
    from transformers import pipeline

    device = 0 if torch.cuda.is_available() else -1
    primary = cfg["asr"]["primary_model"]
    fallback = cfg["asr"]["fallback_model"]
    try:
        asr = pipeline("automatic-speech-recognition", model=primary, device=device)
        print(f"[ASR] Dùng model chính: {primary}")
        return asr
    except Exception as e:
        print(f"[ASR] Không tải được '{primary}' ({e}). Chuyển sang fallback: {fallback}")
        return pipeline("automatic-speech-recognition", model=fallback, device=device)


def transcribe_with_transformers(wav_path: str, cfg, asr_pipeline=None) -> list:
    import torchaudio

    # asr_pipeline: cho phép truyền sẵn 1 pipeline đã nạp (vd. web_app.py cache lại giữa các
    # lần request để khỏi nạp lại model mỗi lần) — nếu không truyền, giữ đúng hành vi cũ (tự
    # nạp mới mỗi lần gọi, dùng bởi run_asr.py CLI / asr_parallel.sh).
    if asr_pipeline is None:
        asr_pipeline = load_asr_pipeline(cfg)
    chunk_length_s = cfg["asr"]["chunk_length_s"]

    waveform, sr = torchaudio.load(wav_path)
    if sr != 16000:
        waveform = torchaudio.functional.resample(waveform, sr, 16000)
        sr = 16000
    total_seconds = waveform.shape[1] / sr

    segments = []
    t = 0.0
    while t < total_seconds:
        end = min(t + chunk_length_s, total_seconds)
        chunk = waveform[:, int(t * sr):int(end * sr)].squeeze().numpy()
        if chunk.size == 0:
            break
        try:
            result = asr_pipeline({"array": chunk, "sampling_rate": sr})
            text = result["text"].strip() if isinstance(result, dict) else str(result).strip()
        except Exception as e:
            text = ""
            print(f"[ASR] Lỗi ở đoạn {t:.1f}-{end:.1f}s: {e}")
        if text:
            segments.append({"start": round(t, 2), "end": round(end, 2), "text": text})
        t = end
    return segments


# ---------------------------------------------------------------------------
# Engine 2: whisper.cpp CLI (whisper-cli + model ggml) — máy local / GPU thuê.
# ---------------------------------------------------------------------------

def find_whisper_cli(cfg) -> str:
    configured = cfg["asr"].get("whisper_cpp", {}).get("binary")
    if configured and Path(configured).exists():
        return configured
    return shutil.which("whisper-cli")


def transcribe_with_whisper_cpp(video_id: str, wav_path: str, out_dir: Path, cfg) -> list:
    wcfg = cfg["asr"]["whisper_cpp"]
    binary = find_whisper_cli(cfg)
    model_path = Path(wcfg["model_path"])
    if not model_path.exists():
        raise FileNotFoundError(
            f"Không thấy model ggml: {model_path}. Tải bằng script trong repo whisper.cpp: "
            "models/download-ggml-model.sh small (hoặc tải file .bin tương ứng thủ công)."
        )

    out_dir.mkdir(parents=True, exist_ok=True)
    output_prefix = out_dir / f"{video_id}_whisper_cpp"
    cmd = [binary]
    if not wcfg.get("use_gpu", False):
        cmd.append("--no-gpu")
    cmd += [
        "-m", str(model_path),
        "-f", str(wav_path),
        "-l", wcfg.get("language", "vi"),
        "-mc", str(wcfg.get("max_context", 0)),
        "-oj",                                  # json -> nguồn parse chính, có timestamps
        "-osrt", "-ovtt", "-ocsv", "-otxt",      # bonus: xem lại nhanh / làm phụ đề
        "-of", str(output_prefix),
    ]
    subprocess.run(cmd, check=True)

    json_path = Path(f"{output_prefix}.json")
    raw = json.loads(json_path.read_text(encoding="utf-8"))
    segments = []
    for item in raw.get("transcription", []):
        text = item.get("text", "").strip()
        if not text:
            continue
        offsets = item.get("offsets", {})
        segments.append({
            "start": round(offsets.get("from", 0) / 1000.0, 2),
            "end": round(offsets.get("to", 0) / 1000.0, 2),
            "text": text,
        })
    return segments


# ---------------------------------------------------------------------------

def transcribe_video(video_id: str, wav_path: str, cfg, asr_pipeline=None) -> list:
    # asr_pipeline: chỉ áp dụng cho engine "transformers" (xem transcribe_with_transformers) —
    # dùng bởi web_app.py để cache model giữa nhiều lần kéo-thả video, tránh nạp lại mỗi lần.
    engine = cfg["asr"].get("engine", "transformers")
    if engine == "whisper_cpp":
        if find_whisper_cli(cfg) is None:
            print("[ASR] engine='whisper_cpp' nhưng không tìm thấy binary whisper-cli -> chuyển sang 'transformers'.")
        else:
            raw_dir = Path(cfg["paths"]["transcripts"]) / "_whisper_cpp_raw"
            print("[ASR] Dùng engine: whisper_cpp")
            return transcribe_with_whisper_cpp(video_id, wav_path, raw_dir, cfg)
    return transcribe_with_transformers(wav_path, cfg, asr_pipeline=asr_pipeline)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--video", required=True, help="Đường dẫn video gốc")
    args = parser.parse_args()

    cfg = load_config(args.config)
    wav_path = extract_audio(args.video, out_dir="data/processed/_audio_tmp")

    video_id = Path(args.video).stem
    segments = transcribe_video(video_id, wav_path, cfg)

    out_dir = Path(cfg["paths"]["transcripts"])
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{video_id}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(segments, f, ensure_ascii=False, indent=2)

    print(f"[{video_id}] {len(segments)} đoạn transcript -> {out_path}")


if __name__ == "__main__":
    main()
