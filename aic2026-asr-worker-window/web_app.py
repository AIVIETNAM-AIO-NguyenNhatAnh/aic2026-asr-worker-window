"""
Web UI: kéo-thả video vào trình duyệt -> tự tách audio + chạy ASR -> hiển thị transcript
ngay trên trang (kèm video xem lại, bấm vào 1 đoạn để tua video tới đúng chỗ).

Dùng lại đúng logic trong extract_audio.py + run_asr.py (engine đọc từ config.yaml, mặc định
"transformers" — model wav2vec2-base-vietnamese-250h / whisper-small). Output transcript CÙNG
SCHEMA (start/end/text) với data/processed/transcripts/{video_id}.json của repo chính, nên có
thể copy thẳng file .json tải xuống từ UI này vào aic2026-project nếu muốn.

Model ASR được NẠP 1 LẦN rồi cache lại cho các lần kéo-thả tiếp theo trong cùng phiên chạy web
(khác với run_asr.py CLI / asr_parallel.sh — mỗi lần gọi 1 video luôn nạp lại model, vì chạy
song song nhiều tiến trình độc lập). Nhờ vậy sau lần đầu (chậm, phải tải model), các video sau
xử lý nhanh hơn nhiều — hợp với việc dùng UI này để xem thử nhiều video liên tiếp.

Chạy:
    ./run_web.sh
rồi mở http://127.0.0.1:5057 trên trình duyệt.

Lưu ý cổng: dùng 5057 (không phải 5060/5061) vì Chrome/nhiều trình duyệt CHẶN CỨNG cổng 5060 và
5061 (ERR_UNSAFE_PORT — 2 cổng này dành riêng cho giao thức SIP điện thoại), truy cập sẽ luôn
báo "site can't be reached" dù server chạy đúng.
"""
import argparse
import json
import traceback
import uuid
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory

from extract_audio import extract_audio
from run_asr import load_config, load_asr_pipeline, transcribe_video

BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "web_uploads"
AUDIO_TMP_DIR = BASE_DIR / "web_uploads" / "_audio_tmp"
UPLOAD_DIR.mkdir(exist_ok=True)
AUDIO_TMP_DIR.mkdir(exist_ok=True, parents=True)

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 2 * 1024 * 1024 * 1024  # 2GB, video có thể khá nặng

_cfg = None
_asr_pipeline_cache = None  # cache pipeline "transformers" giữa các lần request (xem docstring)


def get_config():
    global _cfg
    if _cfg is None:
        _cfg = load_config(str(BASE_DIR / "config.yaml"))
    return _cfg


def get_pipeline_if_transformers(cfg):
    """Nạp + cache pipeline ASR nếu engine='transformers'. whisper_cpp không cache (chạy qua
    subprocess riêng mỗi lần, không tốn RAM giữ model trong tiến trình Flask)."""
    global _asr_pipeline_cache
    if cfg["asr"].get("engine", "transformers") != "transformers":
        return None
    if _asr_pipeline_cache is None:
        print("[web_app] Nạp model ASR lần đầu (có thể mất chút thời gian)...")
        _asr_pipeline_cache = load_asr_pipeline(cfg)
    return _asr_pipeline_cache


INDEX_HTML = """<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ASR Transcript — Kéo thả video</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
         background:#0f1115; color:#e8e9ec; }
  header { padding:20px 28px; border-bottom:1px solid #2a2e38; }
  header h1 { font-size:18px; margin:0 0 4px; font-weight:600; }
  header p { font-size:13px; color:#9aa0ab; margin:0; }
  main { max-width:960px; margin:0 auto; padding:24px 28px 60px; }

  #dropzone {
    border:2px dashed #3a3f4b; border-radius:14px; padding:56px 20px;
    text-align:center; cursor:pointer; transition:border-color .15s, background .15s;
  }
  #dropzone.drag { border-color:#5b8cff; background:#131a2b; }
  #dropzone h2 { margin:0 0 8px; font-size:16px; font-weight:600; }
  #dropzone p { margin:0; font-size:13px; color:#9aa0ab; }
  #fileInput { display:none; }

  #status { margin-top:18px; font-size:13px; color:#9aa0ab; display:none; }
  #status.show { display:flex; align-items:center; gap:10px; }
  .spinner { width:16px; height:16px; border-radius:50%;
             border:2px solid #2a2e38; border-top-color:#5b8cff;
             animation:spin .8s linear infinite; }
  @keyframes spin { to { transform:rotate(360deg); } }

  #error { margin-top:18px; font-size:13px; color:#ff6b6b; display:none; }

  #resultHeader { margin-top:28px; display:none; align-items:baseline; gap:10px; flex-wrap:wrap; }
  #resultHeader h2 { font-size:15px; margin:0; font-weight:600; }
  #resultHeader span { font-size:12px; color:#9aa0ab; }
  #downloadLink { font-size:12px; color:#5b8cff; text-decoration:none; margin-left:auto; }
  #downloadLink:hover { text-decoration:underline; }

  #player { margin-top:14px; display:none; }
  #player video { width:100%; max-height:420px; border-radius:10px; background:#000; }

  #segments { margin-top:16px; display:none; }
  .seg { display:flex; gap:12px; padding:10px 12px; border-radius:8px; cursor:pointer;
         border:1px solid transparent; }
  .seg:hover { background:#171a21; border-color:#2a2e38; }
  .seg .ts { flex:0 0 92px; color:#5b8cff; font-variant-numeric:tabular-nums; font-size:12px;
             padding-top:2px; }
  .seg .txt { font-size:14px; line-height:1.5; }
  .seg.empty { color:#6b7280; font-size:13px; padding:16px 12px; }
</style>
</head>
<body>
<header>
  <h1>ASR Transcript — Kéo thả video</h1>
  <p>Tách audio + chạy nhận dạng giọng nói (nhánh ASR) cho 1 video, hiện transcript ngay bên dưới.</p>
</header>
<main>
  <div id="dropzone">
    <h2>Kéo video vào đây, hoặc bấm để chọn file</h2>
    <p>Hỗ trợ .mp4 .mov .mkv .avi ... — lần chạy đầu tiên có thể chậm hơn (đang tải model ASR),
       các video sau nhanh hơn nhiều.</p>
    <input type="file" id="fileInput" accept="video/*">
  </div>

  <div id="status"><div class="spinner"></div><span id="statusText">Đang xử lý...</span></div>
  <div id="error"></div>

  <div id="resultHeader">
    <h2 id="resultTitle"></h2><span id="resultMeta"></span>
    <a id="downloadLink" download>Tải transcript .json</a>
  </div>
  <div id="player"><video id="videoEl" controls></video></div>
  <div id="segments"></div>
</main>

<script>
  const dropzone = document.getElementById("dropzone");
  const fileInput = document.getElementById("fileInput");
  const statusBox = document.getElementById("status");
  const statusText = document.getElementById("statusText");
  const errorBox = document.getElementById("error");
  const resultHeader = document.getElementById("resultHeader");
  const resultTitle = document.getElementById("resultTitle");
  const resultMeta = document.getElementById("resultMeta");
  const downloadLink = document.getElementById("downloadLink");
  const playerBox = document.getElementById("player");
  const videoEl = document.getElementById("videoEl");
  const segmentsBox = document.getElementById("segments");

  dropzone.addEventListener("click", () => fileInput.click());
  fileInput.addEventListener("change", () => {
    if (fileInput.files.length) uploadVideo(fileInput.files[0]);
  });

  ["dragenter", "dragover"].forEach(evt =>
    dropzone.addEventListener(evt, e => { e.preventDefault(); dropzone.classList.add("drag"); }));
  ["dragleave", "drop"].forEach(evt =>
    dropzone.addEventListener(evt, e => { e.preventDefault(); dropzone.classList.remove("drag"); }));
  dropzone.addEventListener("drop", e => {
    const files = e.dataTransfer.files;
    if (files.length) uploadVideo(files[0]);
  });

  function uploadVideo(file) {
    errorBox.style.display = "none";
    resultHeader.style.display = "none";
    playerBox.style.display = "none";
    segmentsBox.style.display = "none";
    segmentsBox.innerHTML = "";
    statusBox.classList.add("show");
    statusText.textContent = `Đang tách audio + chạy ASR cho "${file.name}"... (lần đầu có thể mất vài phút để tải model)`;

    const form = new FormData();
    form.append("video", file);

    fetch("/transcribe", { method: "POST", body: form })
      .then(async res => {
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || "Lỗi không xác định");
        return data;
      })
      .then(renderResult)
      .catch(err => {
        errorBox.textContent = "Lỗi: " + err.message;
        errorBox.style.display = "block";
      })
      .finally(() => statusBox.classList.remove("show"));
  }

  function fmtTs(sec) {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${String(m).padStart(2,"0")}:${String(s).padStart(2,"0")}`;
  }

  function renderResult(data) {
    resultTitle.textContent = `Transcript — ${data.video_name}`;
    resultMeta.textContent = `${data.segment_count} đoạn · engine: ${data.engine}`;
    resultHeader.style.display = "flex";

    downloadLink.href = "data:application/json;charset=utf-8," + encodeURIComponent(JSON.stringify(data.segments, null, 2));
    downloadLink.download = `${data.video_name}.json`;

    videoEl.src = data.video_url;
    playerBox.style.display = "block";

    segmentsBox.style.display = "block";
    if (!data.segments.length) {
      segmentsBox.innerHTML = '<div class="seg empty">Không nhận dạng được đoạn thoại nào (video có thể không có tiếng nói).</div>';
      return;
    }
    data.segments.forEach(seg => {
      const row = document.createElement("div");
      row.className = "seg";
      row.innerHTML = `<div class="ts">${fmtTs(seg.start)}–${fmtTs(seg.end)}</div><div class="txt"></div>`;
      row.querySelector(".txt").textContent = seg.text;
      row.addEventListener("click", () => { videoEl.currentTime = seg.start; videoEl.play(); });
      segmentsBox.appendChild(row);
    });
  }
</script>
</body>
</html>
"""


@app.route("/")
def index():
    return INDEX_HTML


@app.route("/transcribe", methods=["POST"])
def do_transcribe():
    if "video" not in request.files or not request.files["video"].filename:
        return jsonify({"error": "Chưa chọn file video"}), 400

    f = request.files["video"]
    job_id = uuid.uuid4().hex[:8]
    video_name = Path(f.filename).stem
    video_id = f"{job_id}_{video_name}"
    video_path = UPLOAD_DIR / f"{video_id}{Path(f.filename).suffix}"
    f.save(str(video_path))

    cfg = get_config()
    try:
        wav_path = extract_audio(str(video_path), out_dir=str(AUDIO_TMP_DIR))
    except Exception as e:
        traceback.print_exc()  # in đầy đủ traceback ra Terminal (nơi chạy run_web.sh) để dễ debug
        return jsonify({"error": f"Lỗi khi tách audio (cần ffmpeg): {e}"}), 500

    try:
        pipeline_cache = get_pipeline_if_transformers(cfg)
        segments = transcribe_video(video_id, wav_path, cfg, asr_pipeline=pipeline_cache)
    except Exception as e:
        traceback.print_exc()  # in đầy đủ traceback ra Terminal (nơi chạy run_web.sh) để dễ debug
        return jsonify({"error": f"Lỗi khi chạy ASR: {e}"}), 500
    finally:
        Path(wav_path).unlink(missing_ok=True)

    return jsonify({
        "engine": cfg["asr"].get("engine", "transformers"),
        "video_name": video_name,
        "video_url": f"/uploads/{video_path.name}",
        "segment_count": len(segments),
        "segments": segments,
    })


@app.route("/uploads/<path:subpath>")
def serve_upload(subpath):
    return send_from_directory(str(UPLOAD_DIR), subpath)


def main():
    parser = argparse.ArgumentParser(description="Web UI kéo-thả video để xem transcript ASR.")
    parser.add_argument("--port", type=int, default=5057)
    args = parser.parse_args()
    print(f"[web_app] Mở trình duyệt: http://127.0.0.1:{args.port}")
    app.run(host="127.0.0.1", port=args.port, debug=False)


if __name__ == "__main__":
    main()
