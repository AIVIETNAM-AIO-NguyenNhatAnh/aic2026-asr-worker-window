#!/usr/bin/env bash
# Nén toàn bộ data/processed/transcripts/ (transcript .json đã chạy ASR) thành 1 file zip để
# gửi lại cho trưởng nhóm — KHÔNG nén data/raw/ (video gốc) hay data/processed/_audio_tmp/
# (file wav tạm), vì đều không cần thiết cho việc gộp kết quả.
#
# Dùng: bash package_results.sh duong   (tên file zip sẽ có "duong" + ngày giờ)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${1:-ketqua}"
STAMP="$(date +%Y%m%d_%H%M)"
OUT="$DIR/transcripts_${LABEL}_${STAMP}.zip"

if [ ! -d "$DIR/data/processed/transcripts" ] || [ -z "$(ls -A "$DIR/data/processed/transcripts" 2>/dev/null)" ]; then
  echo "[package_results.sh] data/processed/transcripts/ đang trống — chạy asr_parallel.sh (hoặc run_asr.py) trước." >&2
  exit 1
fi

cd "$DIR"
zip -r -q "$OUT" data/processed/transcripts

n_files=$(find data/processed/transcripts -maxdepth 1 -type f -iname "*.json" | wc -l | tr -d ' ')
echo "[package_results.sh] Đã đóng gói $n_files transcript -> $OUT"
echo "[package_results.sh] Gửi file này (qua Zalo/Google Drive/email) cho trưởng nhóm."
