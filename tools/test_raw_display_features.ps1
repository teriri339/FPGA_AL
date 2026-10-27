param(
    [string]$ModelSimBin = 'D:/modelsim/modelsim_ase/win32aloem',
    [string]$TdRoot = 'D:/AnlogicTD-HX1P35A',
    [string]$LogoVectorDirectory = 'D:/Downloads/qiansai/tmp/example_logo_vectors_20261017_a',
    [string]$OutputDirectory = '',
    [string[]]$Tests = @('tb_ae_anti_flicker','tb_ae_cdc_coherency','tb_sc520_i2c_ce','tb_reset_release','tb_template_display_smooth','tb_template_fast_resource_equivalence','tb_template_fast_resource_720p','tb_template_fast_phases','tb_coarse_pyramid','tb_template_fast_reacquire','tb_coarse_720p','tb_template_global_equivalence','tb_template_fast_720p','tb_template_fast_overlay','tb_template_global_overlay','tb_template_global_reacquire','tb_template_global_720p_schedule','tb_template_far_equivalence','tb_template_far_reacquire','tb_template_resource_equivalence','tb_template_expanded_reacquire','tb_template_pipeline_equivalence','tb_template_reacquire','tb_template_diagnostics','tb_template_debug_osd','tb_template_tracker','tb_template_buttons','tb_template_overlay','tb_button_sharpen','tb_sensor_applied_cdc','tb_uics520_applied_status','tb_picture_ae','tb_raw_sharpen','tb_raw_sharpen_720p_timing','tb_raw_sharpen_full_width','tb_picture_quality','tb_vision_edge_modes','tb_logo_osd','tb_canny_noise','tb_target_tracking')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Split-Path -Parent $repoRoot) ('tmp/raw_display_features_' + [guid]::NewGuid().ToString('N'))
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Choose a new output directory; existing results are never overwritten.' }
foreach ($exe in @('vlib.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSimBin $exe))) { throw "Missing ModelSim executable: $exe" }
}
if (-not (Test-Path -LiteralPath (Join-Path $LogoVectorDirectory 'logo_expected.mem'))) { throw 'Missing generated Anlogic Logo vectors.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
Push-Location -LiteralPath $OutputDirectory
try {
    & (Join-Path $ModelSimBin 'vlib.exe') work
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    $vendor = Join-Path $TdRoot 'sim_release/ph1p'
    $hdl = Join-Path $repoRoot 'reference_edge_project/user_source/hdl_source'
    & (Join-Path $ModelSimBin 'vlog.exe') -sv `
        (Join-Path $vendor 'ph1p_logic_eram.v') `
        (Join-Path $vendor 'ph1p_phy_eram.v') `
        (Join-Path $vendor 'ph1p_phy_gsr.v') `
        (Join-Path $hdl 'hx1p35_port/hx_vision_pipeline.v') `
        (Join-Path $hdl 'hx1p35_port/hx_template_tracker.v') `
        (Join-Path $repoRoot 'tests/hx_template_tracker_legacy.v') `
        (Join-Path $repoRoot 'tests/hx_template_tracker_serial_ref.v') `
        (Join-Path $repoRoot 'tests/hx_template_tracker_resource_ref.v') `
        (Join-Path $repoRoot 'tests/hx_template_tracker_far_ref.v') `
        (Join-Path $repoRoot 'tests/hx_template_tracker_global_ref.v') `
        (Join-Path $repoRoot 'tests/hx_template_tracker_fast_ref.v') `
        (Join-Path $hdl 'hx1p35_port/anlogic_logo_rom.v') `
        (Join-Path $hdl 'hx1p35_port/hx_button_mode_ctrl.v') `
        (Join-Path $hdl 'uics520_cfg/SC520GainTbl.v') `
        (Join-Path $hdl 'uics520_cfg/uics520regAE.v') `
        (Join-Path $hdl 'uics520_cfg/uics520reg_720p60.v') `
        (Join-Path $hdl 'uics520_cfg/uicfgcs520.v') `
        (Join-Path $hdl 'uics500_cfg/uii2c.v') `
        (Join-Path $hdl 'uiisp_beta/ae_set.v') `
        (Join-Path $repoRoot 'tests/tb_raw_sharpen.sv') `
        (Join-Path $repoRoot 'tests/tb_button_sharpen.sv') `
        (Join-Path $repoRoot 'tests/tb_template_tracker.sv') `
        (Join-Path $repoRoot 'tests/tb_template_reacquire.sv') `
        (Join-Path $repoRoot 'tests/tb_template_expanded_reacquire.sv') `
        (Join-Path $repoRoot 'tests/tb_template_far_reacquire.sv') `
        (Join-Path $repoRoot 'tests/tb_template_global_reacquire.sv') `
        (Join-Path $repoRoot 'tests/tb_template_fast_reacquire.sv') `
        (Join-Path $repoRoot 'tests/tb_template_fast_resource_equivalence.sv') `
        (Join-Path $repoRoot 'tests/tb_template_display_smooth.sv') `
        (Join-Path $repoRoot 'tests/tb_coarse_720p.sv') `
        (Join-Path $repoRoot 'tests/tb_template_resource_equivalence.sv') `
        (Join-Path $repoRoot 'tests/tb_template_pipeline_equivalence.sv') `
        (Join-Path $repoRoot 'tests/tb_template_buttons.sv') `
        (Join-Path $repoRoot 'tests/tb_template_overlay.sv') `
        (Join-Path $repoRoot 'tests/tb_sensor_applied_cdc.sv') `
        (Join-Path $repoRoot 'tests/tb_reset_release.sv') `
        (Join-Path $repoRoot 'tests/tb_uics520_applied_status.sv') `
        (Join-Path $repoRoot 'tests/tb_sc520_i2c_ce.sv') `
        (Join-Path $repoRoot 'tests/tb_picture_ae.sv') `
        (Join-Path $repoRoot 'tests/tb_ae_anti_flicker.sv') `
        (Join-Path $repoRoot 'tests/tb_ae_cdc_coherency.sv') `
        (Join-Path $repoRoot 'tests/tb_picture_quality.sv') `
        (Join-Path $repoRoot 'tests/tb_vision_edge_modes.sv') `
        (Join-Path $repoRoot 'tests/tb_logo_osd.sv') `
        (Join-Path $repoRoot 'tests/tb_canny_noise.sv') `
        (Join-Path $repoRoot 'tests/tb_target_tracking.sv')
    if ($LASTEXITCODE -ne 0) { throw 'RTL compilation failed' }

    foreach ($test in $Tests) {
        $module = if ($test -in @('tb_raw_sharpen_720p_timing','tb_raw_sharpen_full_width')) { 'tb_raw_sharpen' } elseif ($test -in @('tb_template_global_overlay','tb_template_fast_overlay')) { 'tb_template_overlay' } elseif($test -in @('tb_template_fast_720p','tb_template_fast_phases')) { 'tb_template_fast_reacquire' } elseif($test -eq 'tb_template_fast_resource_720p') { 'tb_template_fast_resource_equivalence' } else { $test }
        $args = @('-c', '-l', "$test.log", "work.$module")
        if ($test -in @('tb_template_debug_osd','tb_template_overlay','tb_template_global_overlay','tb_template_fast_overlay','tb_raw_sharpen', 'tb_raw_sharpen_720p_timing', 'tb_raw_sharpen_full_width', 'tb_picture_quality', 'tb_vision_edge_modes', 'tb_logo_osd', 'tb_canny_noise', 'tb_target_tracking')) { $args += 'work.PH1P_PHY_GSR' }
        if ($test -eq 'tb_template_global_overlay') { $args += '-gGLOBAL_SCENARIO=1' }
        if ($test -eq 'tb_template_fast_overlay') { $args += '-gGLOBAL_SCENARIO=2' }
        if ($test -in @('tb_template_fast_720p','tb_template_fast_resource_720p')) { $args += @('-gW=1280','-gH=720','-gROW_IDLE=370','-gONLY_720P=1') }
        if ($test -eq 'tb_template_fast_phases') { $args += '-gONLY_PHASES=1' }
        if ($test -eq 'tb_raw_sharpen_720p_timing') { $args += '-gROW_IDLE_CYCLES=1586' } # 64 active + 1586 blank = 1650 clocks/line.
        if ($test -eq 'tb_raw_sharpen_full_width') { $args += @('-gW=1280','-gROW_IDLE_CYCLES=370') }
        if ($test -eq 'tb_logo_osd') { $args += @('-gQUALITY_ENABLE=0', "-gVECTOR_DIR=$LogoVectorDirectory") }
        if ($test -eq 'tb_target_tracking') { $args += @('-gHOLD_FRAMES=10') }
        & (Join-Path $ModelSimBin 'vsim.exe') @args -do 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath "$test.log" -Pattern '\*\* (Error|Fatal):' -Quiet) -or -not (Select-String -LiteralPath "$test.log" -Pattern '# PASS|PASS ' -Quiet)) { throw "Failed: $test (see $OutputDirectory/$test.log)" }
    }
    Write-Output "RAW display feature and selected regression tests passed. Logs: $OutputDirectory"
} finally {
    Pop-Location
}
