#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.5 — HYGIENE REVIEW & SAFE REMEDIATION PLAN
READ ONLY / ZERO MUTATION

Consumes the newest V2.4.4 context-aware hygiene JSON report and converts
candidate findings into a conservative remediation PLAN.

NO firewall rule is changed or deleted.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.5 — HYGIENE REMEDIATION PLANNER' -ForegroundColor Magenta
Write-Host ' EVIDENCE -> CLASSIFICATION -> HUMAN REVIEW PLAN' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_SECURITY_HYGIENE_CONTEXT.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    throw 'No V2.4.4 context-aware hygiene JSON report found.'
}

Write-Host "Source : $($source.FullName)"

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30
$findings = @($data.findings)

$planItems = @()

foreach ($f in $findings) {
    $decision = 'PROTECT'
    $confidence = 1.00
    $reason = [System.Collections.Generic.List[string]]::new()
    $requiredChecks = [System.Collections.Generic.List[string]]::new()

    $classification = [string]$f.classification
    $program = [string]$f.program
    $display = [string]$f.display_name
    $isWindowsBaseline = [bool]$f.is_windows_baseline
    $serviceCount = @($f.service_evidence).Count
    $appCount = @($f.installed_app_evidence).Count
    $listener = [bool]$f.listener_match

    if ($isWindowsBaseline -or $classification -like 'SYSTEM_*') {
        $decision = 'PROTECT'
        $confidence = 0.99
        $reason.Add('Windows/system baseline evidence.')
    }
    elseif ($classification -eq 'ACTIVE_APPLICATION_RULE') {
        $decision = 'PROTECT'
        $confidence = 0.95
        $reason.Add('Application binary is present.')
    }
    elseif ($classification -eq 'BROAD_RULE_REVIEW') {
        $decision = 'REVIEW_REQUIRED'
        $confidence = 0.75
        $reason.Add('Broad inbound rule cannot be safely removed from firewall evidence alone.')
        $requiredChecks.Add('Identify owning application or server role.')
        $requiredChecks.Add('Confirm whether exposed port is still required.')
    }
    elseif ($classification -eq 'STALE_APPLICATION_ARTIFACT') {
        $decision = 'REVIEW_REQUIRED'
        $confidence = 0.80
        $reason.Add('Binary is missing but related application/service evidence exists.')
        $requiredChecks.Add('Resolve replacement/current executable path.')
        $requiredChecks.Add('Compare old and current firewall rules.')
    }
    elseif ($classification -eq 'ORPHAN_CONFIRMED_CANDIDATE') {
        # Conservative promotion only. Missing binary + no service + no installed-app evidence
        # is strong stale evidence, but still not enough for automatic deletion.
        if ($serviceCount -eq 0 -and $appCount -eq 0 -and -not $listener) {
            $decision = 'LIKELY_REMOVE'
            $confidence = 0.90
            $reason.Add('Referenced binary is absent.')
            $reason.Add('No matching service evidence.')
            $reason.Add('No matching installed-application evidence.')
            $reason.Add('No matching listener observed.')
            $requiredChecks.Add('Confirm application is intentionally retired.')
            $requiredChecks.Add('Capture firewall rule snapshot before any future mutation.')
        }
        else {
            $decision = 'REVIEW_REQUIRED'
            $confidence = 0.70
            $reason.Add('Orphan signal has conflicting live evidence.')
        }
    }

    # Never auto-promote known mutable/versioned application families to SAFE_REMOVE.
    if ($display -match '(?i)Edge|WebView|JetBrains|Rider|RustRover|PyCharm|WebStorm|DataGrip|Java|JDK|Adobe|Steam|Docker|nginx|FileMaker') {
        if ($decision -eq 'LIKELY_REMOVE') {
            $requiredChecks.Add('Check for newer/replacement version before removal.')
            $reason.Add('Versioned or commonly updated application family detected.')
        }
    }

    $planItems += [pscustomobject][ordered]@{
        display_name = $display
        firewall_rule_name = [string]$f.name
        program = $program
        source_classification = $classification
        proposed_decision = $decision
        confidence = $confidence
        service_evidence_count = $serviceCount
        installed_app_evidence_count = $appCount
        listener_match = $listener
        reasons = @($reason)
        required_checks = @($requiredChecks)
        mutation = 'NONE'
    }
}

$counts = [ordered]@{
    SAFE_REMOVE = @($planItems | Where-Object proposed_decision -eq 'SAFE_REMOVE').Count
    LIKELY_REMOVE = @($planItems | Where-Object proposed_decision -eq 'LIKELY_REMOVE').Count
    REVIEW_REQUIRED = @($planItems | Where-Object proposed_decision -eq 'REVIEW_REQUIRED').Count
    PROTECT = @($planItems | Where-Object proposed_decision -eq 'PROTECT').Count
}

Write-Host ''
Write-Host "Plan items       : $($planItems.Count)"
Write-Host "SAFE_REMOVE      : $($counts.SAFE_REMOVE)" -ForegroundColor Green
Write-Host "LIKELY_REMOVE    : $($counts.LIKELY_REMOVE)" -ForegroundColor Yellow
Write-Host "REVIEW_REQUIRED  : $($counts.REVIEW_REQUIRED)" -ForegroundColor Cyan
Write-Host "PROTECT          : $($counts.PROTECT)"
Write-Host ''

foreach ($item in @($planItems | Where-Object proposed_decision -in @('LIKELY_REMOVE','REVIEW_REQUIRED'))) {
    $c = if ($item.proposed_decision -eq 'LIKELY_REMOVE') { 'Yellow' } else { 'Cyan' }
    Write-Host "[$($item.proposed_decision)] $($item.display_name)" -ForegroundColor $c
    Write-Host "  Program    : $($item.program)"
    Write-Host "  Confidence : $($item.confidence)"
    Write-Host "  Reasons    : $($item.reasons -join ' | ')"
    if (@($item.required_checks).Count -gt 0) {
        Write-Host "  Checks     : $($item.required_checks -join ' | ')"
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $ReportRoot "VERTEX_HYGIENE_REMEDIATION_PLAN.$stamp.json"
$txt = Join-Path $ReportRoot "VERTEX_HYGIENE_REMEDIATION_PLAN.$stamp.txt"

$report = [ordered]@{
    schema = 'vertex.environment.hygiene-remediation-plan.v1'
    mission = 'VERTEX_ENV_2_V2_4_5_HYGIENE_REMEDIATION_PLAN'
    generated_at = (Get-Date).ToString('o')
    source_report = $source.FullName
    mode = 'READ_ONLY'
    counts = $counts
    plan = $planItems
    policy = [ordered]@{
        SAFE_REMOVE = 'Reserved for future stages with stronger independent proof.'
        LIKELY_REMOVE = 'Strong stale evidence; human confirmation still required.'
        REVIEW_REQUIRED = 'Evidence is insufficient or conflicting.'
        PROTECT = 'No cleanup action proposed.'
        automatic_mutation = 'DENIED'
        human_gate = 'REQUIRED'
        rollback_evidence_before_future_mutation = 'REQUIRED'
    }
}

$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $json -Encoding UTF8

$lines = @(
    '============================================================',
    ' VERTEX HYGIENE REMEDIATION PLAN',
    '============================================================',
    " Source           : $($source.FullName)",
    " Plan Items       : $($planItems.Count)",
    " SAFE_REMOVE      : $($counts.SAFE_REMOVE)",
    " LIKELY_REMOVE    : $($counts.LIKELY_REMOVE)",
    " REVIEW_REQUIRED  : $($counts.REVIEW_REQUIRED)",
    " PROTECT          : $($counts.PROTECT)",
    '',
    ' Mutation         : NONE',
    ' Human Gate       : REQUIRED',
    ' Auto Delete      : DENIED',
    '',
    " JSON             : $json",
    " TXT              : $txt",
    '============================================================'
)
$lines | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' REMEDIATION PLAN COMPLETE' -ForegroundColor Green
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host ' NO FIREWALL MUTATION PERFORMED' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
