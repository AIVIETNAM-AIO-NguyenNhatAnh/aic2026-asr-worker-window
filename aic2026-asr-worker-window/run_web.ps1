# run_web.ps1 - Ban Windows cua run_web.sh: chay Web UI keo-tha video xem transcript ASR
# (web_app.py) bang dung 1 Python interpreter, tu cai goi con thieu.
#
# Dung: .\run_web.ps1
#       .\run_web.ps1 -Port 5058

param(
  [int]$Port
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
Set-Location $ScriptDir
. (Join-Path $ScriptDir "_common.ps1")

$PythonExe = Find-Python
if (-not $PythonExe) {
  Write-Host "[run_web.ps1] Khong tim thay Python nao tren may." -ForegroundColor Red
  exit 1
}

Ensure-Module -PythonExe $PythonExe -Module "flask" -PipPackage @("flask")
Ensure-Module -PythonExe $PythonExe -Module "yaml" -PipPackage @("pyyaml")
if (-not (Ensure-AsrStack -PythonExe $PythonExe)) {
  Write-Host "[run_web.ps1] Bo torch/torchaudio/transformers loi, xem chi tiet o tren." -ForegroundColor Red
  exit 1
}

if (-not (Test-FfmpegBinary)) { exit 1 }

Write-Host "[run_web.ps1] Dung interpreter: $PythonExe"

$pyArgs = @((Join-Path $ScriptDir "web_app.py"))
if ($Port) { $pyArgs += @("--port", $Port) }
& $PythonExe @pyArgs
