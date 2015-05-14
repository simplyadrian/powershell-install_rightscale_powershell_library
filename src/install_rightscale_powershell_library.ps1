# Powershell 2.0


# Stop and fail script when a command fails.
$ErrorActionPreference = "Stop"

Write-Output "Installing RightScale Powershell library..."

$rsLibDstDirPath = "$env:rs_sandbox_home\RightScript\lib"
$rsLibTgzPath = Join-Path "$env:RS_ATTACH_DIR" "RsPsLib.tgz"

Write-Output "Extracting to ${rsLibDstDirPath}..."

if (-not(Test-Path "$rsLibDstDirPath"))
{
    md "$rsLibDstDirPath" | Out-Null
}

cd "$rsLibDstDirPath"
tar -xzf "$rsLibTgzPath"

Write-Output "Installing DNS providers' modules..."

# Create modules folder
$modulesFolder = "$env:windir\system32\WindowsPowershell\v1.0\modules"

cd "$env:RS_ATTACH_DIR"

if (-not (Test-Path $modulesFolder))
{
    mkdir -force "$modulesFolder"
}
if (-not (Test-Path "$modulesFolder\RaxHelpers"))
{
    mkdir -force "$modulesFolder\RaxHelpers"
    copy ".\RaxHelpers.dll" "$modulesFolder\RaxHelpers"
    copy ".\RaxHelpers.psm1" "$modulesFolder\RaxHelpers"
}

if (-not (Test-Path "$modulesFolder\Route53Tools"))
{
    mkdir -force "$modulesFolder\Route53Tools"
    Copy-Item -Force "$env:RS_ATTACH_DIR\Route53Tools.psm1" "$modulesFolder\Route53Tools"
}

# Put curl ca cert bundle if missing (fix for RL sandbox 5.8)
$curlPath = 'C:\Program Files (x86)\RightScale\RightLink\sandbox\shell\bin'
if ((Test-Path "${curlPath}\curl.exe") -and (-not (Test-Path "${curlPath}\curl-ca-bundle.crt")))
{
    Copy-Item -Force "$env:RS_ATTACH_DIR\curl-ca-bundle.crt" $curlPath
}
