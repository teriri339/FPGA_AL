param(
    [Parameter(Mandatory=$true)][string]$BuildDirectory,
    [string]$ModelSimBin='D:/modelsim/modelsim_ase/win32aloem',
    [string]$TdRoot='D:/AnlogicTD-HX1P35A'
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$BuildDirectory=(Resolve-Path -LiteralPath $BuildDirectory).Path
$simDirectory=Join-Path $BuildDirectory 'raw_sim'
if(Test-Path -LiteralPath $simDirectory){throw 'Simulation directory already exists; preserve existing results.'}
$manifest=Get-Content -LiteralPath (Join-Path $BuildDirectory 'history_manifest.json') -Raw|ConvertFrom-Json
if($manifest.commit -ne 'a7676fbfb8569ebb0560f09fd4550c02f762d45d'){throw 'This test targets only historical a7676fb RTL.'}
New-Item -ItemType Directory -Path $simDirectory|Out-Null
Push-Location -LiteralPath $simDirectory
try{
    & (Join-Path $ModelSimBin 'vlib.exe') work
    if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    $hdl=Join-Path $BuildDirectory 'source/reference_edge_project/user_source/hdl_source/hx1p35_port'
    $vendor=Join-Path $TdRoot 'sim_release/ph1p'
    & (Join-Path $ModelSimBin 'vlog.exe') -sv `
        (Join-Path $vendor 'ph1p_logic_eram.v') (Join-Path $vendor 'ph1p_phy_eram.v') (Join-Path $vendor 'ph1p_phy_gsr.v') `
        (Join-Path $hdl 'hx_pixel_stream_adapter.v') (Join-Path $hdl 'hx_vision_pipeline.v') `
        (Join-Path $repoRoot 'tests/tb_history_raw_compare.sv')
    if($LASTEXITCODE -ne 0){throw 'Historical RTL compilation failed'}
    & (Join-Path $ModelSimBin 'vsim.exe') -c -l history_raw.log work.tb_history_raw_compare work.PH1P_PHY_GSR `
        -do 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath history_raw.log -Pattern 'PASS historical a7676fb:' -Quiet)){throw 'Historical RAW regression failed'}
    Write-Output "Historical RAW regression passed: $simDirectory"
}finally{Pop-Location}
