param(
    [string]$ModelSimBin = 'D:/modelsim/modelsim_ase/win32aloem',
    [string]$TdRoot = 'D:/AnlogicTD-HX1P35A',
    [string]$OutputDirectory = '',
    [int[]]$HoldFrames = @(0, 1, 4, 10)
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Split-Path -Parent $repoRoot) ('tmp/target_tracking_sim_' + [guid]::NewGuid().ToString('N'))
}
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'Choose a new output directory; existing simulation files are never overwritten.'
}
foreach ($exe in @('vlib.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSimBin $exe))) { throw "Missing ModelSim executable: $exe" }
}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
Push-Location -LiteralPath $OutputDirectory
try {
    & (Join-Path $ModelSimBin 'vlib.exe') work
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    $hdl = Join-Path $repoRoot 'reference_edge_project/user_source/hdl_source/hx1p35_port'
    $vendor = Join-Path $TdRoot 'sim_release/ph1p'
    & (Join-Path $ModelSimBin 'vlog.exe') -sv `
        (Join-Path $vendor 'ph1p_logic_eram.v') `
        (Join-Path $vendor 'ph1p_phy_eram.v') `
        (Join-Path $vendor 'ph1p_phy_gsr.v') `
        (Join-Path $hdl 'hx_vision_pipeline.v') `
        (Join-Path $hdl 'anlogic_logo_rom.v') `
        (Join-Path $repoRoot 'tests/tb_target_tracking.sv')
    if ($LASTEXITCODE -ne 0) { throw 'RTL compilation failed' }
    foreach ($hold in $HoldFrames) {
        if ($hold -lt 0) { throw 'HoldFrames must be nonnegative' }
        $log = "target_tracking_hold$hold.log"
        & (Join-Path $ModelSimBin 'vsim.exe') -c "-gHOLD_FRAMES=$hold" -l $log `
            work.tb_target_tracking work.PH1P_PHY_GSR `
            -do 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'
        if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $log -Pattern "PASS target tracking HOLD=$hold`:" -Quiet)) {
            throw "Tracking test failed: HOLD=$hold (see $OutputDirectory/$log)"
        }
    }
    Write-Output "All requested tracking configurations passed. Logs: $OutputDirectory"
} finally {
    Pop-Location
}
