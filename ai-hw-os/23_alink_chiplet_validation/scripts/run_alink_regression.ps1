# Run one A-Link testbench or all seven with Vivado XSim.
param(
    [ValidateSet("all", "axm_engine", "axs_regs", "axs_mem", "axil_reg_slice", "axm_chiplet", "axs_chiplet", "alink_top")]
    [string]$Module = "all",
    [switch]$Gui,
    [string]$VivadoBin = $(if ($env:VIVADO_BIN) { $env:VIVADO_BIN } else { "D:\AMDDesignTools\2025.2\Vivado\bin" })
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent

$Lists = [ordered]@{
    "axm_engine" = @("rtl\alink\axm_engine.sv", "sva\axm_engine_sva.sv", "tb\axm_engine_tb.sv")
    "axs_regs" = @("rtl\alink\axs_regs.sv", "sva\axs_regs_sva.sv", "tb\axs_regs_tb.sv")
    "axs_mem" = @("tb\beh\sram_bank.sv", "rtl\alink\axs_mem.sv", "sva\axs_mem_sva.sv", "tb\axs_mem_tb.sv")
    "axil_reg_slice" = @("rtl\common_ip\skid_buffer.sv", "rtl\alink\axil_reg_slice.sv", "sva\axil_reg_slice_sva.sv", "tb\axil_reg_slice_tb.sv")
    "axm_chiplet" = @("rtl\alink\axm_engine.sv", "tb\beh\cmd_gen.sv", "tb\beh\axil_pmon.sv", "tb\beh\axm_core.sv", "rtl\alink\axm_chiplet.sv", "sva\axm_chiplet_sva.sv", "tb\axm_chiplet_tb.sv")
    "axs_chiplet" = @("tb\beh\sram_bank.sv", "rtl\alink\axs_regs.sv", "rtl\alink\axs_mem.sv", "tb\beh\axs_dec.sv", "tb\beh\axs_bank.sv", "rtl\alink\axs_chiplet.sv", "sva\axs_chiplet_sva.sv", "tb\axs_chiplet_tb.sv")
    "alink_top" = @("tb\beh\reset_sync.sv", "tb\beh\sram_bank.sv", "tb\beh\cmd_gen.sv", "tb\beh\axil_pmon.sv", "tb\beh\axs_dec.sv", "tb\beh\axs_bank.sv", "tb\beh\axm_core.sv", "rtl\common_ip\skid_buffer.sv", "rtl\alink\axm_engine.sv", "rtl\alink\axs_regs.sv", "rtl\alink\axs_mem.sv", "rtl\alink\axil_reg_slice.sv", "rtl\alink\axm_chiplet.sv", "rtl\alink\axs_chiplet.sv", "rtl\alink\alink_top.sv", "sva\alink_top_sva.sv", "tb\alink_top_tb.sv")
}

function Invoke-AlinkTest([string]$Name) {
    Write-Host "`n========== A-Link test: $Name =========="
    $sources = $Lists[$Name] | ForEach-Object {
        $path = Join-Path $Root $_
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing source: $path" }
        $path
    }
    $top = "${Name}_tb"
    $buildDir = Join-Path $Root "build\$Name"
    New-Item -ItemType Directory -Force $buildDir | Out-Null

    Push-Location $buildDir
    try {
        & (Join-Path $VivadoBin "xvlog.bat") --sv -d SIMULATION -i (Join-Path $Root "tb\beh") $sources
        if ($LASTEXITCODE -ne 0) { throw "xvlog failed for $Name" }
        & (Join-Path $VivadoBin "xelab.bat") $top -s "${top}_snap" -debug typical -timescale 1ns/1ps
        if ($LASTEXITCODE -ne 0) { throw "xelab failed for $Name" }
        if ($Gui) {
            & (Join-Path $VivadoBin "xsim.bat") "${top}_snap" -gui
        } else {
            $runTcl = (Join-Path $Root "scripts\xsim_run.tcl") -replace '\\', '/'
            & (Join-Path $VivadoBin "xsim.bat") "${top}_snap" -tclbatch $runTcl -wdb "${top}.wdb"
            if ($LASTEXITCODE -ne 0) { throw "xsim failed for $Name" }
        }
    } finally {
        Pop-Location
    }
}

if ($Gui -and $Module -eq "all") { throw "-Gui requires one specific -Module." }
if ($Module -eq "all") {
    foreach ($name in $Lists.Keys) { Invoke-AlinkTest $name }
    Write-Host "`nAll seven A-Link tests completed successfully."
} else {
    Invoke-AlinkTest $Module
}

# END run_alink_regression.ps1
