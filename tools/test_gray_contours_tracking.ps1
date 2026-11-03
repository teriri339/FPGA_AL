param(
    [string]$ModelSimBin = 'D:/Electric/modelsim_ase/win32aloem',
    [string]$TdRoot = 'D:/ALKJ'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$output = Join-Path $env:TEMP ('gray_tracking_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
$hdl = Join-Path $repo 'reference_edge_project/user_source/hdl_source/hx1p35_port'
$vendor = Join-Path $TdRoot 'sim_release/ph1p'
Push-Location -LiteralPath $output
try {
    & (Join-Path $ModelSimBin 'vlib.exe') work
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $ModelSimBin 'vlog.exe') -sv `
        (Join-Path $vendor 'ph1p_logic_eram.v') `
        (Join-Path $vendor 'ph1p_phy_eram.v') `
        (Join-Path $vendor 'ph1p_phy_gsr.v') `
        (Join-Path $hdl 'hx_vision_pipeline.v') `
        (Join-Path $hdl 'hx_template_tracker.v') `
        (Join-Path $hdl 'hx_button_mode_ctrl.v') `
        (Join-Path $hdl 'anlogic_logo_rom.v') `
        (Join-Path $repo 'tests/tb_gray_contours_tracking.sv') `
        (Join-Path $repo 'tests/tb_tracking_search_range.sv') `
        (Join-Path $repo 'tests/tb_tracking_continuity.sv') `
        (Join-Path $repo 'tests/tb_adaptive_tracking.sv') `
        (Join-Path $repo 'tests/tb_display_mode_cycle.sv') `
        (Join-Path $repo 'tests/tb_motion_prediction.sv')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    function Invoke-Check($name, $parameters, $passText) {
        $log = $name + '.log'
        & (Join-Path $ModelSimBin 'vsim.exe') -c -l $log @parameters `
            -do 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0' *> $null
        if ($LASTEXITCODE -ne 0 -or
            (Select-String -LiteralPath $log -Pattern '\*\* Fatal:|\*\* Error:') -or
            !(Select-String -LiteralPath $log -SimpleMatch $passText)) {
            Get-Content -LiteralPath $log -Tail 20
            throw "Simulation failed: $name"
        }
        Select-String -LiteralPath $log -SimpleMatch $passText
    }
    foreach ($sharp in 0,1) {
        foreach ($denoise in 0,1) {
            Invoke-Check "gray_s${sharp}_d${denoise}" @("-gSHARP=$sharp", "-gDENOISE=$denoise", 'work.tb_gray_contours_tracking', 'work.PH1P_PHY_GSR') 'PASS gray'
        }
    }
    Invoke-Check 'motion' @('work.tb_motion_prediction', 'work.PH1P_PHY_GSR') 'PASS motion prediction'
    Invoke-Check 'adaptive' @('work.tb_adaptive_tracking', 'work.PH1P_PHY_GSR') 'PASS adaptive tracking'
    Invoke-Check 'wide' @('work.tb_tracking_search_range', 'work.PH1P_PHY_GSR') 'PASS wider tracking window'
    Invoke-Check 'wide720' @('-gW=1280', '-gH=720', '-gROW_IDLE=370', '-gONLY_720P=1', 'work.tb_tracking_search_range', 'work.PH1P_PHY_GSR') 'PASS wider tracking window'
    Invoke-Check 'modes' @('work.tb_display_mode_cycle', 'work.PH1P_PHY_GSR') 'PASS RAW/GRAY/CANNY'
    Invoke-Check 'continuity' @('work.tb_tracking_continuity', 'work.PH1P_PHY_GSR') 'PASS tracking continuity'
    Invoke-Check 'continuity720' @('-gW=1280', '-gH=720', '-gROW_IDLE=370', '-gLONG_FRAMES=0', 'work.tb_tracking_continuity', 'work.PH1P_PHY_GSR') 'PASS tracking continuity'
    Write-Output "Logs: $output"
} finally {
    Pop-Location
}
