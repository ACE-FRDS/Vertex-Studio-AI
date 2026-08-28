#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Root = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$Executor = Join-Path $Root 'VERTEX_ENV_2_PACKAGE_LIFECYCLE_EXECUTOR_V1_1_RECEIPT_VERIFY.ps1'
$Ownership = Join-Path $Root 'VERTEX_ENV_2_PACKAGE_OWNERSHIP_V1_2.ps1'
$Manifest = Join-Path $Root 'VERTEX_ENV_2_PACKAGE_MANIFEST_OWNERSHIP_POSITIVE_V1.json'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V1.3 — OWNERSHIP POSITIVE CASE' -ForegroundColor Magenta
Write-Host ' NEW ASSET -> RECEIPT -> OWNERSHIP PROOF' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

foreach($file in @($Executor,$Ownership,$Manifest)){
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){
        throw "Required file missing: $file"
    }
}

Write-Host "`n[1/5] DRY RUN" -ForegroundColor Yellow
& $Executor -ManifestPath $Manifest

Write-Host "`n[2/5] EXECUTE" -ForegroundColor Yellow
& $Executor -ManifestPath $Manifest -Mode Execute -Approval 'APPROVE-ENV2'

$ReportRoot='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'
$Receipt = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_ENV2_RECEIPT.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if(-not $Receipt){ throw 'Execution receipt not found.' }

Write-Host "`n[3/5] PHYSICAL VERIFY" -ForegroundColor Yellow
$Target = 'D:\Vertex_Deployment_Sandbox\_vertex_owned_positive_20260823_194709'
if(-not(Test-Path -LiteralPath $Target -PathType Container)){
    throw "Physical verification RED: $Target"
}
Write-Host "Target exists: $Target" -ForegroundColor Green

Write-Host "`n[4/5] OWNERSHIP AUDIT" -ForegroundColor Yellow
& $Ownership -ManifestPath $Manifest -ExecutionReceiptPath $Receipt.FullName

Write-Host "`n[5/5] OWNERSHIP REGISTER" -ForegroundColor Yellow
& $Ownership -ManifestPath $Manifest -ExecutionReceiptPath $Receipt.FullName -Mode Register -Approval 'APPROVE-OWNERSHIP'

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host ' ENV-2 V1.3 POSITIVE OWNERSHIP CASE COMPLETE' -ForegroundColor Green
Write-Host " Target: $Target" -ForegroundColor Green
Write-Host ' Expected: VERTEX_CREATED / rollback_eligible=True' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
