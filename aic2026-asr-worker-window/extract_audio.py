"""Tách audio (wav, mono, 16kHz, pcm_s16le) từ video bằng ffmpeg — input cho ASR.

Tham số ffmpeg (-ac 1 -ar 16000 -c:a pcm_s16le) khớp với final/extract_audio_transcript.py
của nhóm (benchmark trên máy Mac) để wav đầu ra tương thích cả 2 engine ASR
(HF transformers pipeline và whisper.cpp CLI) mà không cần convert lại.
"""
import shutil
import subprocess
from pathlib import Path


def extract_audio(video_path: str, out_dir: str, sample_rate: int = 16000, ffmpeg_binary: str = None) -> str:
    video_id = Path(video_path).stem
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    out_path = str(Path(out_dir) / f"{video_id}.wav")

    ffmpeg_bin = ffmpeg_binary or shutil.which("ffmpeg") or "ffmpeg"
    cmd = [
        ffmpeg_bin, "-hide_banner", "-loglevel", "error", "-y",
        "-i", video_path,
        "-vn", "-ac", "1", "-ar", str(sample_rate), "-c:a", "pcm_s16le",
        out_path,
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise RuntimeError(
            f"ffmpeg lỗi khi tách audio {video_path}: {result.stderr.decode(errors='ignore')}\n"
            "Kaggle thường có sẵn ffmpeg; nếu thiếu, chạy: !apt-get install -y ffmpeg"
        )
    return out_path
