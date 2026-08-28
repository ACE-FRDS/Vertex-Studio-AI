#requires -Version 7.0
<#
VERTEX ENV-2 V2.4.11 — VERSION LINEAGE NORMALIZER
READ ONLY / ZERO MUTATION

Consumes latest V2.4.9 replacement identity report and normalizes
vendor/product-specific version schemes before comparing lineage.

Goals:
  - Avoid nonsense comparisons like 2023 -> 26 being marked "older"
  - Understand JetBrains build trains such as 261.x / 262.x
  - Preserve Edge/WebView semantic build ordering
  - Never mutate firewall/system state
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportRoot = 'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports'

Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-2 V2.4.11 — VERSION LINEAGE NORMALIZER' -ForegroundColor Magenta
Write-Host ' RAW VERSION -> NORMALIZED LINEAGE -> REASSESS' -ForegroundColor Magenta
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

$source = Get-ChildItem -LiteralPath $ReportRoot -Filter 'VERTEX_REPLACEMENT_IDENTITY_RESOLUTION.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    throw 'No V2.4.9 replacement identity report found.'
}

$data = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 60
$candidates = @($data.candidates)

Write-Host "Source     : $($source.FullName)"
Write-Host "Candidates : $($candidates.Count)"


function Get-SafeProperty {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = ''
    )

    if ($null -eq $Object) { return $Default }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }

    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Get-VersionTokens {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $matches = [regex]::Matches($Text, '(?<!\d)(\d{1,4})(?:\.(\d{1,4}))?(?:\.(\d{1,4}))?(?:\.(\d{1,4}))?(?!\d)')
    $tokens = [System.Collections.Generic.List[object]]::new()

    foreach ($m in $matches) {
        $parts = @()
        for ($i = 1; $i -le 4; $i++) {
            if ($m.Groups[$i].Success) {
                $parts += [int]$m.Groups[$i].Value
            }
        }

        if ($parts.Count -gt 0) {
            $tokens.Add([pscustomobject][ordered]@{
                raw   = $m.Value
                parts = @($parts)
            })
        }
    }

    return @($tokens)
}

function Get-PreferredVersionToken {
    param(
        [string]$Vendor,
        [string]$Product,
        [string[]]$Texts
    )

    $all = [System.Collections.Generic.List[object]]::new()

    foreach ($t in @($Texts)) {
        foreach ($tok in @(Get-VersionTokens $t)) {
            $all.Add($tok)
        }
    }

    if ($all.Count -eq 0) {
        return $null
    }

    # Vendor/product aware preferences.
    if ($Vendor -eq 'JETBRAINS') {
        # Prefer JetBrains build train 3-digit number such as 261/262.
        $jb = @($all | Where-Object {
            $_.parts.Count -ge 1 -and $_.parts[0] -ge 200 -and $_.parts[0] -lt 400
        } | Sort-Object { $_.parts[0] } -Descending)

        if ($jb.Count -gt 0) { return $jb[0] }

        # Otherwise prefer calendar-year version such as 2024.3.2.
        $year = @($all | Where-Object {
            $_.parts[0] -ge 2000 -and $_.parts[0] -le 2100
        } | Sort-Object { $_.parts[0] } -Descending)
        if ($year.Count -gt 0) { return $year[0] }
    }

    if ($Vendor -in @('ADOBE','CLARIS_FILEMAKER')) {
        # Prefer calendar-year style when present.
        $year = @($all | Where-Object {
            $_.parts[0] -ge 2000 -and $_.parts[0] -le 2100
        } | Sort-Object { $_.parts[0] } -Descending)

        if ($year.Count -gt 0) { return $year[0] }

        # Adobe often exposes 26.x for 2026 products.
        $shortYear = @($all | Where-Object {
            $_.parts[0] -ge 20 -and $_.parts[0] -le 99
        } | Sort-Object { $_.parts[0] } -Descending)

        if ($shortYear.Count -gt 0) { return $shortYear[0] }
    }

    if ($Product -eq 'EDGE_WEBVIEW2' -or $Vendor -eq 'MICROSOFT') {
        # Edge/WebView major release is the first component, e.g. 151.x.
        $edge = @($all | Where-Object {
            $_.parts[0] -ge 80 -and $_.parts[0] -le 500
        } | Sort-Object { $_.parts[0] } -Descending)

        if ($edge.Count -gt 0) { return $edge[0] }
    }

    # Generic: choose the token with the most components, then highest first part.
    return @($all |
        Sort-Object `
            @{Expression={ $_.parts.Count };Descending=$true},
            @{Expression={ $_.parts[0] };Descending=$true}
    )[0]
}

function Convert-ToComparableVersion {
    param(
        [string]$Vendor,
        [string]$Product,
        [object]$Token
    )

    if (-not $Token) { return $null }

    $parts = @($Token.parts)
    if ($parts.Count -eq 0) { return $null }

    $major = [int]$parts[0]
    $minor = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $patch = if ($parts.Count -gt 2) { [int]$parts[2] } else { 0 }
    $build = if ($parts.Count -gt 3) { [int]$parts[3] } else { 0 }

    # Normalize short-year Adobe-style major 26 => 2026.
    if ($Vendor -eq 'ADOBE' -and $major -ge 20 -and $major -le 99) {
        $major = 2000 + $major
    }

    # JetBrains build train 261 => 2026.1, 262 => 2026.2, etc.
    if ($Vendor -eq 'JETBRAINS' -and $major -ge 200 -and $major -lt 400) {
        $year = 2000 + [math]::Floor($major / 10)
        $train = $major % 10
        return [pscustomobject][ordered]@{
            normalized = "$year.$train.$minor.$patch"
            vector = @($year,$train,$minor,$patch)
            scheme = 'JETBRAINS_BUILD_TRAIN'
            raw = [string]$Token.raw
        }
    }

    return [pscustomobject][ordered]@{
        normalized = "$major.$minor.$patch.$build"
        vector = @($major,$minor,$patch,$build)
        scheme = 'GENERIC'
        raw = [string]$Token.raw
    }
}

function Compare-VersionVector {
    param(
        [AllowNull()][object]$Old,
        [AllowNull()][object]$New
    )

    if (-not $Old -or -not $New) {
        return 'UNKNOWN'
    }

    $a = @($Old.vector)
    $b = @($New.vector)
    $len = [Math]::Max($a.Count,$b.Count)

    for ($i=0; $i -lt $len; $i++) {
        $av = if ($i -lt $a.Count) { [int]$a[$i] } else { 0 }
        $bv = if ($i -lt $b.Count) { [int]$b[$i] } else { 0 }

        if ($bv -gt $av) { return 'NEWER' }
        if ($bv -lt $av) { return 'OLDER' }
    }

    return 'SAME'
}

$results = [System.Collections.Generic.List[object]]::new()
$i = 0

foreach ($c in $candidates) {
    $i++

    $best = $c.best_replacement
    $decision = [string]$c.identity_decision

    $versionAssessment = 'NOT_APPLICABLE'
    $oldNorm = $null
    $newNorm = $null

    if ($best) {
        $vendor  = [string]$best.old_vendor
        if ($vendor -eq 'UNKNOWN') { $vendor = [string]$best.new_vendor }

        $product = [string]$best.old_product
        if ($product -eq 'UNKNOWN') { $product = [string]$best.new_product }

        $oldTexts = @(
            [string]$c.old_program,
            [string]$c.display_name
        )

        $fileIdentity = Get-SafeProperty -Object $best -Name 'file_identity' -Default $null
        $appIdentity  = Get-SafeProperty -Object $best -Name 'app_identity'  -Default $null

        $newTexts = @(
            [string](Get-SafeProperty -Object $best -Name 'path' -Default ''),
            [string](Get-SafeProperty -Object $fileIdentity -Name 'file_version' -Default ''),
            [string](Get-SafeProperty -Object $fileIdentity -Name 'product_version' -Default ''),
            [string](Get-SafeProperty -Object $appIdentity -Name 'display_version' -Default ''),
            [string](Get-SafeProperty -Object $appIdentity -Name 'display_name' -Default '')
        )

        $oldToken = Get-PreferredVersionToken -Vendor $vendor -Product $product -Texts $oldTexts
        $newToken = Get-PreferredVersionToken -Vendor $vendor -Product $product -Texts $newTexts

        $oldNorm = Convert-ToComparableVersion -Vendor $vendor -Product $product -Token $oldToken
        $newNorm = Convert-ToComparableVersion -Vendor $vendor -Product $product -Token $newToken

        $versionAssessment = Compare-VersionVector -Old $oldNorm -New $newNorm
    }

    $revisedDecision = $decision
    $notes = [System.Collections.Generic.List[string]]::new()

    if ($best) {
        if ($versionAssessment -eq 'NEWER') {
            $notes.Add('Normalized version lineage supports replacement.')
        }
        elseif ($versionAssessment -eq 'OLDER') {
            $notes.Add('Normalized version lineage indicates candidate is older.')
            if ($revisedDecision -eq 'REPLACEMENT_CONFIRMED') {
                $revisedDecision = 'REPLACEMENT_PROBABLE'
            }
        }
        elseif ($versionAssessment -eq 'SAME') {
            $notes.Add('Normalized version lineage is same generation.')
        }
        else {
            $notes.Add('Version lineage could not be normalized reliably.')
        }
    }

    $results.Add([pscustomobject][ordered]@{
        candidate_id          = [string]$c.candidate_id
        display_name          = [string]$c.display_name
        family                = [string]$c.family
        old_program           = [string]$c.old_program
        identity_decision     = $decision
        revised_decision      = $revisedDecision
        version_assessment    = $versionAssessment
        old_version           = $oldNorm
        new_version           = $newNorm
        best_replacement      = $best
        notes                 = @($notes)
        mutation              = 'NONE'
    })

    Write-Progress -Activity 'Vertex Version Lineage Normalizer' `
        -Status "$i / $($candidates.Count) : $($c.display_name)" `
        -PercentComplete (($i / [Math]::Max(1,$candidates.Count)) * 100)
}

Write-Progress -Activity 'Vertex Version Lineage Normalizer' -Completed

$counts = [ordered]@{
    TOTAL                 = $results.Count
    NEWER                 = @($results | Where-Object version_assessment -eq 'NEWER').Count
    SAME                  = @($results | Where-Object version_assessment -eq 'SAME').Count
    OLDER                 = @($results | Where-Object version_assessment -eq 'OLDER').Count
    UNKNOWN               = @($results | Where-Object version_assessment -eq 'UNKNOWN').Count
    NOT_APPLICABLE        = @($results | Where-Object version_assessment -eq 'NOT_APPLICABLE').Count
    CONFIRMED_AFTER_NORM  = @($results | Where-Object revised_decision -eq 'REPLACEMENT_CONFIRMED').Count
    PROBABLE_AFTER_NORM   = @($results | Where-Object revised_decision -eq 'REPLACEMENT_PROBABLE').Count
    REJECTED_AFTER_NORM   = @($results | Where-Object revised_decision -eq 'REPLACEMENT_REJECTED').Count
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' VERSION LINEAGE NORMALIZATION SUMMARY'
Write-Host '============================================================'
Write-Host " Total                : $($counts.TOTAL)"
Write-Host " Newer                : $($counts.NEWER)" -ForegroundColor Green
Write-Host " Same                 : $($counts.SAME)"
Write-Host " Older                : $($counts.OLDER)" -ForegroundColor Yellow
Write-Host " Unknown              : $($counts.UNKNOWN)"
Write-Host " Not applicable       : $($counts.NOT_APPLICABLE)"
Write-Host " Confirmed after norm : $($counts.CONFIRMED_AFTER_NORM)" -ForegroundColor Green
Write-Host " Probable after norm  : $($counts.PROBABLE_AFTER_NORM)" -ForegroundColor Cyan
Write-Host " Rejected after norm  : $($counts.REJECTED_AFTER_NORM)" -ForegroundColor Yellow

foreach ($r in $results) {
    if (-not $r.best_replacement) { continue }

    Write-Host ''
    $color = switch ($r.version_assessment) {
        'NEWER' { 'Green' }
        'OLDER' { 'Yellow' }
        'SAME'  { 'Cyan' }
        default { 'Gray' }
    }

    Write-Host "[$($r.version_assessment)] $($r.candidate_id) $($r.display_name)" -ForegroundColor $color
    Write-Host "  Old : $($r.old_program)"
    Write-Host "  New : $($r.best_replacement.path)"

    if ($r.old_version) {
        Write-Host "  Old Version : $($r.old_version.raw) -> $($r.old_version.normalized) [$($r.old_version.scheme)]"
    }
    if ($r.new_version) {
        Write-Host "  New Version : $($r.new_version.raw) -> $($r.new_version.normalized) [$($r.new_version.scheme)]"
    }

    Write-Host "  Identity     : $($r.identity_decision)"
    Write-Host "  Revised      : $($r.revised_decision)"
    if (@($r.notes).Count -gt 0) {
        Write-Host "  Note         : $($r.notes -join ' | ')"
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$json = Join-Path $ReportRoot "VERTEX_VERSION_LINEAGE_NORMALIZATION.$stamp.json"
$txt  = Join-Path $ReportRoot "VERTEX_VERSION_LINEAGE_NORMALIZATION.$stamp.txt"

$report = [ordered]@{
    schema        = 'vertex.environment.version-lineage-normalization.v1'
    mission       = 'VERTEX_ENV_2_V2_4_11_VERSION_LINEAGE_NORMALIZER'
    generated_at  = (Get-Date).ToString('o')
    source_report = $source.FullName
    mode          = 'READ_ONLY'
    counts        = $counts
    candidates    = @($results)
    policy        = [ordered]@{
        raw_string_compare      = 'DENIED'
        vendor_aware_normalize  = 'ENABLED'
        product_aware_normalize = 'ENABLED'
        automatic_mutation      = 'DENIED'
        human_gate              = 'REQUIRED'
        mutation                = 'NONE'
    }
}

$report | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $json -Encoding UTF8

@(
    '============================================================',
    ' VERTEX ENV-2 V2.4.11 — VERSION LINEAGE NORMALIZER',
    '============================================================',
    " Source                : $($source.FullName)",
    " Total                 : $($counts.TOTAL)",
    " Newer                 : $($counts.NEWER)",
    " Same                  : $($counts.SAME)",
    " Older                 : $($counts.OLDER)",
    " Unknown               : $($counts.UNKNOWN)",
    " Confirmed after norm  : $($counts.CONFIRMED_AFTER_NORM)",
    " Probable after norm   : $($counts.PROBABLE_AFTER_NORM)",
    " Rejected after norm   : $($counts.REJECTED_AFTER_NORM)",
    '',
    ' Raw version compare   : DENIED',
    ' Automatic mutation    : DENIED',
    ' Human gate            : REQUIRED',
    '',
    " JSON                  : $json",
    " TXT                   : $txt",
    '============================================================'
) | Set-Content -LiteralPath $txt -Encoding UTF8

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ' V2.4.10 VERSION NORMALIZER : GREEN' -ForegroundColor Green
Write-Host " JSON : $json"
Write-Host " TXT  : $txt"
Write-Host ' READ ONLY / ZERO MUTATION' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
