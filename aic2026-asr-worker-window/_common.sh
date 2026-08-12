#!/usr/bin/env bash
# Dùng chung cho run.sh và run_web.sh: tìm ĐÚNG 1 Python interpreter và luôn cài thiếu gì
# thì bù vào đúng interpreter đó — không bao giờ trộn giữa 2 bản Python khác nhau nữa
# (nguyên nhân toàn bộ lỗi "pip nói đã cài" nhưng "ModuleNotFoundError" trước đây).

PY_CANDIDATES=(
  python3.13 python3.12 python3.11 python3.10 python3.9
  /usr/local/bin/python3.13 /usr/local/bin/python3.12 /usr/local/bin/python3.11 /usr/local/bin/python3.10 /usr/local/bin/python3
  /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3.10 /opt/homebrew/bin/python3
  python3 python
)

# find_python: in ra đường dẫn 1 interpreter có sẵn cv2+numpy nếu có; nếu không bản nào có,
# lấy bản python3 đầu tiên tìm thấy và cài opencv-python+numpy (2 gói nhẹ, luôn cài được)
# vào đúng bản đó rồi trả về bản đó luôn — KHÔNG bao giờ cài vào 1 bản rồi chạy bằng bản khác.
find_python() {
  local c
  for c in "${PY_CANDIDATES[@]}"; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import cv2, numpy" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  for c in "${PY_CANDIDATES[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "[_common.sh] Cài opencv-python + numpy vào $c ..." >&2
      "$c" -m pip install --user opencv-python numpy >&2
      echo "$c"
      return 0
    fi
  done
  return 1
}

# ensure_module PYTHON module pip_package...: cài thêm 1 gói vào ĐÚNG interpreter đang dùng
# nếu module đó chưa import được — không tự đổi sang interpreter khác.
ensure_module() {
  local py="$1" mod="$2"; shift 2
  if ! "$py" -c "import $mod" >/dev/null 2>&1; then
    echo "[_common.sh] Cài thêm $* vào $py ..." >&2
    "$py" -m pip install --user "$@" >&2
  fi
}

# ensure_optional PYTHON module pip_package...: giống ensure_module nhưng không dừng script
# nếu cài lỗi (dùng cho transnetv2-pytorch — nếu thiếu, extract_keyframes.py tự rơi về
# phương pháp "uniform" nên không cần chặn cả chương trình).
ensure_optional() {
  local py="$1" mod="$2"; shift 2
  if ! "$py" -c "import $mod" >/dev/null 2>&1; then
    echo "[_common.sh] (tuỳ chọn) Cài thêm $* vào $py — nếu lỗi vẫn chạy tiếp được..." >&2
    "$py" -m pip install --user "$@" >&2 || true
  fi
}

# ensure_asr_stack PYTHON: cài đủ torch+torchaudio+transformers rồi TỰ KIỂM TRA THẬT bằng đúng
# cơ chế transformers dùng nội bộ (transformers.utils.is_torch_available()) thay vì chỉ kiểm tra
# "import torch" suông. Lý do (đã gặp thực tế): các bản transformers gần đây (>= ~4.50) tự ép
# torch phải >= 2.4/2.5 mới bật tích hợp — nếu máy có torch cũ hơn (vd. Mac Intel/x86_64: PyPI
# CHỈ có torch tối đa 2.2.2 cho kiến trúc này, Apple đã ngừng build torch mới hơn), "import torch"
# và các phép tính tensor cơ bản vẫn chạy bình thường (không lỗi ngay), NHƯNG transformers tự phát
# hiện torch "quá cũ" và ÂM THẦM tắt tích hợp (in 1 dòng cảnh báo dễ bị bỏ qua: "[transformers]
# Disabling PyTorch because PyTorch >= X is required..."), khiến biến `torch` không được import
# bên trong module pipeline của transformers -> lúc thật sự gọi pipeline(...) mới vỡ ra lỗi khó
# hiểu "NameError: name 'torch' is not defined". Cộng thêm numpy 2.x không khớp ABI với torch cũ
# (cũng hay gặp). Hướng sửa ĐÚNG không phải ép torch mới (bất khả thi trên Mac Intel) mà là GHIM
# transformers dưới ngưỡng bắt đầu ép version (<4.50) — tương thích được cả torch cũ lẫn mới. Hàm
# này kiểm tra đúng is_torch_available() (chỗ transformers tự set cờ) để bắt lớp lỗi này, tự cài
# lại 1 lần, và nếu vẫn lỗi thì in rõ traceback + lệnh sửa thủ công.
ensure_asr_stack() {
  local py="$1"
  local check='import torch, torchaudio
from transformers.utils import is_torch_available
assert is_torch_available(), f"transformers khong nhan torch {torch.__version__} (thu ha transformers xuong <4.50)"'
  if ! "$py" -c "$check" >/dev/null 2>&1; then
    echo "[_common.sh] Bộ torch/torchaudio/transformers/numpy có vấn đề (thường do transformers bản mới ép torch mới hơn máy đang có, hoặc lệch numpy) -> tự cài lại..." >&2
    "$py" -m pip install --user --upgrade --force-reinstall "numpy<2" torch torchaudio "transformers>=4.40,<4.50" >&2
  fi
  if ! "$py" -c "$check" 2>/tmp/aic_asr_stack_check.err; then
    echo "[_common.sh] Vẫn lỗi sau khi tự cài lại. Chi tiết:" >&2
    cat /tmp/aic_asr_stack_check.err >&2
    echo "[_common.sh] Thử sửa thủ công:" >&2
    echo "  $py -m pip install --user --upgrade --force-reinstall \"numpy<2\" torch torchaudio \"transformers>=4.40,<4.50\"" >&2
    return 1
  fi
}

check_ffmpeg_binary() {
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "[_common.sh] Lưu ý: chưa thấy lệnh 'ffmpeg' trên máy. Cách 5 (TransNetV2) cần" >&2
    echo "  ffmpeg để đọc video — nếu thấy lỗi kiểu \"No such file or directory: 'ffmpeg'\"," >&2
    echo "  cài bằng: brew install ffmpeg (rồi chạy lại). Thiếu ffmpeg vẫn chạy được, chỉ" >&2
    echo "  tự rơi về phương pháp 'uniform' thay vì Cách 5." >&2
  fi
}
