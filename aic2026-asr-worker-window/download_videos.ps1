# download_videos.ps1 - Ban Windows cua download_videos.sh: tai DUNG PHAN video duoc giao cho
# 1 thanh vien lam ASR (14 file Videos_*.zip cua batch 1 AIC 2026 chia cho 4 nguoi - xem
# README.md muc "Phan cong"). Giai nen, gom video ra data\raw\, xoa zip ngay sau khi giai nen.
#
# Dung: .\download_videos.ps1 duong   (hoac khoa / tien / kien)
# Muon tai danh sach khac, truyen thang ten file:
#   .\download_videos.ps1 Videos_L21_a.zip Videos_L22_a.zip

param(
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
  [string[]]$FileArgs
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "_common.ps1")

$BaseUrl = "https://aic-data.ledo.io.vn"
$RawDir  = Join-Path $ScriptDir "data\raw"
$TmpDir  = Join-Path $env:TEMP ("aic_asr_dl_" + [guid]::NewGuid().ToString("N"))

# Phan cong 14 file cho 4 thanh vien lam ASR - chia deu nhat co the (4/4/3/3).
$duong = @("Videos_L21_a.zip", "Videos_L22_a.zip", "Videos_L23_a.zip", "Videos_L24_a.zip")
$khoa  = @("Videos_L25_a.zip", "Videos_L26_a.zip", "Videos_L26_b.zip", "Videos_L26_c.zip")
$tien  = @("Videos_L26_d.zip", "Videos_L26_e.zip", "Videos_L27_a.zip")
$kien  = @("Videos_L28_a.zip", "Videos_L29_a.zip", "Videos_L30_a.zip")

if (-not $FileArgs -or $FileArgs.Count -eq 0) {
  Write-Host "Dung: .\download_videos.ps1 duong   (hoac khoa / tien / kien, hoac liet ke ten file zip cu the)" -ForegroundColor Red
  exit 1
}

switch ($FileArgs[0]) {
  "duong"  { $Files = $duong }
  "khoa"   { $Files = $khoa }
  "tien"   { $Files = $tien }
  "kien"   { $Files = $kien }
  default  { $Files = $FileArgs }
}

Write-Host ">>> Se tai $($Files.Count) file: $($Files -join ', ')"

if (-not (Test-Aria2cBinary)) { exit 1 }

New-Item -ItemType Directory -Force -Path $RawDir | Out-Null
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

try {
  foreach ($fname in $Files) {
    Write-Host ">>> Tai $fname ..."
    & aria2c -x 16 -s 16 -k 1M --retry-wait=3 --max-tries=5 -d "$TmpDir" -o "$fname" "$BaseUrl/$fname"
    if ($LASTEXITCODE -ne 0) { throw "aria2c loi khi tai $fname (ma loi $LASTEXITCODE)" }

    Write-Host ">>> Giai nen $fname ..."
    $extractDir = Join-Path $TmpDir "extract"
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Expand-Archive -Path (Join-Path $TmpDir $fname) -DestinationPath $extractDir -Force

    Get-VideoFiles -Path $extractDir -Recurse | ForEach-Object {
      $dest = Join-Path $RawDir $_.Name
      if (-not (Test-Path $dest)) {
        Move-Item -Path $_.FullName -Destination $dest
      }
    }

    Remove-Item -Recurse -Force $extractDir
    Remove-Item -Force (Join-Path $TmpDir $fname)
    Write-Host ">>> Xong $fname"
  }
} finally {
  Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

$nVideos = (Get-VideoFiles -Path $RawDir).Count
Write-Host ""
Write-Host "Hoan tat. $nVideos video dang co trong $RawDir."
