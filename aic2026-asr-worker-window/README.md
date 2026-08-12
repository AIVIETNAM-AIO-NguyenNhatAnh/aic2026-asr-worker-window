# aic2026-asr-worker

Package độc lập để **4 thành viên team tự chạy ASR (tách giọng nói thành transcript) trên máy
cá nhân** cho phần dữ liệu video AIC 2026 batch 1 — không cần GPU, không cần thuê server. Sau
đó gửi kết quả về cho trưởng nhóm gộp lại vào repo chính `aic2026-project`.

Vì sao chạy được trên máy cá nhân không cần GPU: 2 engine ASR trong repo (HF transformers
pipeline dùng model `wav2vec2-base-vietnamese-250h`/`whisper-small`, hoặc `whisper.cpp`) đều tự
chạy CPU nếu không có GPU — chậm hơn có GPU nhưng vẫn ra kết quả đúng, không như bước semantic
embedding (Qwen3-VL-Embedding-2B) hay OCR quy mô lớn mới thực sự nên để dành máy thuê GPU.

**Hỗ trợ cả macOS/Linux lẫn Windows:** mỗi bước có 2 bản script — file `.sh` (chạy bằng `bash`,
dùng trên macOS/Linux) và file `.ps1` tương ứng (chạy bằng PowerShell, dùng trên Windows). Logic
Python bên trong (`run_asr.py`, `extract_audio.py`, `web_app.py`) dùng chung 100% cho cả 2 hệ
điều hành, chỉ phần vỏ ngoài (tải video, chạy song song, đóng gói zip) là viết riêng theo từng
hệ. Xem đúng mục cho hệ điều hành của bạn bên dưới.

**Phân công lần này khác với `aic2026-keyframe-worker`:** trưởng nhóm tự chạy toàn bộ 14 file
cho bước keyframe; 4 thành viên **Dương, Khoa, Tiến, Kiên** chia nhau chạy toàn bộ bước ASR
(14 file, chia 4 người — không phải 5). Phân công ở gói này là RIÊNG, không nhất thiết trùng vai
trò của từng người ở gói keyframe.

## Phân công (14 file video, chia cho 4 người)

| Người | Lệnh dùng | File được giao |
|---|---|---|
| **Dương** | `duong` | Videos_L21_a.zip, Videos_L22_a.zip, Videos_L23_a.zip, Videos_L24_a.zip |
| **Khoa**  | `khoa`  | Videos_L25_a.zip, Videos_L26_a.zip, Videos_L26_b.zip, Videos_L26_c.zip |
| **Tiến**  | `tien`  | Videos_L26_d.zip, Videos_L26_e.zip, Videos_L27_a.zip |
| **Kiên**  | `kien`  | Videos_L28_a.zip, Videos_L29_a.zip, Videos_L30_a.zip |

(cột "Lệnh dùng" là tên không dấu, gõ trong Terminal — xem bên dưới)

## Cài đặt (làm 1 lần)

### macOS / Linux

1. Python 3.9+ (kiểm tra: `python3 --version`).
2. `aria2` (tải video đa luồng):
   ```bash
   brew install aria2      # macOS
   apt install -y aria2    # Linux/WSL
   ```
3. `ffmpeg` (tách audio từ video — **khác** với `aria2`, cả 2 đều cần):
   ```bash
   brew install ffmpeg      # macOS
   apt install -y ffmpeg    # Linux/WSL
   ```
4. Không cần tự cài gói Python (torch/transformers/torchaudio/pyyaml) — script tự phát hiện
   Python và tự cài thiếu gì bù nấy. Lưu ý các gói này khá nặng (torch ~1-2GB) và mô hình
   `wav2vec2-base-vietnamese-250h`/`whisper-small` sẽ tự tải về (vài trăm MB) khi chạy lần đầu
   — cần mạng ổn định lúc chạy lần đầu tiên.

### Windows

1. Python 3.9+ — tải từ [python.org](https://python.org) (nhớ tick "Add python.exe to PATH" lúc
   cài) hoặc `winget install Python.Python.3.11`. Kiểm tra: mở PowerShell, gõ `py -3.11 --version`.
2. `aria2` (tải video đa luồng):
   ```powershell
   winget install aria2.aria2
   ```
3. `ffmpeg` (tách audio từ video — **khác** với `aria2`, cả 2 đều cần):
   ```powershell
   winget install ffmpeg
   ```
   (nếu máy không có `winget`, cài qua [Chocolatey](https://chocolatey.org): `choco install aria2 ffmpeg`,
   hoặc tải thủ công 2 file `.exe`/`.zip` từ trang chủ rồi thêm đường dẫn vào biến môi trường `PATH`)
4. Cho phép chạy file `.ps1` (Windows mặc định chặn) — mở PowerShell **với quyền người dùng hiện
   tại** (không cần Admin), gõ 1 lần:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```
5. Không cần tự cài gói Python (torch/transformers/torchaudio/pyyaml/flask) — script `.ps1` tự
   phát hiện Python và tự cài thiếu gì bù nấy, giống hệt bản macOS/Linux.

## Chạy (chỉ 1 lệnh)

Thay bằng đúng tên của bạn (`duong`/`khoa`/`tien`/`kien`):

**macOS/Linux** — mở Terminal, `cd` vào thư mục này:
```bash
bash run_all.sh duong
```

**Windows** — mở PowerShell, `cd` vào thư mục này:
```powershell
.\run_all.ps1 duong
```

Lệnh này tự làm tuần tự:
1. Tải + giải nén video được giao vào `data/raw/` (xoá zip ngay sau khi giải nén).
2. Chạy ASR — **mặc định chỉ 2 video song song cùng lúc** (thấp hơn nhiều so với bước keyframe)
   vì mỗi tiến trình tự nạp riêng 1 bản model ASR (tốn RAM hơn hẳn OpenCV) — tránh máy bị đơ.
3. Nén `data/processed/transcripts/` thành 1 file `transcripts_duong_<ngày giờ>.zip` (thay
   `duong` bằng đúng tên bạn dùng).

Xong thì gửi file zip đó (Zalo/Google Drive/email) cho trưởng nhóm.

**Thời gian ước tính:** ASR chậm hơn keyframe extraction đáng kể (phải chạy cả model deep
learning cho từng đoạn audio) — có thể mất nhiều giờ tuỳ số lượng/độ dài video trong phần được
giao. Chạy nền qua đêm được, máy sẽ dùng nhiều CPU + RAM trong lúc chạy.

## Web UI — kéo-thả 1 video, xem transcript ngay trên trình duyệt

Dùng để xem thử nhanh output ASR cho 1 video bất kỳ (không cần chạy cả `run_all`, không cần gõ
lệnh gì thêm) — kéo video vào trang, trang tự tách audio + chạy ASR + hiện transcript kèm video
xem lại (bấm vào 1 đoạn để tua video tới đúng chỗ).

```bash
bash run_web.sh          # macOS/Linux
```
```powershell
.\run_web.ps1             # Windows
```

rồi mở `http://127.0.0.1:5057` trên trình duyệt (không phải 5060 — cổng đó bị Chrome/nhiều trình
duyệt chặn cứng vì dành cho giao thức SIP, sẽ báo lỗi ERR_UNSAFE_PORT dù server chạy đúng). Lần
kéo video đầu tiên sẽ chậm hơn (đang tải
model ASR về máy), các video sau trong cùng phiên chạy nhanh hơn nhiều vì model được giữ lại
trong bộ nhớ (khác với `asr_parallel` — mỗi tiến trình song song luôn nạp lại model, xem giải
thích trong `run_asr.py`). Có nút tải transcript `.json` (cùng schema với
`data/processed/transcripts/{video_id}.json`) nếu muốn lưu lại hoặc gộp thủ công vào repo chính.

UI này chỉ để xem thử/kiểm tra kết quả — muốn chạy hàng loạt cho cả phần được giao vẫn dùng
`run_all` như bên trên.

## Chạy từng bước riêng (nếu cần)

**macOS/Linux:**
```bash
bash download_videos.sh duong   # chỉ tải (đổi "duong" thành đúng tên bạn)
bash asr_parallel.sh            # chỉ chạy ASR (mặc định 2 luồng song song)
bash asr_parallel.sh 1          # chạy tuần tự từng video 1 (máy ít RAM, tránh đơ máy)
bash asr_parallel.sh 3          # ép chạy 3 video song song (máy nhiều RAM, >=16GB)
bash package_results.sh duong   # chỉ đóng gói
```

**Windows:**
```powershell
.\download_videos.ps1 duong        # chỉ tải (đổi "duong" thành đúng tên bạn)
.\asr_parallel.ps1                  # chỉ chạy ASR (mặc định 2 luồng song song)
.\asr_parallel.ps1 -Jobs 1          # chạy tuần tự từng video 1 (máy ít RAM, tránh đơ máy)
.\asr_parallel.ps1 -Jobs 3          # ép chạy 3 video song song (máy nhiều RAM, >=16GB)
.\package_results.ps1 duong         # chỉ đóng gói
```

Nếu máy bị chậm/đơ khi chạy song song, giảm xuống 1 luồng (chạy tuần tự) — chậm hơn nhưng ổn
định, không lo hết RAM.

## Lỗi "NameError: name 'torch' is not defined"

Gặp khi bản `transformers` cài được (mới) tự ép torch phải >= 2.4/2.5 mới bật tích hợp, trong khi
máy chỉ có torch cũ hơn — đặc biệt **Mac Intel (x86_64): PyPI chỉ có torch tối đa 2.2.2 cho kiến
trúc này** (Apple đã ngừng build torch mới hơn cho Intel Mac từ lâu, nên KHÔNG thể "nâng torch
lên" trên máy này; **Windows/Apple Silicon/Linux thường không bị giới hạn này** vì PyPI vẫn có
torch mới cho các nền tảng đó, nhưng vẫn nên ghim như dưới đây để transcript ra đồng nhất giữa
cả 4 người). `transformers` tự tắt tích hợp torch mà không báo lỗi rõ ràng ngay, đến lúc chạy ASR
thật mới vỡ ra lỗi này. Hướng sửa đúng là ghim `transformers` xuống dưới bản bắt đầu ép version,
không phải cố nâng torch. Các script `run_web`/`asr_parallel` (cả `.sh` và `.ps1`) bản hiện tại
đã tự phát hiện + tự cài lại đúng version khi chạy; nếu vẫn còn lỗi, chạy tay:

```bash
python3.11 -m pip install --user --upgrade --force-reinstall "numpy<2" torch torchaudio "transformers>=4.40,<4.50"
```

(đổi `python3.11` thành đúng bản Python máy bạn dùng, xem dòng "Dùng interpreter" khi chạy script)

```powershell
py -3.11 -m pip install --user --upgrade --force-reinstall "numpy<2" torch torchaudio "transformers>=4.40,<4.50"
```

(Windows — đổi `-3.11` thành đúng bản Python máy bạn dùng)

Nếu chạy trong thư mục `~/Downloads` trên macOS, gặp thêm lỗi `PermissionError: [Errno 1]
Operation not permitted` khi chạy `pip` — đó là macOS chặn quyền Files & Folders cho Terminal vào
Downloads, không liên quan torch. Chuyển thư mục ra ngoài (vd. `mv ~/Downloads/aic2026-asr-worker
~/`) rồi chạy lại, hoặc cấp quyền Downloads cho Terminal trong System Settings → Privacy &
Security → Files and Folders. (Windows không có kiểu chặn quyền thư mục này.)

**Windows riêng:** nếu chạy `.ps1` báo lỗi kiểu "không thể tải vì không được ký số" / "running
scripts is disabled on this system" — đó là chính sách Execution Policy mặc định của Windows,
xem lại bước 4 ở mục Cài đặt phía trên (`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy
RemoteSigned`). Nếu vẫn không đổi được (máy công ty/trường bị khoá chính sách), chạy tạm 1 lần
không cần đổi policy vĩnh viễn:
```powershell
powershell -ExecutionPolicy Bypass -File .\run_all.ps1 duong
```

## Dành cho trưởng nhóm — gộp kết quả lại vào repo chính

Sau khi nhận đủ 4 file zip từ Dương, Khoa, Tiến, Kiên, giải nén từng file rồi copy đè thư mục
`data/processed/transcripts/` của từng người vào `aic2026-project/data/processed/transcripts/`
(không trùng `video_id` giữa các người nên copy đè an toàn). Zip tạo bởi `package_results.ps1`
trên Windows có cùng cấu trúc thư mục bên trong với bản `.sh` (`data/processed/transcripts/...`)
nên lệnh gộp dưới đây dùng chung được, không cần phân biệt file zip đến từ máy nào:

```bash
cd aic2026-project
for f in transcripts_duong_*.zip transcripts_khoa_*.zip transcripts_tien_*.zip transcripts_kien_*.zip; do
  unzip -o -q "$f" -d /tmp/asr_merge
  cp -R /tmp/asr_merge/data/processed/transcripts/. data/processed/transcripts/
  rm -rf /tmp/asr_merge
done
ls data/processed/transcripts | wc -l   # kiểm tra đủ số video
```

## Lưu ý cấu hình

`config.yaml` trong package này set sẵn giống hệt mặc định của `aic2026-project` (engine
`transformers`, model `wav2vec2-base-vietnamese-250h`/`whisper-small`, `chunk_length_s: 20`).
**Không đổi giá trị trong file này** trừ khi cả team thống nhất đổi chung, vì lệch cấu hình
giữa các máy (model khác nhau, chunk khác nhau) sẽ khiến transcript của từng phần không đồng
nhất khi gộp lại.
