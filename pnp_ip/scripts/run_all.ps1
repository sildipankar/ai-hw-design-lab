# Regression: simulate every block, then synthesize every synthesizable top.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\run_all.ps1 [-SkipSynth]
param([switch]$SkipSynth)
$Root = Split-Path $PSScriptRoot -Parent

$SimBlocks = @("axi_lite_regs","axi_full_slave","universal_top","tb_universal","tb_dpi","async_fifo","cdc_pack","axis_src_sink")
# block -> synth top ("" = sim-only deliverable, skip synth)
$SynthTops = [ordered]@{
    "axi_lite_regs"  = "axi_lite_regs"
    "axi_full_slave" = "axi_full_slave"
    "universal_top"  = "universal_top"
    "tb_universal"   = "example_dut"
    "tb_dpi"         = "mac_dut"
    "async_fifo"     = "async_fifo"
    "cdc_pack"       = "cdc_example_top"
    "axis_src_sink"  = "axis_example_top"
}

$Fail = @()
foreach ($b in $SimBlocks) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_sim.ps1") $b | Tee-Object -Variable out | Out-Null
    if (($LASTEXITCODE -ne 0) -or (-not ($out -match "TB PASS"))) { $Fail += "sim:$b" }
    Write-Host ("sim  {0,-15} {1}" -f $b, $(if ($Fail -contains "sim:$b") {"FAIL"} else {"PASS"}))
}
if (-not $SkipSynth) {
    foreach ($b in $SynthTops.Keys) {
        $t = $SynthTops[$b]
        if ($t -eq "") { continue }
        & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_synth.ps1") $b $t | Out-Null
        if ($LASTEXITCODE -ne 0) { $Fail += "synth:$b" }
        Write-Host ("syn  {0,-15} {1}" -f $b, $(if ($Fail -contains "synth:$b") {"FAIL"} else {"OK"}))
    }
}
if ($Fail.Count -eq 0) { Write-Host "REGRESSION PASS" } else { Write-Host "REGRESSION FAIL: $($Fail -join ', ')"; exit 1 }
