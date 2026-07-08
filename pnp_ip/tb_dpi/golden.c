/* ===========================================================================
 * golden.c -- DPI-C reference model for mac_dut.
 *
 * DPI type mapping: SystemVerilog `int` <-> C `int` (both 32-bit, 2-state,
 * passed by value). Plain scalar int args need NO svdpi.h include; you only
 * need svdpi.h for open arrays, packed vectors wider than 64 bits, strings,
 * or 4-state (logic) arguments.
 *
 * Built by scripts\run_sim.ps1 via: xsc golden.c   -> dpi library "dpi"
 * ===========================================================================
 */

/* one MAC step: returns acc + a*b, wrapping at 32 bits like the RTL */
int golden_mac(int acc, int a, int b)
{
    return acc + a * b;
}

/* === USER C FUNCTIONS START ===
 * Add more reference-model functions here, then import them in tb_dpi.sv.
 * === USER C FUNCTIONS END === */
