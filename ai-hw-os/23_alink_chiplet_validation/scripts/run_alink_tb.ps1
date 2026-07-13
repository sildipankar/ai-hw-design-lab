# =============================================================================
# run_tb.ps1 -- compile + elaborate + run ONE module's testbench with xsim.
#
# Usage (from D:\design_plans):
#   powershell -ExecutionPolicy Bypass -File scripts\run_tb.ps1 <module>
#   powershell -ExecutionPolicy Bypass -File scripts\run_tb.ps1 <module> -Gui
#
# Filelists below encode the blackbox rule: rtl\stubs\*.sv are NEVER compiled for
# sim; where a frontier-owned DUT instantiates a stubbed child, the TB-only
# behavioral model in tb\beh\ is compiled instead. Artifacts land in build\<module>\.
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Module,
    [switch]$Gui
)
$ErrorActionPreference = "Stop"
$Root      = Split-Path $PSScriptRoot -Parent
$VivadoBin = "D:\AMDDesignTools\2025.2\Vivado\bin"

$Lists = @{
  "rr_arbiter"     = @("rtl\common_ip\rr_arbiter.sv","sva\rr_arbiter_sva.sv","tb\rr_arbiter_tb.sv")
  "skid_buffer"    = @("rtl\common_ip\skid_buffer.sv","sva\skid_buffer_sva.sv","tb\skid_buffer_tb.sv")
  "pulse_sync"     = @("tb\beh\sync_2ff.sv","rtl\common_ip\pulse_sync.sv","sva\pulse_sync_sva.sv","tb\pulse_sync_tb.sv")
  "async_fifo"     = @("tb\beh\sync_2ff.sv","rtl\common_ip\async_fifo.sv","sva\async_fifo_sva.sv","tb\async_fifo_tb.sv")
  "axm_engine"     = @("rtl\alink\axm_engine.sv","sva\axm_engine_sva.sv","tb\axm_engine_tb.sv")
  "axs_regs"       = @("rtl\alink\axs_regs.sv","sva\axs_regs_sva.sv","tb\axs_regs_tb.sv")
  "axs_mem"        = @("tb\beh\sram_bank.sv","rtl\alink\axs_mem.sv","sva\axs_mem_sva.sv","tb\axs_mem_tb.sv")
  "axil_reg_slice" = @("rtl\common_ip\skid_buffer.sv","rtl\alink\axil_reg_slice.sv","sva\axil_reg_slice_sva.sv","tb\axil_reg_slice_tb.sv")
  "axm_chiplet"    = @("rtl\alink\axm_engine.sv","tb\beh\cmd_gen.sv","tb\beh\axil_pmon.sv","tb\beh\axm_core.sv","rtl\alink\axm_chiplet.sv","sva\axm_chiplet_sva.sv","tb\axm_chiplet_tb.sv")
  "axs_chiplet"    = @("tb\beh\sram_bank.sv","rtl\alink\axs_regs.sv","rtl\alink\axs_mem.sv","tb\beh\axs_dec.sv","tb\beh\axs_bank.sv","rtl\alink\axs_chiplet.sv","sva\axs_chiplet_sva.sv","tb\axs_chiplet_tb.sv")
  "alink_top"      = @("tb\beh\reset_sync.sv","tb\beh\sram_bank.sv","tb\beh\cmd_gen.sv","tb\beh\axil_pmon.sv","tb\beh\axs_dec.sv","tb\beh\axs_bank.sv","tb\beh\axm_core.sv",
                       "rtl\common_ip\skid_buffer.sv","rtl\alink\axm_engine.sv","rtl\alink\axs_regs.sv","rtl\alink\axs_mem.sv","rtl\alink\axil_reg_slice.sv",
                       "rtl\alink\axm_chiplet.sv","rtl\alink\axs_chiplet.sv","rtl\alink\alink_top.sv","sva\alink_top_sva.sv","tb\alink_top_tb.sv")
}

if (-not $Lists.ContainsKey($Module)) { throw "unknown module '$Module'. Known: $($Lists.Keys -join ', ')" }
$Sv  = $Lists[$Module] | ForEach-Object { Join-Path $Root $_ }
$Top = "${Module}_tb"

$BuildDir = Join-Path $Root "build\$Module"
New-Item -ItemType Directory -Force $BuildDir | Out-Null

Push-Location $BuildDir
try {
    Write-Host "=== [$Module] xvlog ==="
    $Inc = Join-Path $Root "tb\beh"
    & "$VivadoBin\xvlog.bat" --sv -d SIMULATION -i $Inc $Sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

    Write-Host "=== [$Module] xelab top=$Top ==="
    & "$VivadoBin\xelab.bat" $Top -s "${Top}_snap" -debug typical -timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

    if ($Gui) {
        & "$VivadoBin\xsim.bat" "${Top}_snap" -gui
    } else {
        Write-Host "=== [$Module] xsim run ==="
        $RunTcl = (Join-Path $Root "scripts\xsim_run.tcl") -replace '\\','/'
        & "$VivadoBin\xsim.bat" "${Top}_snap" -tclbatch $RunTcl -wdb "${Top}.wdb"
        if ($LASTEXITCODE -ne 0) { throw "xsim failed" }
        Write-Host "waveform: build\$Module\${Top}.wdb"
    }
} finally { Pop-Location }
