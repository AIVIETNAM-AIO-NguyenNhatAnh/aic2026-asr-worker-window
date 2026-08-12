#!/usr/bin/env bash
# Chạy run_asr.py song song nhiều video cùng lúc. Mặc định CHỈ 2 video song song (thấp hơn
# nhiều so với extract_parallel.sh của bước keyframe) — vì mỗi tiến trình ASR tự nạp lại 1
# bản model wav2vec2/whisper riêng (vài trăm MB - ~1GB RAM/tiến trình), chạy quá nhiều cùng
# lúc dễ làm máy đơ/swap. Tăng số luồng nếu máy nhiều RAM (>=16GB) và muốn nhanh hơn.
#
# Dùng: bash asr_parallel.sh          (mặc định 2 luồng song song)
#       bash asr_parallel.sh 3        (ép chạy đúng 3 video cùng lúc)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_common.sh"

PYTHON="$(find_python)" || { echo "[asr_parallel.sh] Không tìm thấy Python3 nào trên máy." >&2; exit 1; }
ensure_module "$PYTHON" yaml pyyaml
ensure_asr_stack "$PYTHON" || { echo "[asr_parallel.sh] Bộ torch/torchaudio/transformers lỗi, xem chi tiết ở trên." >&2; exit 1; }

command -v ffmpeg >/dev/null 2>&1 || {
  echo "[asr_parallel.sh] Chưa thấy lệnh 'ffmpeg' — cần để tách audio từ video." >&2
  echo "  Cài bằng: brew install ffmpeg   (macOS)   hoặc   apt install -y ffmpeg   (Linux)" >&2
  exit 1
}

echo "[asr_parallel.sh] Dùng interpreter: $PYTHON -> $($PYTHON -c 'import sys; print(sys.executable)')"

RAW_DIR="$DIR/data/raw"
if [ ! -d "$RAW_DIR" ] || [ -z "$(ls -A "$RAW_DIR" 2>/dev/null)" ]; then
  echo "[asr_parallel.sh] $RAW_DIR trống — chạy 'bash download_videos.sh <ten>' trước (duong/khoa/tien/kien)." >&2
  exit 1
fi

JOBS="${1:-2}"

n_videos=$(find "$RAW_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.webm" \) | wc -l | tr -d ' ')
echo "[asr_parallel.sh] $n_videos video, chạy song song $JOBS luồng (mỗi luồng nạp riêng 1 bản model)..."

find "$RAW_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.webm" \) -print0 \
  | xargs -0 -n 1 -P "$JOBS" -I {} "$PYTHON" "$DIR/run_asr.py" --video {} --config "$DIR/config.yaml"

echo ""
echo "[asr_parallel.sh] Hoàn tất. Kiểm tra: ls data/processed/transcripts | wc -l"
