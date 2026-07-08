# =============================================================================
# run_sim.ps1 -- compile + elaborate + run ONE block's testbench with xsim.
#
# Usage (from D:\design_plans\pnp_ip):
#   powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 <block_folder>
#   powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 <block_folder> -Gui
#
# Rules this script assumes (the whole repo follows them):
#   - every block folder contains exactly one tb_*.sv ; its module name equals
#     its file basename and it is the simulation top.
#   - all *.sv in the folder are compiled; *.c files (DPI) are built with xsc.
#   - artifacts land in build\<block>\ , including <top>.wdb waveform database.
#   - xvlog gets -d SIMULATION so RTL may use `ifdef SIMULATION fences.
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Block,
    [switch]$Gui
)
$ErrorActionPreference = "Stop"
$Root      = Split-Path $PSScriptRoot -Parent
$VivadoBin = "D:\AMDDesignTools\2025.2\Vivado\bin"

$BlockDir = Join-Path $Root $Block
if (-not (Test-Path $BlockDir)) { throw "no such block folder: $BlockDir" }
$BuildDir = Join-Path $Root "build\$Block"
New-Item -ItemType Directory -Force $BuildDir | Out-Null

$Sv = Get-ChildItem $BlockDir -Filter *.sv | ForEach-Object { $_.FullName }
$C  = @(Get-ChildItem $BlockDir -Filter *.c | ForEach-Object { $_.FullName })
$TbFile = Get-ChildItem $BlockDir -Filter tb_*.sv | Select-Object -First 1
if ($null -eq $TbFile) { throw "no tb_*.sv found in $BlockDir" }
$Top = $TbFile.BaseName

Push-Location $BuildDir
try {
    Write-Host "=== [$Block] xvlog ==="
    & "$VivadoBin\xvlog.bat" --sv -d SIMULATION $Sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

    $SvLib = @()
    if ($C.Count -gt 0) {
        Write-Host "=== [$Block] xsc (DPI C) ==="
        & "$VivadoBin\xsc.bat" $C
        if ($LASTEXITCODE -ne 0) { throw "xsc failed" }
        $SvLib = @("-sv_lib", "dpi")
    }

    Write-Host "=== [$Block] xelab top=$Top ==="
    & "$VivadoBin\xelab.bat" $Top -s "${Top}_snap" -debug typical -timescale 1ns/1ps @SvLib
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

    if ($Gui) {
        & "$VivadoBin\xsim.bat" "${Top}_snap" -gui
    } else {
        Write-Host "=== [$Block] xsim run ==="
        $RunTcl = (Join-Path $Root "scripts\xsim_run.tcl") -replace '\\','/'
        & "$VivadoBin\xsim.bat" "${Top}_snap" -tclbatch $RunTcl -wdb "${Top}.wdb"
        if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
        Write-Host "waveform: build\$Block\${Top}.wdb  (open: scripts\run_sim.ps1 $Block -Gui, or xsim -gui <wdb>)"
    }
} finally { Pop-Location }
