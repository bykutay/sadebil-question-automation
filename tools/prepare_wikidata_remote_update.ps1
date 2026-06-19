param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$Python = "python",
    [string]$BaseDir = (Join-Path $env:TEMP "sadebil_generated_assets_base"),
    [string]$WikidataDir = (Join-Path $env:TEMP "sadebil_wikidata_assets"),
    [string]$RemoteDir = (Join-Path $env:TEMP "sadebil_remote_questions_site"),
    [string]$AndroidRoot = "",
    [string]$Version = "",
    [int]$WikidataPerDifficulty = 250,
    [switch]$SkipWikidataNetwork
)

$ErrorActionPreference = "Stop"

if (-not $Version) {
    $Version = "wikidata-" + (Get-Date -Format "yyyy-MM-dd-HHmm")
}

if (-not (Test-Path -LiteralPath $Python)) {
    $Python = "python"
}

$generator = Join-Path $Root "tools\generate_offline_questions.ps1"
$wikidata = Join-Path $Root "tools\generate_wikidata_questions.py"
$merge = Join-Path $Root "tools\merge_wikidata_remote_bank.py"
$audit = Join-Path $Root "tools\audit_question_quality.py"
if (-not $AndroidRoot) {
    $AndroidRoot = $Root
}

Write-Host "1/5 Base soru bankası hazırlanıyor: $BaseDir"
$env:SADEBIL_GENERATED_ASSETS = $BaseDir
powershell -ExecutionPolicy Bypass -File $generator -Root $Root -PerCategory 3000 | Write-Host

Write-Host "2/5 Wikidata kaynaklı soru bankası hazırlanıyor: $WikidataDir"
if (Test-Path -LiteralPath $WikidataDir) {
    Remove-Item -LiteralPath $WikidataDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WikidataDir | Out-Null

$wikiArgs = @(
    $wikidata,
    "--root", $AndroidRoot,
    "--asset-dir", $WikidataDir,
    "--target-per-difficulty", $WikidataPerDifficulty,
    "--mix-size", "3000",
    "--langs", "tr,en"
)
if ($SkipWikidataNetwork) {
    $wikiArgs += "--skip-network"
}
& $Python @wikiArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Wikidata üretimi uyarıyla bitti; eksikler base bankadan tamamlanacak."
}

Write-Host "3/5 Wikidata + base banka birleştiriliyor: $RemoteDir"
if (Test-Path -LiteralPath $RemoteDir) {
    Remove-Item -LiteralPath $RemoteDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $RemoteDir | Out-Null
& $Python $merge `
    --base-dir $BaseDir `
    --wikidata-dir $WikidataDir `
    --out-dir $RemoteDir `
    --version $Version `
    --wikidata-per-difficulty $WikidataPerDifficulty

Write-Host "4/5 Kalite kontrol çalışıyor."
$env:SADEBIL_GENERATED_ASSETS = $RemoteDir
& $Python $audit $androidRoot

Write-Host "5/5 Remote klasör hazır."
Get-ChildItem -Recurse $RemoteDir |
    Where-Object { -not $_.PSIsContainer } |
    Select-Object FullName, Length |
    Sort-Object FullName

Write-Host "Hazır: $RemoteDir"
