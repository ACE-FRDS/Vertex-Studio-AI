#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Mission='VERTEX_ENV_1_ENVIRONMENT_PLANNER'
function P {
    param(
        $Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function F {
    param(
        [string]$Area,
        [string]$Status,
        [string]$Title,
        [string]$Detail,
        [string]$Action = '',
        [bool]$Blocking = $false
    )

    return [pscustomobject]@{
        area     = $Area
        status   = $Status
        title    = $Title
        detail   = $Detail
        action   = $Action
        blocking = $Blocking
    }
}

function Rank {
    param([string]$Status)

    switch ($Status) {
        'RED'     { return 4 }
        'ORANGE'  { return 3 }
        'YELLOW'  { return 2 }
        'UNKNOWN' { return 1 }
        default   { return 0 }
    }
}
$roots=@(
'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2\ProgramSource\_vertex_reports',
'G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\_vertex_reports',
(Join-Path $PSScriptRoot '_vertex_reports'))
$root=$roots|?{Test-Path $_}|select -First 1
if (!$root){throw 'ENV-1: report directory not found. Run ENV-0 first.'}
$pf=Get-ChildItem $root -Filter 'VERTEX_HOST_PROFILE.*.json' -File|sort LastWriteTime -Descending|select -First 1
if (!$pf){throw 'ENV-1: Host Profile not found. Run ENV-0 first.'}
$p=Get-Content $pf.FullName -Raw -Encoding utf8|ConvertFrom-Json
$find=[Collections.Generic.List[object]]::new()
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host ' VERTEX ENV-1 - ENVIRONMENT PLANNER V2' -ForegroundColor Magenta
Write-Host ' PROFILE -> REQUIREMENTS -> GAP -> PLAN / READ ONLY' -ForegroundColor Magenta
Write-Host ' PARSER SAFETY -> NORMALIZED POWERSHELL SYNTAX' -ForegroundColor Magenta
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host "Profile: $($pf.FullName)" -ForegroundColor Green

Write-Host "`n[1/7] SHELL" -ForegroundColor Yellow
$ps=P (P $p toolchain) powershell
$v=[version](P $ps version '0.0');$ed=[string](P $ps edition '');$exe=[string](P $ps executable '')
if ($v.Major-ge 7-and$ed-eq'Core'-and$exe-match'\\pwsh\.exe$'){$find.Add((F shell GREEN 'PowerShell 7 verified' "$v / $ed / $exe"))}
else{$find.Add((F shell RED 'PowerShell mismatch' "$v / $ed / $exe" 'Use pwsh 7+ and re-run ENV-0.' $true))}
$find.Add((F shell UNKNOWN 'Terminal default/working directory not yet machine-verified' 'Current ENV-0 schema verifies the actual process, not Windows Terminal defaultProfile/startingDirectory.' 'Add read-only Terminal settings inspection to ENV-0 V4.'))

Write-Host '[2/7] DEVELOPMENT' -ForegroundColor Yellow
$tc=P $p toolchain
foreach ($spec in @(
@('git',$true),@('rustc',$true),@('cargo',$true),@('node',$true),@('pnpm',$true),
@('cmake',$false),@('ninja',$false),@('clang',$false),@('docker',$false))){
$n=$spec[0];$req=[bool]$spec[1];$ok=[bool](P (P $tc $n) installed $false)
if ($ok){$find.Add((F development GREEN "$n ready" 'Detected by ENV-0.'))}
elseif ($req){$find.Add((F development RED "$n missing" 'Required for VSA development.' "Install/repair $n after Human Gate." $true))}
else{$find.Add((F development YELLOW "$n not detected" 'Optional workload dependency.' 'Install only if selected role requires it.'))}}

Write-Host '[3/7] AI / CUDA' -ForegroundColor Yellow
$ng=P (P $p gpu) nvidia;$gpus=@(P $ng gpus @());$g=$gpus|sort {[int](P $_ vram_total_mib 0)} -Descending|select -First 1
if ([bool](P $ng available $false)-and$g){$vg=[math]::Round(([double](P $g vram_total_mib 0))/1024,2);$find.Add((F ai GREEN 'NVIDIA GPU detected' "$(P $g name) / $vg GiB"))}
else{$find.Add((F ai YELLOW 'NVIDIA GPU not detected' 'CPU fallback may be required.'))}
$ar=P $p ai_runtime
foreach ($n in @('ollama','lm_studio','freetoken','llama_cpp','cuda_toolkit')){
$r=P $ar $n;$ok=$false
foreach ($q in @('command','nvcc','cli','server')){$z=P $r $q;if ([bool](P $z installed $false)){$ok=$true}}
if (@(P $r apps @()).Count-gt 0){$ok=$true}
$find.Add((F ai $(if ($ok){'GREEN'}else{'YELLOW'}) "$n detection" $(if ($ok){'Detected.'}else{'Not detected; optional unless role requires it.'})))}

Write-Host '[4/7] STORAGE' -ForegroundColor Yellow
$vols=@(P (P $p storage) volumes @());$cand=@()
foreach ($z in $vols){$d=[string](P $z drive_letter '');$free=[double](P $z free_gib 0);$pct=[double](P $z free_percent 0);$fs=[string](P $z filesystem '');$h=[string](P $z health '')
$st='GREEN';$score=100
if (($h-and$h-ne'Healthy')-or$free-lt 20-or$pct-lt 5){$st='RED';$score=0}
elseif ($free-lt 50-or$pct-lt 10){$st='ORANGE';$score=30}
elseif ($free-lt 100-or$pct-lt 20){$st='YELLOW';$score=60}
if ($d-eq'C:'){$score-=15};if ($fs-eq'NTFS'){$score+=5};$score+=[math]::Min(40,[math]::Floor($free/50))
$cand+=[pscustomobject]@{drive=$d;status=$st;score=[int]$score;free_gib=$free;free_percent=$pct;filesystem=$fs;health=$h}
$find.Add((F storage $st "$d storage" "$free GiB free / $pct% / $fs / $h" $(if ($st-eq'RED'){'Do not place new Vertex payloads here.'}else{''}) ($st-eq'RED')))}
$best=$cand|? status -ne RED|sort score -Descending|select -First 1

Write-Host '[5/7] SERVER / PORTS' -ForegroundColor Yellow
$svc=@(P $p relevant_services @());$lis=@(P (P $p network) listeners @())
if ($svc.Count){$find.Add((F server YELLOW 'Existing server services detected' "$($svc.Count) relevant services present." 'Never overwrite/reconfigure without an approved plan.'))}
foreach ($port in @(3000,5173,5432,8000,8080,11434)){if (@($lis|?{[int](P $_ LocalPort 0)-eq$port}).Count){$find.Add((F ports YELLOW "Port $port is listening" 'Potential runtime collision.' 'Resolve ownership before binding.'))}}

Write-Host '[6/7] PORTABLE / ROLE MATRIX' -ForegroundColor Yellow
$rem=@(P (P $p vertex) removable_volumes @());$sig=P $p capability_signals;$ram=[double](P (P $p memory) total_gib 0)
$roles=@(
[pscustomobject]@{role='VSA_DEVELOPMENT';status=$(if ((P $sig rust_ready $false)-and(P $sig node_ready $false)-and(P $sig git_ready $false)-and$ram-ge16){'GREEN'}else{'RED'});reason='Git + Rust + Node + >=16 GiB RAM'},
[pscustomobject]@{role='AI_INFERENCE_NODE';status=$(if ((P $sig nvidia_gpu_detected $false)-and$ram-ge16){'GREEN'}elseif ($ram-ge16){'YELLOW'}else{'RED'});reason='GPU preferred; CPU fallback possible'},
[pscustomobject]@{role='VERTEX_SERVER';status=$(if ($ram-ge16-and$best){'YELLOW'}else{'RED'});reason='Requires service/port deployment planning'},
[pscustomobject]@{role='CUSTOMER_RUNTIME';status=$(if ($ram-ge8-and$best){'GREEN'}else{'RED'});reason='>=8 GiB RAM and viable storage'},
[pscustomobject]@{role='USB_PORTABLE_HOST';status=$(if ($rem.Count){'YELLOW'}else{'UNKNOWN'});reason='Media/performance policy needs further evaluation'})
if ($rem.Count){$find.Add((F portable GREEN 'Removable media detected' "$($rem.Count) volume(s)."))}

Write-Host '[7/7] PLAN' -ForegroundColor Yellow
$overall='GREEN';$max=0
foreach ($x in $find){$r=Rank $x.status;if ($r-gt$max){$max=$r;$overall=$x.status}}
$stamp=Get-Date -Format yyyyMMdd-HHmmss;$jp=Join-Path $root "VERTEX_ENVIRONMENT_PLAN.$stamp.json";$tp=Join-Path $root "VERTEX_ENVIRONMENT_PLAN.$stamp.txt"
$plan=[ordered]@{schema='vertex.environment.plan.v1';mission_id=$Mission;generated_at=(Get-Date).ToString('o');source_profile=$pf.FullName;mode='READ_ONLY_PLANNING';overall_status=$overall;recommended_volume=$best;placement_candidates=@($cand|sort score -Descending);role_matrix=$roles;findings=@($find);execution_policy=[ordered]@{install=$false;uninstall=$false;registry_mutation=$false;service_mutation=$false;firewall_mutation=$false;path_mutation=$false;requires_human_gate_before_env2=$true};next_mission='ENV-2 Package Lifecycle / Deployment Executor'}
$plan|ConvertTo-Json -Depth 12|Set-Content $jp -Encoding utf8
$rl=($roles|%{"  {0,-22} {1,-8} {2}"-f$_.role,$_.status,$_.reason})-join"`r`n"
$att=(@($find)|? status -in RED,ORANGE,YELLOW,UNKNOWN|sort @{e={Rank $_.status};Descending=$true}|%{"  [{0}] {1}: {2}"-f$_.status,$_.title,$_.detail})-join"`r`n"
$txt=@"
============================================================
 VERTEX ENV-1 - ENVIRONMENT PLAN
============================================================
 Source Profile     : $($pf.Name)
 Overall Status     : $overall
 Recommended Volume : $(if ($best){$best.drive}else{'NONE'})
 Free Space         : $(if ($best){$best.free_gib}else{'N/A'}) GiB

 ROLE MATRIX
$rl

 ATTENTION / GAPS
$att

 POLICY
  Scanner observes.
  Planner recommends.
  Human approves.
  ENV-2 executes.
  ENV-0 re-surveys and verifies.

 NO INSTALL / NO UNINSTALL / NO SYSTEM MUTATION

 JSON : $jp
 TXT  : $tp
============================================================
"@
$txt|Set-Content $tp -Encoding utf8
Write-Host $txt -ForegroundColor Green
