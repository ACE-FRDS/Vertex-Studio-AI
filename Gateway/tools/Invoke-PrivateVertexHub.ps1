param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Snapshot', 'StageText', 'Apply', 'Rollback')]
    [string]$Action,

    [string]$RelativePath,
    [string]$RequestFile,
    [string]$RequestId,
    [string]$ReceiptFile,
    [string]$ApprovedBy
)

$ErrorActionPreference = 'Stop'

$Workspace = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource'
$ControlRoot = 'G:\Vertex_Project\Vertex_Studio_AI\Gateway\private-hub'

Set-Location $Workspace

switch ($Action) {
    'Snapshot' {
        if ([string]::IsNullOrWhiteSpace($RelativePath)) {
            throw '-RelativePath is required for Snapshot.'
        }

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            snapshot $Workspace $RelativePath

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub Snapshot failed with exit code $LASTEXITCODE"
        }
    }

    'StageText' {
        if ([string]::IsNullOrWhiteSpace($RequestFile)) {
            throw '-RequestFile is required for StageText.'
        }

        $resolved = (Resolve-Path $RequestFile).Path

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            stage-text $Workspace $ControlRoot $resolved

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub StageText failed with exit code $LASTEXITCODE"
        }
    }

    'Apply' {
        if ([string]::IsNullOrWhiteSpace($RequestId)) {
            throw '-RequestId is required for Apply.'
        }

        if ([string]::IsNullOrWhiteSpace($ApprovedBy)) {
            throw '-ApprovedBy is required for Apply. Human Gate cannot be implicit.'
        }

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            apply $Workspace $ControlRoot $RequestId $ApprovedBy

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub Apply failed with exit code $LASTEXITCODE"
        }
    }

    'Rollback' {
        if ([string]::IsNullOrWhiteSpace($ReceiptFile)) {
            throw '-ReceiptFile is required for Rollback.'
        }

        if ([string]::IsNullOrWhiteSpace($ApprovedBy)) {
            throw '-ApprovedBy is required for Rollback. Human Gate cannot be implicit.'
        }

        $resolved = (Resolve-Path $ReceiptFile).Path

        & cargo run -q -p vsa-vertex-hub --bin private_hub -- `
            rollback $Workspace $ControlRoot $resolved $ApprovedBy

        if ($LASTEXITCODE -ne 0) {
            throw "Private VertexHub Rollback failed with exit code $LASTEXITCODE"
        }
    }
}
