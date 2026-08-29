$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PluginRoot = Join-Path $ProjectRoot "packages\gakuji_paddle_ocr"
$PluginAndroid = Join-Path $PluginRoot "android"

# Mirror PaddleOCR's official Android layout. Kotlin files under src/main/java
# compile normally with the Kotlin Android plugin and this avoids the source-set
# ambiguity that caused the first Gakuji integration build to miss com.paddle.ocr.
$SdkDestination = Join-Path $PluginAndroid "src\main\java\com\paddle\ocr"
$StaleSdkDestination = Join-Path $PluginAndroid "src\main\kotlin\com\paddle\ocr"
$AssetsRoot = Join-Path $PluginAndroid "src\main\assets\models"
$ThirdPartyRoot = Join-Path $PluginRoot "third_party"
$WorkRoot = Join-Path $env:TEMP "gakuji_paddleocr_android_setup"
$RepoRoot = Join-Path $WorkRoot "PaddleOCR"

$DetUrl = "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_det_onnx_infer.tar"
$RecUrl = "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv5_mobile_rec_onnx_infer.tar"
$LicenseUrl = "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/LICENSE"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Download-File([string]$Url, [string]$Destination) {
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Extract-Model([string]$Archive, [string]$Destination) {
    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    & tar -xf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed while extracting $Archive"
    }
}

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description was not found: $Path"
    }
}

Require-Command "git"
Require-Command "tar"

if (Test-Path $WorkRoot) {
    Remove-Item $WorkRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

Write-Host "Fetching the official PaddleOCR Android SDK source..."
git clone --depth 1 --filter=blob:none --sparse https://github.com/PaddlePaddle/PaddleOCR.git $RepoRoot
if ($LASTEXITCODE -ne 0) {
    throw "Could not clone PaddleOCR."
}

Push-Location $RepoRoot
try {
    git sparse-checkout set deploy/ppocr-android/ppocr-sdk
    if ($LASTEXITCODE -ne 0) {
        throw "Could not configure the PaddleOCR sparse checkout."
    }
} finally {
    Pop-Location
}

$OfficialSdk = Join-Path $RepoRoot "deploy\ppocr-android\ppocr-sdk"
$OfficialSource = Join-Path $OfficialSdk "src\main\java\com\paddle\ocr"

$RequiredOfficialFiles = @(
    (Join-Path $OfficialSource "PaddleOCR.kt"),
    (Join-Path $OfficialSource "PaddleOCRConfig.kt"),
    (Join-Path $OfficialSource "EngineConfig.kt"),
    (Join-Path $OfficialSource "model\OCRResult.kt"),
    (Join-Path $OfficialSource "util\OpenCVUtils.kt")
)

foreach ($RequiredFile in $RequiredOfficialFiles) {
    Assert-File $RequiredFile "Required PaddleOCR SDK source"
}

# Remove the old v1 install location so it cannot create duplicate classes.
if (Test-Path $StaleSdkDestination) {
    Write-Host "Removing stale PaddleOCR source location: $StaleSdkDestination"
    Remove-Item $StaleSdkDestination -Recurse -Force
}

if (Test-Path $SdkDestination) {
    Remove-Item $SdkDestination -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $SdkDestination | Out-Null
Copy-Item -Path (Join-Path $OfficialSource "*") -Destination $SdkDestination -Recurse -Force

$InstalledChecks = @(
    (Join-Path $SdkDestination "PaddleOCR.kt"),
    (Join-Path $SdkDestination "PaddleOCRConfig.kt"),
    (Join-Path $SdkDestination "EngineConfig.kt"),
    (Join-Path $SdkDestination "model\OCRResult.kt"),
    (Join-Path $SdkDestination "util\OpenCVUtils.kt")
)
foreach ($InstalledFile in $InstalledChecks) {
    Assert-File $InstalledFile "Installed PaddleOCR SDK source"
}

$InstalledSourceCount = (Get-ChildItem -Path $SdkDestination -Filter "*.kt" -Recurse | Measure-Object).Count
if ($InstalledSourceCount -lt 10) {
    throw "PaddleOCR SDK install looks incomplete: only $InstalledSourceCount Kotlin files were copied."
}
Write-Host "Installed $InstalledSourceCount PaddleOCR Kotlin source files." -ForegroundColor Green

$OfficialProguard = Join-Path $OfficialSdk "proguard-rules.pro"
if (Test-Path $OfficialProguard) {
    Copy-Item $OfficialProguard (Join-Path $PluginAndroid "proguard-rules.pro") -Force
}

New-Item -ItemType Directory -Force -Path $ThirdPartyRoot | Out-Null
Download-File $LicenseUrl (Join-Path $ThirdPartyRoot "PaddleOCR_LICENSE.txt")

$DetAssets = Join-Path $AssetsRoot "det"
$RecAssets = Join-Path $AssetsRoot "rec"
$ExistingDetOnnx = Join-Path $DetAssets "inference.onnx"
$ExistingRecOnnx = Join-Path $RecAssets "inference.onnx"
$ExistingRecYaml = Join-Path $RecAssets "inference.yml"

$ModelsAlreadyInstalled =
    (Test-Path -LiteralPath $ExistingDetOnnx -PathType Leaf) -and
    (Test-Path -LiteralPath $ExistingRecOnnx -PathType Leaf) -and
    (Test-Path -LiteralPath $ExistingRecYaml -PathType Leaf)

if ($ModelsAlreadyInstalled) {
    Write-Host "PP-OCRv5 mobile model assets already exist; keeping them." -ForegroundColor Green
} else {
    $DetArchive = Join-Path $WorkRoot "PP-OCRv5_mobile_det_onnx_infer.tar"
    $RecArchive = Join-Path $WorkRoot "PP-OCRv5_mobile_rec_onnx_infer.tar"
    $DetExtract = Join-Path $WorkRoot "det"
    $RecExtract = Join-Path $WorkRoot "rec"

    Download-File $DetUrl $DetArchive
    Download-File $RecUrl $RecArchive
    Extract-Model $DetArchive $DetExtract
    Extract-Model $RecArchive $RecExtract

    $DetOnnx = Get-ChildItem -Path $DetExtract -Filter "inference.onnx" -Recurse | Select-Object -First 1
    $RecOnnx = Get-ChildItem -Path $RecExtract -Filter "inference.onnx" -Recurse | Select-Object -First 1
    $RecYaml = Get-ChildItem -Path $RecExtract -Filter "inference.yml" -Recurse | Select-Object -First 1

    if ($null -eq $DetOnnx) {
        throw "PP-OCRv5 mobile detection inference.onnx was not found in the downloaded archive."
    }
    if ($null -eq $RecOnnx -or $null -eq $RecYaml) {
        throw "PP-OCRv5 mobile recognition inference.onnx/inference.yml was not found in the downloaded archive."
    }

    New-Item -ItemType Directory -Force -Path $DetAssets | Out-Null
    New-Item -ItemType Directory -Force -Path $RecAssets | Out-Null
    Copy-Item $DetOnnx.FullName $ExistingDetOnnx -Force
    Copy-Item $RecOnnx.FullName $ExistingRecOnnx -Force
    Copy-Item $RecYaml.FullName $ExistingRecYaml -Force
}

Assert-File $ExistingDetOnnx "Detection model"
Assert-File $ExistingRecOnnx "Recognition model"
Assert-File $ExistingRecYaml "Recognition YAML"

Write-Host ""
Write-Host "PaddleOCR Android repair/setup complete." -ForegroundColor Green
Write-Host "SDK source root: $SdkDestination"
Write-Host "Model assets:    $AssetsRoot"
Write-Host ""
Write-Host "Verified entry point:"
Write-Host "  $(Join-Path $SdkDestination 'PaddleOCR.kt')"
Write-Host ""
Write-Host "Next run:"
Write-Host "  flutter clean"
Write-Host "  flutter pub get"
Write-Host "  flutter run"
