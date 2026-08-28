#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.12 — PRODUCT LINEAGE BOUNDARY GATE
READ ONLY / ZERO MUTATION

Consumes latest V2.4.11 version-lineage report and enforces stricter
product-lineage boundaries before any remediation can become eligible.

Principle:
  Newer version != valid replacement.
  Same vendor != same product.
  Same executable leaf != same role.
  Remediation eligibility requires identity + role + context + lineage.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.12 — PRODUCT LINEAGE BOUNDARY GATE' -ForegroundColor Magenta
Write-Host ' VENDOR -> PRODUCT -> ROLE -> CONTEXT -> VERSION LINEAGE' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_VERSION_LINEAGE_NORMALIZATION.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    throw 'No V2.4.11 version-lineage report found.'
}

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60
$candidates = @($data.candidates)

Write-Host "Source     : $($source.FullName)"
Write-Host "Candidates : $($candidates.Count)"

function Normalize-Path {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().Trim('"').Replace('/','\').ToLowerInvariant()
}

function Get-ExecutableRole {
    param(
        [AllowNull()][string]$Path,
        [AllowNull()][string]$DisplayName
    )

    $leaf = ''
    if ($Path) {
        try { $leaf = [IO.Path]::GetFileName($Path).ToLowerInvariant() } catch {}
    }

    $text = "$leaf $DisplayName".ToLowerInvariant()

    switch -Regex ($text) {
        'filemaker pro\.exe'      { return 'PRIMARY_APPLICATION' }
        'rider64\.exe|pycharm64\.exe|webstorm64\.exe|datagrip64\.exe|idea64\.exe|rustrover64\.exe' { return 'PRIMARY_IDE' }
        'adobe premiere pro\.exe' { return 'PRIMARY_APPLICATION' }
        'streamdeck\.exe'         { return 'PRIMARY_APPLICATION' }
        'ue4editor\.exe|ue5editor\.exe' { return 'PRIMARY_EDITOR' }
        'nginx\.exe'              { return 'SERVER_DAEMON' }
        'msedgewebview2\.exe'     { return 'WEBVIEW_RUNTIME' }
        'steamwebhelper\.exe'     { return 'HELPER_RUNTIME' }
        'epicwebhelper\.exe'      { return 'HELPER_RUNTIME' }
        'node20?\.exe'            { return 'NODE_RUNTIME' }
        'javaw?\.exe'             { return 'JAVA_RUNTIME' }
        'acsetup\.exe'            { return 'INSTALLER_UPDATER' }
        'epfwupd\.exe'            { return 'FIRMWARE_UPDATER' }
        'eneasyapp\.exe'          { return 'NETWORK_SETUP_TOOL' }
        default                   { return 'UNKNOWN_ROLE' }
    }
}

function Get-InstallContext {
    param([AllowNull()][string]$Path)

    $p = Normalize-Path $Path
    if (-not $p) { return 'UNKNOWN_CONTEXT' }

    switch -Regex ($p) {
        '\\temp\\|\\appdata\\local\\temp\\' { return 'TEMPORARY' }
        '\\toolbox\\cache\\backup\\'        { return 'BACKUP_CACHE' }
        '\\steamapps\\common\\'             { return 'GAME_EMBEDDED' }
        '\\adobe\\.*\\jre\\'                { return 'EMBEDDED_RUNTIME' }
        '\\adobe\\.*\\libs\\node\.exe$'     { return 'EMBEDDED_RUNTIME' }
        '\\jetbrains\\.*\\acp-agents\\'     { return 'EMBEDDED_RUNTIME' }
        '\\codex\\runtimes\\'               { return 'EMBEDDED_RUNTIME' }
        '\\cache\\codex-runtimes\\'         { return 'EMBEDDED_RUNTIME' }
        '\\program files\\|\\program files \(x86\)\\' { return 'SYSTEM_INSTALL' }
        '\\appdata\\local\\programs\\'      { return 'USER_INSTALL' }
        '\\programdata\\'                   { return 'PROGRAMDATA_INSTALL' }
        default                             { return 'OTHER_CONTEXT' }
    }
}

function Get-CanonicalVendorProduct {
    param([object]$Best)

    if (-not $Best) {
        return [pscustomobject][ordered]@{
            old_vendor='UNKNOWN'
            new_vendor='UNKNOWN'
            old_product='UNKNOWN'
            new_product='UNKNOWN'
        }
    }

    return [pscustomobject][ordered]@{
        old_vendor = [string]$Best.old_vendor
        new_vendor = [string]$Best.new_vendor
        old_product = [string]$Best.old_product
        new_product = [string]$Best.new_product
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$i = 0

foreach ($c in $candidates) {
    $i++

    $best = $c.best_replacement
    $identityDecision = [string]$c.identity_decision
    $revisedDecision  = [string]$c.revised_decision
    $versionAssessment = [string]$c.version_assessment

    $oldPath = [string]$c.old_program
    $newPath = if ($best) { [string]$best.path } else { '' }

    $oldRole = Get-ExecutableRole -Path $oldPath -DisplayName ([string]$c.display_name)
    $newRole = Get-ExecutableRole -Path $newPath -DisplayName ([string]$c.display_name)

    $oldContext = Get-InstallContext -Path $oldPath
    $newContext = Get-InstallContext -Path $newPath

    $vp = Get-CanonicalVendorProduct -Best $best

    $reasons = [System.Collections.Generic.List[string]]::new()
    $guards  = [System.Collections.Generic.List[string]]::new()

    $vendorMatch = ($vp.old_vendor -ne 'UNKNOWN' -and $vp.old_vendor -eq $vp.new_vendor)
    $productMatch = ($vp.old_product -ne 'UNKNOWN' -and $vp.old_product -eq $vp.new_product)
    $roleMatch = ($oldRole -ne 'UNKNOWN_ROLE' -and $oldRole -eq $newRole)

    if ($vendorMatch) { $reasons.Add("Vendor match: $($vp.old_vendor)") }
    else { $guards.Add("Vendor boundary not satisfied: $($vp.old_vendor) -> $($vp.new_vendor)") }

    if ($productMatch) { $reasons.Add("Product match: $($vp.old_product)") }
    else { $guards.Add("Product boundary not satisfied: $($vp.old_product) -> $($vp.new_product)") }

    if ($roleMatch) { $reasons.Add("Executable role match: $oldRole") }
    else { $guards.Add("Executable role mismatch/unknown: $oldRole -> $newRole") }

    # Context compatibility rules
    $contextCompatible = $false

    if ($oldContext -eq $newContext) {
        $contextCompatible = $true
        $reasons.Add("Install context match: $oldContext")
    }
    elseif ($oldContext -eq 'SYSTEM_INSTALL' -and $newContext -eq 'USER_INSTALL') {
        $contextCompatible = $true
        $reasons.Add('Install context migration accepted: SYSTEM_INSTALL -> USER_INSTALL')
    }
    elseif ($oldContext -eq 'TEMPORARY' -and $newContext -in @('SYSTEM_INSTALL','USER_INSTALL','PROGRAMDATA_INSTALL')) {
        $contextCompatible = $true
        $reasons.Add("Temporary-to-installed migration accepted: $oldContext -> $newContext")
    }
    elseif ($oldContext -eq 'BACKUP_CACHE' -or $newContext -eq 'BACKUP_CACHE') {
        $guards.Add("Backup/cache context cannot establish replacement lineage: $oldContext -> $newContext")
    }
    elseif ($oldContext -eq 'EMBEDDED_RUNTIME' -or $newContext -eq 'EMBEDDED_RUNTIME') {
        $guards.Add("Embedded runtime boundary requires exact parent-product identity: $oldContext -> $newContext")
    }
    elseif ($oldContext -eq 'GAME_EMBEDDED' -or $newContext -eq 'GAME_EMBEDDED') {
        $guards.Add("Game-embedded context cannot replace unrelated application context: $oldContext -> $newContext")
    }
    else {
        $guards.Add("Install context not proven compatible: $oldContext -> $newContext")
    }

    $versionOK = $versionAssessment -in @('NEWER','SAME')
    if ($versionOK) {
        $reasons.Add("Version lineage accepted: $versionAssessment")
    } elseif ($versionAssessment -eq 'UNKNOWN') {
        $guards.Add('Version lineage unknown.')
    } elseif ($versionAssessment -eq 'OLDER') {
        $guards.Add('Replacement candidate is older after normalization.')
    }

    # Default safety state
    $final = 'HOLD_FOR_HUMAN'

    if (-not $best) {
        if ($revisedDecision -eq 'READY_FOR_HUMAN_APPROVAL') {
            $final = 'REMEDIATION_CANDIDATE_NO_REPLACEMENT'
        } else {
            $final = $revisedDecision
        }
    }
    elseif ($identityDecision -eq 'REPLACEMENT_REJECTED') {
        $final = 'REPLACEMENT_REJECTED'
    }
    elseif (
        $identityDecision -eq 'REPLACEMENT_CONFIRMED' -and
        $vendorMatch -and
        $productMatch -and
        $roleMatch -and
        $contextCompatible -and
        $versionOK
    ) {
        $final = 'REMEDIATION_ELIGIBLE'
    }
    elseif (
        $identityDecision -in @('REPLACEMENT_CONFIRMED','REPLACEMENT_PROBABLE') -and
        $vendorMatch -and
        $productMatch -and
        $roleMatch
    ) {
        $final = 'REPLACEMENT_VALID_BUT_HOLD'
    }
    else {
        $final = 'PRODUCT_LINEAGE_REJECTED'
    }

    # Hard guards for generic/embedded runtimes.
    if ($oldRole -in @('NODE_RUNTIME','JAVA_RUNTIME','HELPER_RUNTIME') -or
        $newRole -in @('NODE_RUNTIME','JAVA_RUNTIME','HELPER_RUNTIME')) {

        if (-not ($vendorMatch -and $productMatch -and $roleMatch -and $contextCompatible)) {
            $final = 'PRODUCT_LINEAGE_REJECTED'
            $guards.Add('Generic/helper runtime hard guard triggered.')
        }
    }

    # Backup cache must never become remediation proof.
    if ($newContext -eq 'BACKUP_CACHE' -and $final -eq 'REMEDIATION_ELIGIBLE') {
        $final = 'REPLACEMENT_VALID_BUT_HOLD'
        $guards.Add('Replacement located in backup cache; not eligible for automated remediation.')
    }

    $results.Add([pscustomobject][ordered]@{
        candidate_id          = [string]$c.candidate_id
        display_name          = [string]$c.display_name
        family                = [string]$c.family
        old_program           = $oldPath
        new_program           = $newPath
        old_vendor            = $vp.old_vendor
        new_vendor            = $vp.new_vendor
        old_product           = $vp.old_product
        new_product           = $vp.new_product
        old_role              = $oldRole
        new_role              = $newRole
        old_context           = $oldContext
        new_context           = $newContext
        identity_decision     = $identityDecision
        version_assessment    = $versionAssessment
        boundary_decision     = $final
        reasons               = @($reasons)
        guards                = @($guards)
        firewall_rule_names   = @($c.firewall_rule_names)
        mutation              = 'NONE'
    })

    Write-Progress -Activity 'Vertex Product Lineage Boundary Gate' `
        -Status "$i / $($candidates.Count) : $($c.display_name)" `
        -PercentComplete (($i / [Math]::Max(1,$candidates.Count)) * 100)
}

Write-Progress -Activity 'Vertex Product Lineage Boundary Gate' -Completed

$counts = [ordered]@{
    TOTAL                              = $results.Count
    REMEDIATION_ELIGIBLE               = @($results | Where-Object boundary_decision -eq 'REMEDIATION_ELIGIBLE').Count
    REPLACEMENT_VALID_BUT_HOLD         = @($results | Where-Object boundary_decision -eq 'REPLACEMENT_VALID_BUT_HOLD').Count
    PRODUCT_LINEAGE_REJECTED           = @($results | Where-Object boundary_decision -eq 'PRODUCT_LINEAGE_REJECTED').Count
    REPLACEMENT_REJECTED               = @($results | Where-Object boundary_decision -eq 'REPLACEMENT_REJECTED').Count
    REMEDIATION_CANDIDATE_NO_REPLACEMENT = @($results | Where-Object boundary_decision -eq 'REMEDIATION_CANDIDATE_NO_REPLACEMENT').Count
    HOLD_FOR_HUMAN                     = @($results | Where-Object boundary_decision -eq 'HOLD_FOR_HUMAN').Count
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' PRODUCT LINEAGE BOUNDARY SUMMARY'
Write-Host '============================================================'
Write-Host " Total                              : $($counts.TOTAL)"
Write-Host " Remediation eligible               : $($counts.REMEDIATION_ELIGIBLE)" -ForegroundColor Green
Write-Host " Replacement valid but hold         : $($counts.REPLACEMENT_VALID_BUT_HOLD)" -ForegroundColor Cyan
Write-Host " Product lineage rejected           : $($counts.PRODUCT_LINEAGE_REJECTED)" -ForegroundColor Yellow
Write-Host " Replacement rejected               : $($counts.REPLACEMENT_REJECTED)" -ForegroundColor Yellow
Write-Host " Candidate / no replacement         : $($counts.REMEDIATION_CANDIDATE_NO_REPLACEMENT)"
Write-Host " Hold for human                     : $($counts.HOLD_FOR_HUMAN)"

foreach ($r in $results) {
    if ($r.boundary_decision -in @('HOLD_FOR_HUMAN')) { continue }

    $color = switch ($r.boundary_decision) {
        'REMEDIATION_ELIGIBLE'               { 'Green' }
        'REPLACEMENT_VALID_BUT_HOLD'         { 'Cyan' }
        'REMEDIATION_CANDIDATE_NO_REPLACEMENT' { 'Yellow' }
        default                              { 'Gray' }
    }

    Write-Host ''
    Write-Host "[$($r.boundary_decision)] $($r.candidate_id) $($r.display_name)" -ForegroundColor $color
    Write-Host "  Old : $($r.old_program)"
    if ($r.new_program) { Write-Host "  New : $($r.new_program)" }
    Write-Host "  Vendor  : $($r.old_vendor) -> $($r.new_vendor)"
    Write-Host "  Product : $($r.old_product) -> $($r.new_product)"
    Write-Host "  Role    : $($r.old_role) -> $($r.new_role)"
    Write-Host "  Context : $($r.old_context) -> $($r.new_context)"
    Write-Host "  Version : $($r.version_assessment)"
    if (@($r.reasons).Count -gt 0) { Write-Host "  Why     : $($r.reasons -join ' | ')" }
    if (@($r.guards).Count -gt 0)  { Write-Host "  Guard   : $($r.guards -join ' | ')" }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $ReportRoot "VERTEX_PRODUCT_LINEAGE_BOUNDARY.$stamp.json"
$txt  = Join-Path $ReportRoot "VERTEX_PRODUCT_LINEAGE_BOUNDARY.$stamp.txt"

$report = [ordered]@{
    schema        = 'vertex.environment.product-lineage-boundary.v1'
    mission       = 'VERTEX_ENV_2_V2_4_12_PRODUCT_LINEAGE_BOUNDARY_GATE'
    generated_at  = (Get-Date).ToString('o')
    source_report = $source.FullName
    mode          = 'READ_ONLY'
    counts        = $counts
    candidates    = @($results)
    policy        = [ordered]@{
        same_vendor_is_enough       = $false
        same_product_is_enough      = $false
        same_executable_is_enough   = $false
        role_match_required         = $true
        context_compatibility       = 'REQUIRED'
        version_lineage             = 'REQUIRED_WHEN_AVAILABLE'
        generic_runtime_hard_guard  = 'ENABLED'
        backup_cache_as_proof       = 'DENIED'
        automatic_mutation          = 'DENIED'
        human_gate                  = 'REQUIRED'
        mutation                    = 'NONE'
    }
}

$report | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX ENV-2 V2.4.12 — PRODUCT LINEAGE BOUNDARY GATE',
    '============================================================',
    " Source                         : $($source.FullName)",
    " Total                          : $($counts.TOTAL)",
    " Remediation eligible           : $($counts.REMEDIATION_ELIGIBLE)",
    " Replacement valid but hold     : $($counts.REPLACEMENT_VALID_BUT_HOLD)",
    " Product lineage rejected       : $($counts.PRODUCT_LINEAGE_REJECTED)",
    " Replacement rejected           : $($counts.REPLACEMENT_REJECTED)",
    " Candidate / no replacement     : $($counts.REMEDIATION_CANDIDATE_NO_REPLACEMENT)",
    " Hold for human                 : $($counts.HOLD_FOR_HUMAN)",
    '',
    ' Automatic mutation             : DENIED',
    ' Human gate                     : REQUIRED',
    ' Transaction gate               : NEXT STAGE',
    '',
    " JSON                           : $json",
    " TXT                            : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.4.12 PRODUCT LINEAGE GATE : GREEN' -ForegroundColor Green
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
