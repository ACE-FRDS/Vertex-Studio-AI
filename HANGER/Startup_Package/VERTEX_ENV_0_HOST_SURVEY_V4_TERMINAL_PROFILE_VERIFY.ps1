#requires -Version 7.0
<#
VERTEX ENV-0
Vertex Host Survey & Environment Profile V4
READ-ONLY OBSERVATION MISSION

Purpose:
  - Observe the current Windows host without changing system configuration.
  - Generate machine-readable and human-readable evidence for later:
      ENV-1 Environment Planner
      ENV-2 Package Lifecycle
      ENV-3 Installer / Repair
      ENV-4 Uninstaller / Cleaner
      ENV-5 VSA -> Server Deployment
      ENV-6 USB SSD -> Server Genesis
      ENV-7 Recovery / Rollback

Mutation policy:
  ALLOWED:
    - Read system state
    - Execute version/status/query commands
    - Create survey report files only
  FORBIDDEN:
    - Install / uninstall
    - Registry mutation
    - Service mutation
    - Firewall mutation
    - Environment variable mutation
    - PATH mutation
    - Package manager mutation
    - Driver mutation
    - Port binding
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MissionId = 'VERTEX_ENV_0_HOST_SURVEY'
$Schema = 'vertex.environment.host-profile.v1'
$StartedAt = Get-Date

# -------------------------------------------------------------------
# Resolve Vertex report destination.
# -------------------------------------------------------------------
$CandidateRoots = @(
    'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports',
    'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\_vertex_reports',
    (Join-Path $PSScriptRoot '_vertex_reports')
)

$ReportRoot = $null
foreach ($candidate in $CandidateRoots) {
    $parent = Split-Path -Parent $candidate
    if ($candidate -and ((Test-Path -LiteralPath $candidate) -or (Test-Path -LiteralPath $parent))) {
        $ReportRoot = $candidate
        break
    }
}

if (-not $ReportRoot) {
    $ReportRoot = Join-Path $PSScriptRoot '_vertex_reports'
}

New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$JsonPath = Join-Path $ReportRoot "VERTEX_HOST_PROFILE.$Stamp.json"
$TextPath = Join-Path $ReportRoot "VERTEX_HOST_PROFILE.$Stamp.txt"

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
function Invoke-Observation {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Action
    )

    try {
        $value = & $Action
        [pscustomobject]@{
            name   = $Name
            status = 'GREEN'
            value  = $value
            error  = $null
        }
    }
    catch {
        [pscustomobject]@{
            name   = $Name
            status = 'UNAVAILABLE'
            value  = $null
            error  = $_.Exception.Message
        }
    }
}

function Get-CommandProbe {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [string[]] $VersionArgs = @('--version')
    )

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [pscustomobject]@{
            installed = $false
            command   = $Command
            path      = $null
            version   = $null
        }
    }

    $version = $null
    try {
        $output = & $cmd.Source @VersionArgs 2>&1 | Select-Object -First 3
        $version = ($output | ForEach-Object { "$_" }) -join ' | '
    } catch {
        $version = "version probe failed: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        installed = $true
        command   = $Command
        path      = $cmd.Source
        version   = $version
    }
}

function Get-DirectoryStats {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            path   = $Path
            exists = $false
            files  = 0
            dirs   = 0
            bytes  = 0
        }
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
        $files = @($items | Where-Object { -not $_.PSIsContainer })
        $dirs  = @($items | Where-Object { $_.PSIsContainer })

        [pscustomobject]@{
            path   = $Path
            exists = $true
            files  = $files.Count
            dirs   = $dirs.Count
            bytes  = [int64](($files | Measure-Object -Property Length -Sum).Sum ?? 0)
        }
    } catch {
        [pscustomobject]@{
            path   = $Path
            exists = $true
            files  = $null
            dirs   = $null
            bytes  = $null
            error  = $_.Exception.Message
        }
    }
}

function Convert-BytesToGiB {
    param([Nullable[long]] $Bytes)
    if ($null -eq $Bytes) { return $null }
    [math]::Round($Bytes / 1GB, 2)
}

function Read-InstalledApps {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $apps = foreach ($path in $paths) {
        $items = @(Get-ItemProperty $path -ErrorAction SilentlyContinue)

        foreach ($item in $items) {
            $displayNameProperty = $item.PSObject.Properties['DisplayName']

            if ($null -eq $displayNameProperty) {
                continue
            }

            $displayName = [string]$displayNameProperty.Value

            if ([string]::IsNullOrWhiteSpace($displayName)) {
                continue
            }

            $displayVersionProperty = $item.PSObject.Properties['DisplayVersion']
            $publisherProperty = $item.PSObject.Properties['Publisher']
            $installLocationProperty = $item.PSObject.Properties['InstallLocation']
            $installDateProperty = $item.PSObject.Properties['InstallDate']

            [pscustomobject]@{
                DisplayName     = $displayName
                DisplayVersion  = if ($displayVersionProperty) { [string]$displayVersionProperty.Value } else { $null }
                Publisher       = if ($publisherProperty) { [string]$publisherProperty.Value } else { $null }
                InstallLocation = if ($installLocationProperty) { [string]$installLocationProperty.Value } else { $null }
                InstallDate     = if ($installDateProperty) { [string]$installDateProperty.Value } else { $null }
            }
        }
    }

    @($apps | Sort-Object DisplayName, DisplayVersion -Unique)
}

function Find-App {
    param(
        [Parameter(Mandatory)] [object[]] $Apps,
        [Parameter(Mandatory)] [string] $Pattern
    )

    @(
        $Apps | Where-Object {
            $property = $_.PSObject.Properties['DisplayName']
            if ($null -eq $property) {
                return $false
            }

            $name = [string]$property.Value
            -not [string]::IsNullOrWhiteSpace($name) -and $name -match $Pattern
        }
    )
}

function Get-NvidiaInfo {
    $smi = Get-Command 'nvidia-smi' -ErrorAction SilentlyContinue
    if (-not $smi) {
        return [pscustomobject]@{
            available = $false
            path      = $null
            driver    = $null
            cuda      = $null
            gpus      = @()
        }
    }

    $driver = $null
    $cuda = $null
    try {
        $header = & $smi.Source 2>&1 | Select-Object -First 5
        $joined = ($header | ForEach-Object { "$_" }) -join "`n"
        if ($joined -match 'Driver Version:\s*([0-9.]+)') { $driver = $Matches[1] }
        if ($joined -match 'CUDA Version:\s*([0-9.]+)') { $cuda = $Matches[1] }
    } catch {}

    $gpus = @()
    try {
        $rows = & $smi.Source --query-gpu=index,name,memory.total,memory.free,driver_version,pci.bus_id --format=csv,noheader,nounits 2>$null
        foreach ($row in $rows) {
            $parts = $row -split '\s*,\s*'
            if ($parts.Count -ge 6) {
                $gpus += [pscustomobject]@{
                    index          = [int]$parts[0]
                    name           = $parts[1]
                    vram_total_mib = [int]$parts[2]
                    vram_free_mib  = [int]$parts[3]
                    driver_version = $parts[4]
                    pci_bus_id     = $parts[5]
                }
            }
        }
    } catch {}

    [pscustomobject]@{
        available = $true
        path      = $smi.Source
        driver    = $driver
        cuda      = $cuda
        gpus      = $gpus
    }
}


function Get-WindowsTerminalSettings {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )

    $settingsPath = $candidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if (-not $settingsPath) {
        return [pscustomobject]@{
            found = $false
            settings_path = $null
            default_profile_guid = $null
            default_profile_name = $null
            default_profile_source = $null
            default_profile_commandline = $null
            starting_directory = $null
            powershell7_profile = $false
            vertex_mothership_start = $false
            error = 'Windows Terminal settings.json not found.'
        }
    }

    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding utf8 | ConvertFrom-Json

        $defaultGuid = [string]$settings.defaultProfile
        $profiles = @($settings.profiles.list)
        $defaultProfile = $profiles |
            Where-Object { [string]$_.guid -eq $defaultGuid } |
            Select-Object -First 1

        $name = $null
        $source = $null
        $commandline = $null
        $startingDirectory = $null

        if ($defaultProfile) {
            $name = [string]$defaultProfile.name
            $source = [string]$defaultProfile.source
            $commandline = [string]$defaultProfile.commandline
            $startingDirectory = [string]$defaultProfile.startingDirectory
        }

        $isPowerShell7 = $false

        if ($defaultProfile) {
            if (
                $name -match '(?i)PowerShell\s*7' -or
                $source -eq 'Windows.Terminal.PowershellCore' -or
                $commandline -match '(?i)\\pwsh\.exe'
            ) {
                $isPowerShell7 = $true
            }
        }

        $expectedMothership = 'G:\Vertex_Project\Vertex_Studio_AI'
        $mothershipStart = $false

        if (-not [string]::IsNullOrWhiteSpace($startingDirectory)) {
            try {
                $normalizedActual = [IO.Path]::GetFullPath($startingDirectory.TrimEnd('\'))
                $normalizedExpected = [IO.Path]::GetFullPath($expectedMothership.TrimEnd('\'))
                $mothershipStart = ($normalizedActual -eq $normalizedExpected)
            } catch {}
        }

        return [pscustomobject]@{
            found = $true
            settings_path = $settingsPath
            default_profile_guid = $defaultGuid
            default_profile_name = $name
            default_profile_source = $source
            default_profile_commandline = $commandline
            starting_directory = $startingDirectory
            powershell7_profile = $isPowerShell7
            vertex_mothership_start = $mothershipStart
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            found = $true
            settings_path = $settingsPath
            default_profile_guid = $null
            default_profile_name = $null
            default_profile_source = $null
            default_profile_commandline = $null
            starting_directory = $null
            powershell7_profile = $false
            vertex_mothership_start = $false
            error = $_.Exception.Message
        }
    }
}

# -------------------------------------------------------------------
# Mission banner
# -------------------------------------------------------------------
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-0 — HOST SURVEY & ENVIRONMENT PROFILE V4' -ForegroundColor Magenta
Write-Host ' READ-ONLY OBSERVATION / POWERSHELL 7 PRIMARY' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta

if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw "ENV-0 requires PowerShell 7+ (pwsh). Current: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
}

Write-Host ("PowerShell : {0} / {1}" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition) -ForegroundColor Green
Write-Host ("Process    : {0}" -f (Get-Process -Id $PID).Path) -ForegroundColor Green
Write-Host 'Mutation   : REPORT FILES ONLY' -ForegroundColor Green

# -------------------------------------------------------------------
# Core host
# -------------------------------------------------------------------
Write-Host "`n[1/12] HOST / OS" -ForegroundColor Yellow

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$baseboard = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue

$hostInfo = [pscustomobject]@{
    computer_name = $env:COMPUTERNAME
    user_name     = $env:USERNAME
    domain        = $computer.Domain
    manufacturer  = $computer.Manufacturer
    model         = $computer.Model
    system_type   = $computer.SystemType
    os_caption    = $os.Caption
    os_version    = $os.Version
    os_build      = $os.BuildNumber
    architecture  = $os.OSArchitecture
    install_date  = $os.InstallDate
    last_boot     = $os.LastBootUpTime
    bios_vendor   = $bios.Manufacturer
    bios_version  = ($bios.SMBIOSBIOSVersion -join ', ')
    motherboard   = if ($baseboard) { "$($baseboard.Manufacturer) $($baseboard.Product)" } else { $null }
}

Write-Host ("Host       : {0}" -f $hostInfo.computer_name) -ForegroundColor Green
Write-Host ("OS         : {0} / Build {1}" -f $hostInfo.os_caption, $hostInfo.os_build) -ForegroundColor Green

# -------------------------------------------------------------------
# CPU / memory
# -------------------------------------------------------------------
Write-Host "`n[2/12] CPU / MEMORY" -ForegroundColor Yellow

$cpuRaw = @(Get-CimInstance Win32_Processor)
$cpuInfo = @($cpuRaw | ForEach-Object {
    [pscustomobject]@{
        name                  = $_.Name.Trim()
        manufacturer          = $_.Manufacturer
        physical_cores        = $_.NumberOfCores
        logical_processors    = $_.NumberOfLogicalProcessors
        max_clock_mhz         = $_.MaxClockSpeed
        virtualization_firmware_enabled = $_.VirtualizationFirmwareEnabled
        second_level_cache_kb = $_.L2CacheSize
        third_level_cache_kb  = $_.L3CacheSize
    }
})

$totalRam = [int64]$computer.TotalPhysicalMemory
$memoryModules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        manufacturer = $_.Manufacturer
        part_number  = ($_.PartNumber ?? '').Trim()
        capacity_gib = Convert-BytesToGiB $_.Capacity
        speed_mhz    = $_.Speed
        configured_clock_mhz = $_.ConfiguredClockSpeed
        locator      = $_.DeviceLocator
    }
})

$memoryInfo = [pscustomobject]@{
    total_bytes = $totalRam
    total_gib   = Convert-BytesToGiB $totalRam
    modules     = $memoryModules
}

Write-Host ("CPU        : {0}" -f (($cpuInfo | ForEach-Object { $_.name }) -join ' / ')) -ForegroundColor Green
Write-Host ("RAM        : {0} GiB" -f $memoryInfo.total_gib) -ForegroundColor Green

# -------------------------------------------------------------------
# GPU
# -------------------------------------------------------------------
Write-Host "`n[3/12] GPU / DRIVER / CUDA" -ForegroundColor Yellow

$gpuCim = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        name            = $_.Name
        driver_version  = $_.DriverVersion
        adapter_ram_gib = if ($_.AdapterRAM) { Convert-BytesToGiB ([int64]$_.AdapterRAM) } else { $null }
        video_processor = $_.VideoProcessor
        pnp_device_id   = $_.PNPDeviceID
    }
})

$nvidia = Get-NvidiaInfo

foreach ($gpu in $gpuCim) {
    Write-Host ("GPU        : {0}" -f $gpu.name) -ForegroundColor Green
}
if ($nvidia.available) {
    Write-Host ("NVIDIA-SMI : {0} / CUDA {1}" -f $nvidia.driver, $nvidia.cuda) -ForegroundColor Green
}

# -------------------------------------------------------------------
# Storage
# -------------------------------------------------------------------
Write-Host "`n[4/12] STORAGE / FILESYSTEM" -ForegroundColor Yellow

$volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object {
    [pscustomobject]@{
        drive_letter = "$($_.DriveLetter):"
        label        = $_.FileSystemLabel
        filesystem   = $_.FileSystem
        health       = $_.HealthStatus
        size_gib     = Convert-BytesToGiB $_.Size
        free_gib     = Convert-BytesToGiB $_.SizeRemaining
        free_percent = if ($_.Size -gt 0) { [math]::Round(($_.SizeRemaining / $_.Size) * 100, 1) } else { $null }
    }
})

$physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{
        friendly_name = $_.FriendlyName
        media_type    = $_.MediaType
        bus_type      = $_.BusType
        health        = $_.HealthStatus
        size_gib      = Convert-BytesToGiB $_.Size
    }
})

foreach ($vol in $volumes) {
    Write-Host ("Volume     : {0} {1} GiB free / {2} GiB" -f $vol.drive_letter, $vol.free_gib, $vol.size_gib) -ForegroundColor Green
}

# -------------------------------------------------------------------
# Network / ports
# -------------------------------------------------------------------
Write-Host "`n[5/12] NETWORK / LISTENING PORTS" -ForegroundColor Yellow

$netAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
    [pscustomobject]@{
        name        = $_.Name
        interface   = $_.InterfaceDescription
        link_speed  = "$($_.LinkSpeed)"
        mac_address = $_.MacAddress
        status      = $_.Status
    }
})

$ipInfo = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '169.254.*' } |
    Select-Object InterfaceAlias, IPAddress, PrefixLength)

$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Sort-Object LocalPort -Unique |
    Select-Object LocalAddress, LocalPort, OwningProcess)

Write-Host ("Adapters   : {0}" -f $netAdapters.Count) -ForegroundColor Green
Write-Host ("Listeners  : {0}" -f $listeners.Count) -ForegroundColor Green

# -------------------------------------------------------------------
# Shell / developer toolchain
# -------------------------------------------------------------------
Write-Host "`n[6/12] SHELL / DEVELOPER TOOLCHAIN" -ForegroundColor Yellow

$toolchain = [ordered]@{
    powershell = [pscustomobject]@{
        version   = "$($PSVersionTable.PSVersion)"
        edition   = $PSVersionTable.PSEdition
        executable = (Get-Process -Id $PID).Path
    }
    git        = Get-CommandProbe 'git'
    rustc      = Get-CommandProbe 'rustc'
    cargo      = Get-CommandProbe 'cargo'
    node       = Get-CommandProbe 'node'
    npm        = Get-CommandProbe 'npm'
    pnpm       = Get-CommandProbe 'pnpm'
    yarn       = Get-CommandProbe 'yarn'
    python     = Get-CommandProbe 'python'
    python3    = Get-CommandProbe 'python3'
    pip        = Get-CommandProbe 'pip'
    docker     = Get-CommandProbe 'docker'
    wsl        = Get-CommandProbe 'wsl' @('--version')
    cmake      = Get-CommandProbe 'cmake'
    ninja      = Get-CommandProbe 'ninja'
    clang      = Get-CommandProbe 'clang'
    gcc        = Get-CommandProbe 'gcc'
    dotnet     = Get-CommandProbe 'dotnet'
}

foreach ($entry in $toolchain.GetEnumerator()) {
    if ($entry.Key -eq 'powershell') { continue }
    $state = if ($entry.Value.installed) { 'FOUND' } else { 'MISS' }
    $color = if ($entry.Value.installed) { 'Green' } else { 'DarkGray' }
    Write-Host ("{0,-11}: {1}" -f $entry.Key, $state) -ForegroundColor $color
}

# -------------------------------------------------------------------
# AI / local runtime ecosystem
# -------------------------------------------------------------------
Write-Host "`n[7/12] AI / LOCAL RUNTIME ECOSYSTEM" -ForegroundColor Yellow
Write-Host 'Installed Apps registry reader : STRICT-SAFE' -ForegroundColor Green
Write-Host 'AI runtime descriptor reader   : HETEROGENEOUS-SAFE' -ForegroundColor Green

$apps = Read-InstalledApps

$aiRuntime = [ordered]@{
    ollama = [pscustomobject]@{
        command = Get-CommandProbe 'ollama'
        apps    = Find-App $apps '(?i)ollama'
    }
    lm_studio = [pscustomobject]@{
        command = Get-CommandProbe 'lms'
        apps    = Find-App $apps '(?i)LM Studio'
    }
    freetoken = [pscustomobject]@{
        command = Get-CommandProbe 'freetoken'
        apps    = Find-App $apps '(?i)FreeToken|FlashML'
    }
    llama_cpp = [pscustomobject]@{
        command = Get-CommandProbe 'llama-cli'
        apps    = Find-App $apps '(?i)llama\.cpp'
    }
    cuda_toolkit = [pscustomobject]@{
        nvcc = Get-CommandProbe 'nvcc'
        apps = Find-App $apps '(?i)NVIDIA CUDA'
    }
}

foreach ($key in $aiRuntime.Keys) {
    $runtime = $aiRuntime[$key]
    $found = $false

    # Runtime descriptors are intentionally heterogeneous.
    # Some use "command", CUDA uses "nvcc", and future runtimes may
    # expose other command probes. Inspect properties safely instead
    # of assuming every descriptor has the same shape.
    foreach ($probeName in @('command', 'nvcc', 'cli', 'server')) {
        $probeProperty = $runtime.PSObject.Properties[$probeName]

        if ($null -eq $probeProperty) {
            continue
        }

        $probe = $probeProperty.Value
        if ($null -eq $probe) {
            continue
        }

        $installedProperty = $probe.PSObject.Properties['installed']
        if (
            $installedProperty -and
            [bool]$installedProperty.Value
        ) {
            $found = $true
            break
        }
    }

    $appsProperty = $runtime.PSObject.Properties['apps']
    if (
        -not $found -and
        $appsProperty -and
        $null -ne $appsProperty.Value -and
        @($appsProperty.Value).Count -gt 0
    ) {
        $found = $true
    }

    $state = if ($found) { 'FOUND' } else { 'MISS' }
    $color = if ($found) { 'Green' } else { 'DarkGray' }

    Write-Host ("{0,-12}: {1}" -f $key, $state) -ForegroundColor $color
}

# -------------------------------------------------------------------
# DB / server ecosystem
# -------------------------------------------------------------------
Write-Host "`n[8/12] DATABASE / SERVER ECOSYSTEM" -ForegroundColor Yellow

$dbServer = [ordered]@{
    postgresql = [pscustomobject]@{
        psql = Get-CommandProbe 'psql'
        apps = Find-App $apps '(?i)PostgreSQL'
    }
    sqlite = [pscustomobject]@{
        command = Get-CommandProbe 'sqlite3'
        apps    = Find-App $apps '(?i)SQLite'
    }
    sql_server = [pscustomobject]@{
        sqlcmd = Get-CommandProbe 'sqlcmd'
        apps   = Find-App $apps '(?i)Microsoft SQL Server'
    }
    filemaker_server = [pscustomobject]@{
        apps = Find-App $apps '(?i)FileMaker Server|Claris Server'
    }
}

$relevantServices = @(Get-Service -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '(?i)postgres|docker|ollama|mssql|filemaker|claris|vertex'
    } |
    Select-Object Name, DisplayName, Status, StartType)

Write-Host ("Relevant services: {0}" -f $relevantServices.Count) -ForegroundColor Green

# -------------------------------------------------------------------
# Windows build prerequisites
# -------------------------------------------------------------------
Write-Host "`n[9/12] WINDOWS BUILD PREREQUISITES" -ForegroundColor Yellow

$vswhereCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
    "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
)

$vswhere = $vswhereCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$visualStudio = $null

if ($vswhere) {
    try {
        $raw = & $vswhere -all -format json -products * 2>$null | ConvertFrom-Json
        $visualStudio = @($raw | ForEach-Object {
            [pscustomobject]@{
                display_name     = $_.displayName
                installation_path = $_.installationPath
                installation_version = $_.installationVersion
                product_id       = $_.productId
            }
        })
    } catch {}
}

$buildPrereqs = [ordered]@{
    vswhere = [pscustomobject]@{
        found = [bool]$vswhere
        path  = $vswhere
    }
    visual_studio = $visualStudio
    webview2_apps = Find-App $apps '(?i)WebView2'
    vc_runtime_apps = Find-App $apps '(?i)Visual C\+\+.*Redistributable'
}

Write-Host ("Visual Studio / Build Tools installs: {0}" -f @($visualStudio).Count) -ForegroundColor Green

# -------------------------------------------------------------------
# Vertex footprint / portable awareness
# -------------------------------------------------------------------
Write-Host "`n[10/12] VERTEX FOOTPRINT / PORTABLE SIGNALS" -ForegroundColor Yellow

$vertexPaths = @(
    'G:\Vertex_Project',
    'G:\Vertex_Project\Vertex_Studio_AI',
    'G:\Vertex_Project\Vertex_Studio_AI\HANGER',
    'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package',
    'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2',
    'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\_build'
)

$vertexFootprint = @($vertexPaths | ForEach-Object { Get-DirectoryStats $_ })

$removableVolumes = @()
try {
    $removableVolumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' | ForEach-Object {
        [pscustomobject]@{
            device_id  = $_.DeviceID
            volume_name = $_.VolumeName
            filesystem  = $_.FileSystem
            size_gib    = Convert-BytesToGiB $_.Size
            free_gib    = Convert-BytesToGiB $_.FreeSpace
        }
    })
} catch {}

Write-Host ("Vertex paths observed : {0}" -f @($vertexFootprint | Where-Object exists).Count) -ForegroundColor Green
Write-Host ("Removable volumes     : {0}" -f $removableVolumes.Count) -ForegroundColor Green

# -------------------------------------------------------------------
# Environment variables (selected; values intentionally limited)
# -------------------------------------------------------------------
Write-Host "`n[11/12] ENVIRONMENT / SECURITY / VIRTUALIZATION SIGNALS" -ForegroundColor Yellow

$selectedEnv = [ordered]@{
    PATH_present          = [bool]$env:PATH
    CARGO_HOME            = $env:CARGO_HOME
    RUSTUP_HOME           = $env:RUSTUP_HOME
    PNPM_HOME             = $env:PNPM_HOME
    NODE_OPTIONS          = $env:NODE_OPTIONS
    CUDA_PATH             = $env:CUDA_PATH
    HF_HOME               = $env:HF_HOME
    OLLAMA_MODELS         = $env:OLLAMA_MODELS
    DOCKER_HOST           = $env:DOCKER_HOST
    VERTEX_HOME           = $env:VERTEX_HOME
    CARGO_TARGET_DIR      = $env:CARGO_TARGET_DIR
}

$securitySignals = [ordered]@{
    secure_boot = (Invoke-Observation 'Confirm-SecureBootUEFI' {
        Confirm-SecureBootUEFI
    })
    tpm = (Invoke-Observation 'Get-Tpm' {
        $tpm = Get-Tpm
        [pscustomobject]@{
            present = $tpm.TpmPresent
            ready   = $tpm.TpmReady
            enabled = $tpm.TpmEnabled
        }
    })
    hyper_v_optional_feature = (Invoke-Observation 'Hyper-V' {
        Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All |
            Select-Object FeatureName, State
    })
    virtual_machine_platform = (Invoke-Observation 'VirtualMachinePlatform' {
        Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform |
            Select-Object FeatureName, State
    })
    wsl_feature = (Invoke-Observation 'WSL' {
        Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux |
            Select-Object FeatureName, State
    })
}


# -------------------------------------------------------------------
# Windows Terminal default profile / starting directory
# -------------------------------------------------------------------
Write-Host "`n[11.5/12] WINDOWS TERMINAL PROFILE" -ForegroundColor Yellow

$terminalSettings = Get-WindowsTerminalSettings

if ($terminalSettings.found) {
    Write-Host ("Terminal settings : {0}" -f $terminalSettings.settings_path) -ForegroundColor Green
    Write-Host ("Default profile   : {0}" -f $terminalSettings.default_profile_name) -ForegroundColor Green
    Write-Host ("PowerShell 7      : {0}" -f $terminalSettings.powershell7_profile) -ForegroundColor Green
    Write-Host ("Starting dir      : {0}" -f $terminalSettings.starting_directory) -ForegroundColor Green
    Write-Host ("Mothership start  : {0}" -f $terminalSettings.vertex_mothership_start) -ForegroundColor Green
}
else {
    Write-Host 'Windows Terminal settings: NOT FOUND' -ForegroundColor Yellow
}

# -------------------------------------------------------------------
# Capability signals — observational only, no installation decisions.
# -------------------------------------------------------------------
Write-Host "`n[12/12] CAPABILITY SIGNALS / PROFILE WRITE" -ForegroundColor Yellow

$largestFreeVolume = $volumes | Sort-Object free_gib -Descending | Select-Object -First 1
$primaryNvidia = $nvidia.gpus | Sort-Object vram_total_mib -Descending | Select-Object -First 1

$signals = [ordered]@{
    powershell7_primary = ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7)
    git_ready            = [bool]$toolchain.git.installed
    rust_ready           = [bool]($toolchain.rustc.installed -and $toolchain.cargo.installed)
    node_ready           = [bool]$toolchain.node.installed
    pnpm_ready           = [bool]$toolchain.pnpm.installed
    docker_detected      = [bool]$toolchain.docker.installed
    nvidia_gpu_detected  = [bool]($nvidia.available -and @($nvidia.gpus).Count -gt 0)
    nvidia_vram_gib      = if ($primaryNvidia) { [math]::Round($primaryNvidia.vram_total_mib / 1024, 2) } else { $null }
    host_ram_gib         = $memoryInfo.total_gib
    largest_free_volume  = if ($largestFreeVolume) { $largestFreeVolume.drive_letter } else { $null }
    largest_free_gib     = if ($largestFreeVolume) { $largestFreeVolume.free_gib } else { $null }
    removable_media_seen = ($removableVolumes.Count -gt 0)
    vertex_install_seen  = (@($vertexFootprint | Where-Object exists).Count -gt 0)
    server_services_seen = ($relevantServices.Count -gt 0)
    windows_terminal_found = [bool]$terminalSettings.found
    windows_terminal_default_ps7 = [bool]$terminalSettings.powershell7_profile
    windows_terminal_vertex_start = [bool]$terminalSettings.vertex_mothership_start
}

$profile = [ordered]@{
    schema      = $Schema
    mission_id  = $MissionId
    mode        = 'READ_ONLY_OBSERVATION'
    started_at  = $StartedAt.ToString('o')
    finished_at = (Get-Date).ToString('o')
    host        = $hostInfo
    cpu         = $cpuInfo
    memory      = $memoryInfo
    gpu = [ordered]@{
        cim    = $gpuCim
        nvidia = $nvidia
    }
    storage = [ordered]@{
        volumes        = $volumes
        physical_disks = $physicalDisks
    }
    network = [ordered]@{
        adapters  = $netAdapters
        ipv4      = $ipInfo
        listeners = $listeners
    }
    toolchain          = $toolchain
    ai_runtime         = $aiRuntime
    database_server    = $dbServer
    relevant_services  = $relevantServices
    build_prerequisites = $buildPrereqs
    vertex = [ordered]@{
        footprint         = $vertexFootprint
        removable_volumes = $removableVolumes
    }
    environment = $selectedEnv
    security_virtualization = $securitySignals
    windows_terminal = $terminalSettings
    installed_apps_summary = [ordered]@{
        count = $apps.Count
        # Full installed-app list intentionally omitted from main profile
        # to keep ENV-0 compact. Relevant packages are captured above.
    }
    capability_signals = $signals
}

$profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $JsonPath -Encoding utf8

$summary = @"
============================================================
 VERTEX ENV-0 — HOST SURVEY COMPLETE
============================================================
 Mission                : $MissionId
 Mode                   : READ-ONLY OBSERVATION
 Host                   : $($hostInfo.computer_name)
 OS                     : $($hostInfo.os_caption)
 Build                  : $($hostInfo.os_build)
 PowerShell             : $($PSVersionTable.PSVersion) / $($PSVersionTable.PSEdition)
 CPU                    : $(($cpuInfo | ForEach-Object name) -join ' / ')
 RAM                    : $($memoryInfo.total_gib) GiB
 NVIDIA GPU             : $(if($primaryNvidia){$primaryNvidia.name}else{'NOT DETECTED'})
 NVIDIA VRAM            : $(if($signals.nvidia_vram_gib){$signals.nvidia_vram_gib}else{'N/A'}) GiB
 Largest Free Volume    : $($signals.largest_free_volume)
 Largest Free Space     : $($signals.largest_free_gib) GiB

 Git Ready              : $($signals.git_ready)
 Rust Ready             : $($signals.rust_ready)
 Node Ready             : $($signals.node_ready)
 pnpm Ready             : $($signals.pnpm_ready)
 Docker Detected        : $($signals.docker_detected)
 Vertex Install Seen    : $($signals.vertex_install_seen)
 Removable Media Seen   : $($signals.removable_media_seen)
 Server Services Seen   : $($signals.server_services_seen)
 Terminal Found         : $($signals.windows_terminal_found)
 Default Profile PS7    : $($signals.windows_terminal_default_ps7)
 Vertex Start Directory : $($signals.windows_terminal_vertex_start)

 JSON Profile           : $JsonPath
 Human Summary          : $TextPath
------------------------------------------------------------
 NEXT MISSION
 ENV-1 — Vertex Environment Planner
------------------------------------------------------------
 NO INSTALL
 NO UNINSTALL
 NO REGISTRY MUTATION
 NO SERVICE MUTATION
 NO FIREWALL MUTATION
 NO PATH MUTATION
============================================================
"@

$summary | Set-Content -LiteralPath $TextPath -Encoding utf8
Write-Host $summary -ForegroundColor Green
