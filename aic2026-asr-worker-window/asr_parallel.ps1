# asr_parallel.ps1 - Ban Windows cua asr_parallel.sh: chay run_asr.py song song nhieu video
# cung luc. Mac dinh CHI 2 video song song (thap hon nhieu so voi buoc keyframe) vi moi tien
# trinh ASR tu nap lai 1 ban model wav2vec2/whisper rieng (vai tram MB - ~1GB RAM/tien trinh),
# chay qua nhieu cung luc de lam may do/swap. Tang so luong neu may nhieu RAM (>=16GB).
#
# Dung: .\asr_parallel.ps1          (mac dinh 2 luong song song)
#       .\asr_parallel.ps1 3        (ep chay dung 3 video cung luc)

param(
  [int]$Jobs = 2
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir "_common.ps1")

$PythonExe = Find-Python
if (-not $PythonExe) {
  Write-Host "[asr_parallel.ps1] Khong tim thay Python nao tren may." -ForegroundColor Red
  exit 1
}

Ensure-Module -PythonExe $PythonExe -Module "yaml" -PipPackage @("pyyaml")
if (-not (Ensure-AsrStack -PythonExe $PythonExe)) {
  Write-Host "[asr_parallel.ps1] Bo torch/torchaudio/transformers loi, xem chi tiet o tren." -ForegroundColor Red
  exit 1
}

if (-not (Test-FfmpegBinary)) { exit 1 }

Write-Host "[asr_parallel.ps1] Dung interpreter: $PythonExe"

$RawDir = Join-Path $ScriptDir "data\raw"
$videos = Get-VideoFiles -Path $RawDir
if ($videos.Count -eq 0) {
  Write-Host "[asr_parallel.ps1] $RawDir trong - chay '.\download_videos.ps1 <ten>' truoc (duong/khoa/tien/kien)." -ForegroundColor Red
  exit 1
}

Write-Host "[asr_parallel.ps1] $($videos.Count) video, chay song song $Jobs luong (moi luong nap rieng 1 ban model)..."

$configPath = Join-Path $ScriptDir "config.yaml"
$runAsrPath = Join-Path $ScriptDir "run_asr.py"

$jobsRunning = @()
foreach ($video in $videos) {
  while ($jobsRunning.Count -ge $Jobs) {
    Start-Sleep -Milliseconds 500
    $jobsRunning = @($jobsRunning | Where-Object { $_.Refresh(); -not $_.HasExited })
  }
  Write-Host "[asr_parallel.ps1] Bat dau: $($video.Name)"
  $argList = @("`"$runAsrPath`"", "--video", "`"$($video.FullName)`"", "--config", "`"$configPath`"")
  $p = Start-Process -FilePath $PythonExe -ArgumentList $argList -NoNewWindow -PassThru
  $jobsRunning += $p
}

foreach ($p in $jobsRunning) { $p.WaitForExit() }

Write-Host ""
Write-Host "[asr_parallel.ps1] Hoan tat. Kiem tra: (Get-ChildItem data\processed\transcripts -Filter *.json).Count"
