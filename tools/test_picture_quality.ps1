param(
    [string]$ModelSimBin='D:/modelsim/modelsim_ase/win32aloem',
    [string]$TdRoot='D:/AnlogicTD-HX1P35A',
    [string]$LogoVectorDirectory='D:/Downloads/qiansai/tmp/example_logo_vectors_20261017_a',
    [string]$OutputDirectory=''
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
if(-not $OutputDirectory){$OutputDirectory=Join-Path (Split-Path -Parent $repoRoot) ('tmp/picture_quality_sim_'+[guid]::NewGuid().ToString('N'))}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Choose a new output directory; existing results are preserved.'}
if(-not(Test-Path -LiteralPath (Join-Path $LogoVectorDirectory 'logo_expected.mem'))){throw 'Generate official logo vectors with tools/prepare_example_logo_verification.py first.'}
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
Push-Location -LiteralPath $OutputDirectory
try{
    & (Join-Path $ModelSimBin 'vlib.exe') work
    if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    $vendor=Join-Path $TdRoot 'sim_release/ph1p'
    $hdl=Join-Path $repoRoot 'reference_edge_project/user_source/hdl_source'
    & (Join-Path $ModelSimBin 'vlog.exe') -sv `
        (Join-Path $vendor 'ph1p_logic_eram.v') (Join-Path $vendor 'ph1p_phy_eram.v') (Join-Path $vendor 'ph1p_phy_gsr.v') `
        (Join-Path $hdl 'hx1p35_port/hx_vision_pipeline.v') (Join-Path $hdl 'hx1p35_port/anlogic_logo_rom.v') `
        (Join-Path $hdl 'uiisp_beta/ae_set.v') `
        (Join-Path $repoRoot 'tests/tb_picture_quality.sv') (Join-Path $repoRoot 'tests/tb_picture_ae.sv') `
        (Join-Path $repoRoot 'tests/tb_logo_osd.sv') (Join-Path $repoRoot 'tests/tb_vision_edge_modes.sv') `
        (Join-Path $repoRoot 'tests/tb_canny_noise.sv')
    if($LASTEXITCODE -ne 0){throw 'RTL compilation failed'}
    foreach($test in @('tb_picture_ae','tb_picture_quality','tb_vision_edge_modes','tb_logo_osd','tb_canny_noise')){
        $testArgs=@('-c','-l',"$test.log", "work.$test",'work.PH1P_PHY_GSR')
        if($test -eq 'tb_logo_osd'){$testArgs+=@('-gQUALITY_ENABLE=0',"-gVECTOR_DIR=$LogoVectorDirectory")}
        & (Join-Path $ModelSimBin 'vsim.exe') @testArgs -do 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'
        if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath "$test.log" -Pattern '# PASS ' -Quiet)){throw "Failed: $test"}
    }
    Write-Output "Picture-quality regression passed: $OutputDirectory"
}finally{Pop-Location}
