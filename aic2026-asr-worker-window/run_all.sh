#!/usr/bin/env bash
# Chạy trọn gói cho 1 thành viên: tải video được giao -> chạy ASR (song song có kiểm soát) ->
# đóng gói kết quả thành zip để gửi lại. Chỉ cần 1 lệnh duy nhất.
#
# Dùng: bash run_all.sh duong   (hoặc khoa / tien / kien — xem phân công trong README.md)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

MEMBER="${1:-}"
if [ -z "$MEMBER" ]; then
  echo "Dùng: bash run_all.sh <ten>   (duong / khoa / tien / kien — đúng phần bạn được giao, xem README.md)" >&2
  exit 1
fi

echo "======================================================================"
echo " Bước 1/3 — Tải video được giao ($MEMBER)"
echo "======================================================================"
bash download_videos.sh "$MEMBER"

echo ""
echo "======================================================================"
echo " Bước 2/3 — Chạy ASR (song song có kiểm soát, mặc định 2 video cùng lúc)"
echo "======================================================================"
bash asr_parallel.sh

echo ""
echo "======================================================================"
echo " Bước 3/3 — Đóng gói kết quả"
echo "======================================================================"
bash package_results.sh "$MEMBER"

echo ""
echo "Xong! Gửi file zip vừa tạo (transcripts_${MEMBER}_*.zip) cho trưởng nhóm."
