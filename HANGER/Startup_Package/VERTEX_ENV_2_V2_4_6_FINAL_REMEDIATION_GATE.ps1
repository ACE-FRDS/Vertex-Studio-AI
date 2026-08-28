#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.6 — FINAL REMEDIATION GATE
PLAN -> DEDUP -> REPLACEMENT EVIDENCE -> HUMAN GATE PREPARATION
READ ONLY / ZERO MUTATION

This stage DOES NOT delete, modify, enable, or disable firewall rules.
It consumes the newest V2.4.5 remediation plan, rechecks live evidence,
groups duplicate candidates, searches for likely replacement binaries,
and produces a gated execution manifest for a later mutation stage.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.6 — FINAL REMEDIATION GATE' -ForegroundColor Magenta
Write-Host ' PLAN -> DEDUP -> REPLACEMENT -> HUMAN GATE PREPARATION' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_HYGIENE_REMEDIATION_PLAN.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    throw 'No V2.4.5 remediation-plan JSON report found.'
}

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40
$rawCandidates = @($data.plan | Where-Object { $_.proposed_decision -eq 'LIKELY_REMOVE' })

Write-Host "Source            : $($source.FullName)"
Write-Host "Raw candidates    : $($rawCandidates.Count)"

function Normalize-ProgramPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return $Path.Trim().Trim('"').ToLowerInvariant()
}

function Get-Family {
    param([string]$DisplayName, [string]$Program)

    $s = "$DisplayName $Program"
    switch -Regex ($s) {
        '(?i)filemaker'                  { return 'FILEMAKER' }
        '(?i)rustrover'                  { return 'JETBRAINS_RUSTROVER' }
        '(?i)rider'                      { return 'JETBRAINS_RIDER' }
        '(?i)pycharm'                    { return 'JETBRAINS_PYCHARM' }
        '(?i)webstorm'                   { return 'JETBRAINS_WEBSTORM' }
        '(?i)datagrip'                   { return 'JETBRAINS_DATAGRIP' }
        '(?i)intellij|idea64'            { return 'JETBRAINS_INTELLIJ' }
        '(?i)edgewebview|msedgewebview2' { return 'EDGE_WEBVIEW2' }
        '(?i)nginx'                      { return 'NGINX' }
        '(?i)premiere'                   { return 'ADOBE_PREMIERE' }
        '(?i)creative cloud'             { return 'ADOBE_CREATIVE_CLOUD' }
        '(?i)javaw|openjdk|jdk-'         { return 'JAVA_JDK' }
        '(?i)steamwebhelper|steam'       { return 'STEAM' }
        '(?i)epicwebhelper|epic games'   { return 'EPIC' }
        '(?i)streamdeck|elgato'           { return 'STREAMDECK' }
        '(?i)epson'                      { return 'EPSON' }
        '(?i)armoury|asus|acsetup'       { return 'ASUS_ARMOURY' }
        '(?i)ldplayer|ld9box'             { return 'LDPLAYER' }
        '(?i)bignox|nox'                 { return 'NOX' }
        '(?i)node\.exe|node20\.exe'      { return 'NODE_RUNTIME' }
        default                          { return 'OTHER' }
    }
}

function Find-ReplacementEvidence {
    param(
        [string]$Family,
        [string]$OldProgram
    )

    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    $patterns = switch ($Family) {
        'FILEMAKER'            { @('FileMaker Pro.exe') }
        'JETBRAINS_RUSTROVER'  { @('rustrover64.exe') }
        'JETBRAINS_RIDER'      { @('rider64.exe') }
        'JETBRAINS_PYCHARM'    { @('pycharm64.exe') }
        'JETBRAINS_WEBSTORM'   { @('webstorm64.exe') }
        'JETBRAINS_DATAGRIP'   { @('datagrip64.exe') }
        'JETBRAINS_INTELLIJ'   { @('idea64.exe') }
        'EDGE_WEBVIEW2'        { @('msedgewebview2.exe') }
        'NGINX'                { @('nginx.exe') }
        'ADOBE_PREMIERE'       { @('Adobe Premiere Pro.exe') }
        'JAVA_JDK'             { @('javaw.exe') }
        'STEAM'                { @('steamwebhelper.exe') }
        'EPIC'                 { @('EpicWebHelper.exe') }
        'STREAMDECK'           { @('node20.exe','StreamDeck.exe') }
        default                { @() }
    }

    if ($patterns.Count -eq 0) { return @() }

    $hits = [System.Collections.Generic.List[string]]::new()

    foreach ($root in $roots) {
        foreach ($pattern in $patterns) {
            # Bound recursive discovery to common application roots. Access failures are ignored.
            try {
                Get-ChildItem -LiteralPath $root -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -First 10 |
                    ForEach-Object {
                        $p = $_.FullName
                        if ((Normalize-ProgramPath $p) -ne (Normalize-ProgramPath $OldProgram)) {
                            $hits.Add($p)
                        }
                    }
            } catch {}
        }
    }

    return @($hits | Select-Object -Unique)
}

# Deduplicate by program path + display name. Keep all firewall rule identities.
$groups = $rawCandidates | Group-Object {
    "$(Normalize-ProgramPath ([string]$_.program))|$(([string]$_.display_name).ToLowerInvariant())"
}

$gated = @()
$index = 0

foreach ($g in $groups) {
    $index++
    $items = @($g.Group)
    $first = $items[0]
    $program = [string]$first.program
    $display = [string]$first.display_name
    $family = Get-Family -DisplayName $display -Program $program
    $binaryExistsNow = $false

    if (-not [string]::IsNullOrWhiteSpace($program) -and $program -notin @('Any','System')) {
        $clean = $program.Trim().Trim('"')
        $binaryExistsNow = Test-Path -LiteralPath $clean -PathType Leaf -ErrorAction SilentlyContinue
    }

    $replacements = @()
    if (-not $binaryExistsNow) {
        $replacements = @(Find-ReplacementEvidence -Family $family -OldProgram $program)
    }

    $decision = 'HOLD_FOR_HUMAN'
    $confidence = 0.75
    $why = [System.Collections.Generic.List[string]]::new()

    if ($binaryExistsNow) {
        $decision = 'PROTECT_LIVE_RETURNED'
        $confidence = 0.99
        $why.Add('Previously missing binary now exists.')
    }
    elseif ($replacements.Count -gt 0) {
        $decision = 'REPLACEMENT_DETECTED'
        $confidence = 0.95
        $why.Add('Likely current/replacement executable detected.')
        $why.Add('Old firewall rule may be stale, but replacement context must be reviewed first.')
    }
    elseif ($family -in @('EDGE_WEBVIEW2','FILEMAKER','JETBRAINS_RUSTROVER','JETBRAINS_RIDER',
                          'JETBRAINS_PYCHARM','JETBRAINS_WEBSTORM','JETBRAINS_DATAGRIP',
                          'JETBRAINS_INTELLIJ','NGINX','JAVA_JDK','ADOBE_PREMIERE',
                          'ADOBE_CREATIVE_CLOUD','STEAM','EPIC','STREAMDECK')) {
        $decision = 'HOLD_FOR_HUMAN'
        $confidence = 0.90
        $why.Add('Known versioned/updatable application family.')
        $why.Add('No replacement executable was discovered in bounded application roots.')
    }
    else {
        $decision = 'READY_FOR_HUMAN_APPROVAL'
        $confidence = 0.92
        $why.Add('Binary remains absent.')
        $why.Add('V2.4.5 found no service, installed-app, or listener evidence.')
        $why.Add('No replacement executable detected by V2.4.6.')
    }

    $ruleNames = @($items | ForEach-Object { [string]$_.firewall_rule_name } | Select-Object -Unique)

    $gated += [pscustomobject][ordered]@{
        candidate_id = ('CAND-{0:D4}' -f $index)
        display_name = $display
        family = $family
        old_program = $program
        firewall_rule_names = $ruleNames
        duplicate_rule_count = $ruleNames.Count
        binary_exists_now = $binaryExistsNow
        replacement_paths = $replacements
        gate_decision = $decision
        confidence = $confidence
        reasons = @($why)
        human_approval_required = $true
        mutation = 'NONE'
    }
}

$counts = [ordered]@{
    RAW_LIKELY_REMOVE = $rawCandidates.Count
    UNIQUE_CANDIDATES = $gated.Count
    READY_FOR_HUMAN_APPROVAL = @($gated | Where-Object gate_decision -eq 'READY_FOR_HUMAN_APPROVAL').Count
    REPLACEMENT_DETECTED = @($gated | Where-Object gate_decision -eq 'REPLACEMENT_DETECTED').Count
    PROTECT_LIVE_RETURNED = @($gated | Where-Object gate_decision -eq 'PROTECT_LIVE_RETURNED').Count
    HOLD_FOR_HUMAN = @($gated | Where-Object gate_decision -eq 'HOLD_FOR_HUMAN').Count
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' FINAL REMEDIATION GATE SUMMARY'
Write-Host '============================================================'
Write-Host " Raw LIKELY_REMOVE        : $($counts.RAW_LIKELY_REMOVE)"
Write-Host " Unique candidates        : $($counts.UNIQUE_CANDIDATES)"
Write-Host " Ready for human approval : $($counts.READY_FOR_HUMAN_APPROVAL)" -ForegroundColor Yellow
Write-Host " Replacement detected     : $($counts.REPLACEMENT_DETECTED)" -ForegroundColor Cyan
Write-Host " Live returned / protect  : $($counts.PROTECT_LIVE_RETURNED)" -ForegroundColor Green
Write-Host " Hold for human           : $($counts.HOLD_FOR_HUMAN)"
Write-Host ''

foreach ($x in $gated) {
    $color = switch ($x.gate_decision) {
        'READY_FOR_HUMAN_APPROVAL' { 'Yellow' }
        'REPLACEMENT_DETECTED'     { 'Cyan' }
        'PROTECT_LIVE_RETURNED'    { 'Green' }
        default                    { 'Gray' }
    }
    Write-Host "[$($x.gate_decision)] $($x.candidate_id) $($x.display_name)" -ForegroundColor $color
    Write-Host "  Family       : $($x.family)"
    Write-Host "  Old Program  : $($x.old_program)"
    Write-Host "  Rule Count   : $($x.duplicate_rule_count)"
    if (@($x.replacement_paths).Count -gt 0) {
        Write-Host "  Replacement  : $($x.replacement_paths -join ' | ')"
    }
    Write-Host "  Reason       : $($x.reasons -join ' | ')"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $ReportRoot "VERTEX_FINAL_REMEDIATION_GATE.$stamp.json"
$txt  = Join-Path $ReportRoot "VERTEX_FINAL_REMEDIATION_GATE.$stamp.txt"

$report = [ordered]@{
    schema = 'vertex.environment.final-remediation-gate.v1'
    mission = 'VERTEX_ENV_2_V2_4_6_FINAL_REMEDIATION_GATE'
    generated_at = (Get-Date).ToString('o')
    source_report = $source.FullName
    mode = 'READ_ONLY'
    counts = $counts
    candidates = $gated
    execution_policy = [ordered]@{
        automatic_delete = 'DENIED'
        firewall_mutation = 'DENIED'
        human_gate = 'REQUIRED'
        pre_mutation_snapshot = 'REQUIRED'
        exact_rule_identity_match = 'REQUIRED'
        live_revalidation_immediately_before_mutation = 'REQUIRED'
        rollback_receipt = 'REQUIRED'
        post_mutation_audit = 'REQUIRED'
    }
}

$report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX ENV-2 V2.4.6 — FINAL REMEDIATION GATE',
    '============================================================',
    " Source                    : $($source.FullName)",
    " Raw LIKELY_REMOVE         : $($counts.RAW_LIKELY_REMOVE)",
    " Unique candidates         : $($counts.UNIQUE_CANDIDATES)",
    " Ready for human approval  : $($counts.READY_FOR_HUMAN_APPROVAL)",
    " Replacement detected      : $($counts.REPLACEMENT_DETECTED)",
    " Live returned / protect   : $($counts.PROTECT_LIVE_RETURNED)",
    " Hold for human            : $($counts.HOLD_FOR_HUMAN)",
    '',
    ' Firewall mutation         : DENIED',
    ' Automatic delete          : DENIED',
    ' Human gate               : REQUIRED',
    ' Pre-mutation snapshot     : REQUIRED',
    ' Rollback receipt          : REQUIRED',
    '',
    " JSON                      : $json",
    " TXT                       : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.4.6 FINAL GATE : GREEN' -ForegroundColor Green
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host ' ZERO MUTATION — EXECUTION NOT YET AUTHORIZED' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
