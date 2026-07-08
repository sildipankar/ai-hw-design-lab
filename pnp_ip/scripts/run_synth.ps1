# =============================================================================
# run_synth.ps1 -- wrapper: batch-synthesize one block with scripts\synth.tcl.
#
# Usage (from D:\design_plans\pnp_ip):
#   powershell -ExecutionPolicy Bypass -File scripts\run_synth.ps1 <block> <top_module> [part]
# Example:
#   powershell -ExecutionPolicy Bypass -File scripts\run_synth.ps1 axi_lite_regs axi_lite_regs
#
# Logs + reports land in build\synth_<block>\ .
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Block,
    [Parameter(Mandatory=$true)][string]$Top,
    [string]$Part = ""
)
$ErrorActionPreference = "Stop"
$Root      = Split-Path $PSScriptRoot -Parent
$VivadoBin = "D:\AMDDesignTools\2025.2\Vivado\bin"

$BuildDir = Join-Path $Root "build\synth_$Block"
New-Item -ItemType Directory -Force $BuildDir | Out-Null

$TclArgs = @((Join-Path $Root $Block), $Top)
if ($Part -ne "") { $TclArgs += $Part }

Push-Location $BuildDir
try {
    & "$VivadoBin\vivado.bat" -mode batch -source (Join-Path $Root "scripts\synth.tcl") -tclargs @TclArgs
    if ($LASTEXITCODE -ne 0) { throw "vivado synth failed for $Block ($Top)" }
} finally { Pop-Location }
