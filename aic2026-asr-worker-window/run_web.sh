#!/usr/bin/env bash
# Chạy Web UI kéo-thả video xem transcript ASR (web_app.py) bằng đúng 1 Python interpreter,
# tự cài gói còn thiếu.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
source "$DIR/_common.sh"

PYTHON="$(find_python)" || { echo "[run_web.sh] Không tìm thấy Python3 nào trên máy." >&2; exit 1; }
ensure_module "$PYTHON" flask flask
ensure_module "$PYTHON" yaml pyyaml
ensure_asr_stack "$PYTHON" || { echo "[run_web.sh] Bộ torch/torchaudio/transformers lỗi, xem chi tiết ở trên." >&2; exit 1; }

command -v ffmpeg >/dev/null 2>&1 || {
  echo "[run_web.sh] Chưa thấy lệnh 'ffmpeg' — cần để tách audio từ video." >&2
  echo "  Cài bằng: brew install ffmpeg   (macOS)   hoặc   apt install -y ffmpeg   (Linux)" >&2
  exit 1
}

echo "[run_web.sh] Dùng interpreter: $PYTHON -> $($PYTHON -c 'import sys; print(sys.executable)')"
exec "$PYTHON" "$DIR/web_app.py" "$@"
