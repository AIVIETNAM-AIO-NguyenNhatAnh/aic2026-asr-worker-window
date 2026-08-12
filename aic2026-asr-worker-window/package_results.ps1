# package_results.ps1 - Ban Windows cua package_results.sh: nen toan bo data\processed\transcripts\
# (transcript .json da chay ASR) thanh 1 file zip de gui lai cho truong nhom - KHONG nen
# data\raw\ (video goc) hay data\processed\_audio_tmp\ (file wav tam).
#
# Dung: .\package_results.ps1 duong   (ten file zip se co "duong" + ngay gio)

param(
  [string]$Label = "ketqua"
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$TranscriptsDir = Join-Path $ScriptDir "data\processed\transcripts"
$Stamp = Get-Date -Format "yyyyMMdd_HHmm"
$Out = Join-Path $ScriptDir "transcripts_${Label}_${Stamp}.zip"

if (-not (Test-Path $TranscriptsDir) -or (Get-ChildItem $TranscriptsDir -File -ErrorAction SilentlyContinue).Count -eq 0) {
  Write-Host "[package_results.ps1] data\processed\transcripts dang trong - chay asr_parallel.ps1 (hoac run_asr.py) truoc." -ForegroundColor Red
  exit 1
}

# Dung thu muc tam de giu DUNG cau truc "data\processed\transcripts\..." ben trong file zip
# (giong het ban zip tao boi package_results.sh tren Mac/Linux) - de lenh gop ket qua cua
# truong nhom trong README.md dung chung cho ca 2 he dieu hanh, khong can phan biet.
$stageRoot = Join-Path $env:TEMP ("aic_asr_pkg_" + [guid]::NewGuid().ToString("N"))
$stageTarget = Join-Path $stageRoot "data\processed\transcripts"
New-Item -ItemType Directory -Force -Path $stageTarget | Out-Null
Copy-Item -Path (Join-Path $TranscriptsDir "*") -Destination $stageTarget -Recurse -Force

try {
  Compress-Archive -Path (Join-Path $stageRoot "data") -DestinationPath $Out -Force
} finally {
  Remove-Item -Recurse -Force $stageRoot -ErrorAction SilentlyContinue
}

$nFiles = (Get-ChildItem $TranscriptsDir -File -Filter *.json).Count
Write-Host "[package_results.ps1] Da dong goi $nFiles transcript -> $Out"
Write-Host "[package_results.ps1] Gui file nay (qua Zalo/Google Drive/email) cho truong nhom."
