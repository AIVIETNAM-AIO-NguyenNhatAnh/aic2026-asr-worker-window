#!/usr/bin/env bash
# Tải ĐÚNG PHẦN video được giao cho 1 thành viên làm ASR (14 file Videos_*.zip của batch 1
# AIC 2026 chia cho 4 người — xem README.md mục "Phân công"). Giải nén, gom video ra data/raw/,
# xoá zip ngay sau khi giải nén.
#
# Dùng: bash download_videos.sh duong   (hoặc khoa / tien / kien)
# Muốn tải danh sách khác, truyền thẳng tên file:
#   bash download_videos.sh Videos_L21_a.zip Videos_L22_a.zip
#
# LƯU Ý: đây là phân công RIÊNG cho nhóm làm ASR (4 người) — khác với phân công 5 người của
# aic2026-keyframe-worker (chia theo memberN). Cùng 1 người có thể làm ASR ở gói này và cũng làm
# 1 phần keyframe ở gói kia, tuỳ trưởng nhóm phân công.

set -euo pipefail

BASE_URL="https://aic-data.ledo.io.vn"
RAW_DIR="data/raw"
TMP_DIR="$(mktemp -d)"

# Phân công 14 file cho 4 thành viên làm ASR — chia đều nhất có thể (4/4/3/3).
duong=(Videos_L21_a.zip Videos_L22_a.zip Videos_L23_a.zip Videos_L24_a.zip)
khoa=(Videos_L25_a.zip Videos_L26_a.zip Videos_L26_b.zip Videos_L26_c.zip)
tien=(Videos_L26_d.zip Videos_L26_e.zip Videos_L27_a.zip)
kien=(Videos_L28_a.zip Videos_L29_a.zip Videos_L30_a.zip)

case "${1:-}" in
  duong) FILES=("${duong[@]}") ;;
  khoa)  FILES=("${khoa[@]}") ;;
  tien)  FILES=("${tien[@]}") ;;
  kien)  FILES=("${kien[@]}") ;;
  "")
    echo "Dùng: bash download_videos.sh duong   (hoặc khoa / tien / kien, hoặc liệt kê tên file zip cụ thể)" >&2
    exit 1
    ;;
  *) FILES=("$@") ;;
esac

echo ">>> Sẽ tải ${#FILES[@]} file: ${FILES[*]}"

command -v aria2c >/dev/null 2>&1 || {
  echo "Lỗi: cần lệnh 'aria2c' (tải đa luồng, server nguồn giới hạn tốc độ mỗi kết nối rất thấp)." >&2
  echo "Cài bằng: brew install aria2   (macOS)   hoặc   apt install -y aria2   (Linux)" >&2
  exit 1
}

mkdir -p "$RAW_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

for fname in "${FILES[@]}"; do
  echo ">>> Tải $fname ..."
  aria2c -x 16 -s 16 -k 1M --retry-wait=3 --max-tries=5 \
    -d "$TMP_DIR" -o "$fname" "$BASE_URL/$fname"

  echo ">>> Giải nén $fname ..."
  unzip -q -o "$TMP_DIR/$fname" -d "$TMP_DIR/extract"

  find "$TMP_DIR/extract" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.webm" \) \
    -exec mv -n {} "$RAW_DIR/" \;

  rm -rf "$TMP_DIR/extract" "$TMP_DIR/$fname"
  echo ">>> Xong $fname"
done

n_videos=$(find "$RAW_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.webm" \) | wc -l)
echo ""
echo "Hoàn tất. $n_videos video đang có trong $RAW_DIR/."
