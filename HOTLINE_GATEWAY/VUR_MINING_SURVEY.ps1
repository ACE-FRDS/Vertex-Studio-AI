$ErrorActionPreference = 'Stop'

$root = 'C:\Users\acefr\Documents\Vertex Project\Vertex FM Engine\ProgramSource\Source\src'

$targets = @(
    'components',
    'pages',
    'styles'
)

$results = @()

foreach ($target in $targets) {
    $base = Join-Path $root $target

    Get-ChildItem $base -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in @(
                '.vue',
                '.ts',
                '.tsx',
                '.js',
                '.css',
                '.scss',
                '.svg'
            )
        } |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Length).TrimStart('\')

            $results += [pscustomobject]@{
                area      = $target
                path      = $relative
                extension = $_.Extension
                bytes     = $_.Length
            }
        }
}

Write-Host "`n=== VUR MINING SURVEY ===" -ForegroundColor Cyan
Write-Host "Files :" $results.Count
Write-Host "Bytes :" ($results | Measure-Object bytes -Sum).Sum

Write-Host "`n=== BY AREA ===" -ForegroundColor Cyan

$results |
    Group-Object area |
    ForEach-Object {
        [pscustomobject]@{
            area  = $_.Name
            files = $_.Count
            bytes = ($_.Group | Measure-Object bytes -Sum).Sum
        }
    } |
    Format-Table -AutoSize

Write-Host "`n=== TOP 30 LARGEST ===" -ForegroundColor Cyan

$results |
    Sort-Object bytes -Descending |
    Select-Object -First 30 |
    Format-Table area, extension, bytes, path -AutoSize