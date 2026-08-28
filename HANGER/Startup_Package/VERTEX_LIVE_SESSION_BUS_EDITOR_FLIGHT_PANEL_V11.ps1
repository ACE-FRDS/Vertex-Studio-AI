& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX CIC — LIVE SESSION BUS / EDITOR FLIGHT PANEL V11
# Windows PowerShell 5.1 compatible
#
# Doctrine:
#   - CURRENT v0.2 ONLY
#   - LEGACY untouched
#   - FleetControllerSession remains source of truth
#   - no duplicate/fake controller state in Tauri
#   - Mothership publishes observation snapshots only
#   - Live helper functions are injected into the same Rust module as run_autonomous_mission_step
#   - Tauri ProgramSource resolver is discovered from existing Rust, never guessed by name
#   - AgentMissionDispatch is treated as an opaque/thin execution contract
#   - only execution_id is required from AgentMissionDispatch
#   - no mission_id / agent_id is invented
#   - mission set comes from FleetReadyWave
#   - completed mission evidence comes from AutonomousWaveRecord
#   - Tauri reads through fixed IPC commands
#   - Editor polls live state at 350ms
#   - targeted autonomous voyage proves real emission
#   - RED => atomic rollback
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'
$runtimeDir=Join-Path $core '_vertex_runtime'
$tauri=Join-Path $ui 'src-tauri'
$tauriLib=Join-Path $tauri 'src\lib.rs'
$tauriCargo=Join-Path $tauri 'Cargo.toml'
$transport=Join-Path $ui 'src\vertex-editor\transport.ts'
$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$panel=Join-Path $ui 'src\vertex-editor\VertexLiveFlightPanel.vue'
$coreCargo=Join-Path $core 'Cargo.toml'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "LIVE_SESSION_BUS_V11_BACKUP.$stamp"
$failed=Join-Path $reports "LIVE_SESSION_BUS_V11_FAILED.$stamp"
$report=Join-Path $reports "LIVE_SESSION_BUS_V11.$stamp.json"
$utf8=New-Object System.Text.UTF8Encoding($false)

function WriteUtf8([string]$Path,[string]$Content){
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,$Content,$utf8)
}
function RequireCommand([string]$Name){
  $c=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $c){throw "Missing command: $Name"}
  return $c
}
function RunChecked([string]$Label,[scriptblock]$Action){
  Write-Host "`n$Label" -ForegroundColor Cyan
  & $Action
  if($LASTEXITCODE -ne 0){throw "$Label RED ($LASTEXITCODE)"}
}
function BackupFile([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){return}
  $rel=$Path.Substring($base.Length).TrimStart('\').Replace('\','__')
  Copy-Item -LiteralPath $Path -Destination (Join-Path $backup $rel) -Force
}
function RestoreBackupFile([string]$Path){
  $rel=$Path.Substring($base.Length).TrimStart('\').Replace('\','__')
  $src=Join-Path $backup $rel
  if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination $Path -Force}
}
function FindMatchingBrace([string]$Text,[int]$OpenIndex){
  $depth=0
  $inString=$false
  $quote=[char]0
  $escape=$false
  for($i=$OpenIndex;$i -lt $Text.Length;$i++){
    $ch=$Text[$i]
    if($inString){
      if($escape){$escape=$false;continue}
      if($ch -eq '\'){$escape=$true;continue}
      if($ch -eq $quote){$inString=$false}
      continue
    }
    if($ch -eq '"' -or $ch -eq "'"){$inString=$true;$quote=$ch;continue}
    if($ch -eq '{'){$depth++}
    elseif($ch -eq '}'){
      $depth--
      if($depth -eq 0){return $i}
    }
  }
  return -1
}
function FindEnclosingModule([string]$Text,[int]$Position){
  $matches=[regex]::Matches(
    $Text,
    '(?m)^\s*(?:(?:pub(?:\([^)]*\))?)\s+)?mod\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\{'
  )

  $best=$null

  foreach($m in $matches){
    if($m.Index -ge $Position){continue}

    $open=$Text.IndexOf('{',$m.Index)
    if($open -lt 0){continue}

    $close=FindMatchingBrace $Text $open
    if($close -lt 0){continue}

    if($close -gt $Position){
      if($null -eq $best -or $open -gt $best.Open){
        $best=[pscustomobject]@{
          Name=$m.Groups['name'].Value
          Open=$open
          Close=$close
        }
      }
    }
  }

  return $best
}

function ExtractStructBody([string]$All,[string]$Name){
  $m=[regex]::Match($All,"pub\s+struct\s+$Name\s*\{")
  if(-not $m.Success){return $null}
  $open=$All.IndexOf('{',$m.Index)
  $close=FindMatchingBrace $All $open
  if($close -lt 0){return $null}
  return $All.Substring($open+1,$close-$open-1)
}

Write-Host @'
============================================================
 VERTEX — LIVE SESSION BUS / EDITOR FLIGHT PANEL V11
 REAL MOTHERSHIP STATE -> TAURI IPC -> EDITOR
============================================================
'@ -ForegroundColor Cyan

foreach($p in @($startup,$base,$ui,$core,$reports,$tauriLib,$tauriCargo,$transport,$editor,$coreCargo)){
  if(-not(Test-Path -LiteralPath $p)){throw "Required V6 GREEN artifact missing: $p"}
}
if(Test-Path -LiteralPath $panel){throw "Live Flight Panel already exists. Refusing duplicate V7 docking."}

$cargo=RequireCommand 'cargo'
$rustfmt=RequireCommand 'rustfmt'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/10] V6 GREEN BASELINE LOCK" -ForegroundColor Yellow
Push-Location $ui
try{
  RunChecked '[baseline] frontend build' {& $pnpm.Source build}
}finally{Pop-Location}
RunChecked '[baseline] Tauri cargo check' {& $cargo.Source check --manifest-path $tauriCargo --all-targets}
RunChecked '[baseline] ProgramSource cargo check' {& $cargo.Source check --manifest-path $coreCargo --workspace --all-targets}

Write-Host "`n[1/10] DISCOVER LIVE CONTRACTS IN CURRENT PROGRAMSOURCE" -ForegroundColor Yellow

$allRust=@(Get-ChildItem -LiteralPath (Join-Path $core 'crates') -Filter '*.rs' -File -Recurse -ErrorAction Stop)

$sessionDef=$allRust|Select-String -Pattern 'pub struct FleetControllerSession' -SimpleMatch -List|Select-Object -First 1
$waveDef=$allRust|Select-String -Pattern 'pub struct FleetReadyWave' -SimpleMatch -List|Select-Object -First 1
$dispatchDef=$allRust|Select-String -Pattern 'pub struct MultiAgentDispatchPlan' -SimpleMatch -List|Select-Object -First 1
$assignmentDef=$allRust|Select-String -Pattern 'pub struct AgentMissionDispatch' -SimpleMatch -List|Select-Object -First 1
$recordDef=$allRust|Select-String -Pattern 'pub struct AutonomousWaveRecord' -SimpleMatch -List|Select-Object -First 1
$loopHit=$allRust|Select-String -Pattern 'pub fn run_autonomous_mission_step' -SimpleMatch -List|Select-Object -First 1

foreach($pair in @(
  @('FleetControllerSession',$sessionDef),
  @('FleetReadyWave',$waveDef),
  @('MultiAgentDispatchPlan',$dispatchDef),
  @('AgentMissionDispatch',$assignmentDef),
  @('AutonomousWaveRecord',$recordDef),
  @('run_autonomous_mission_step',$loopHit)
)){
  if(-not $pair[1]){throw "Required live contract not found: $($pair[0])"}
  Write-Host ("  {0,-30} {1}" -f $pair[0],$pair[1].Path) -ForegroundColor Green
}

$contractFiles=@($sessionDef.Path,$waveDef.Path,$dispatchDef.Path,$assignmentDef.Path,$recordDef.Path)|Select-Object -Unique
$contracts=($contractFiles|ForEach-Object{[IO.File]::ReadAllText($_)}) -join "`n"

$sessionBody=ExtractStructBody $contracts 'FleetControllerSession'
$waveBody=ExtractStructBody $contracts 'FleetReadyWave'
$dispatchBody=ExtractStructBody $contracts 'MultiAgentDispatchPlan'
$assignmentBody=ExtractStructBody $contracts 'AgentMissionDispatch'
$recordBody=ExtractStructBody $contracts 'AutonomousWaveRecord'

foreach($body in @($sessionBody,$waveBody,$dispatchBody,$assignmentBody,$recordBody)){
  if($null -eq $body){throw 'Unable to parse one or more required Rust struct bodies.'}
}

foreach($requiredField in @('session_id','current_wave','completed_waves','status')){
  if($sessionBody -notmatch "pub\s+$requiredField\s*:"){throw "FleetControllerSession field missing: $requiredField"}
}
foreach($requiredField in @('wave_id','ready_mission_ids','blocked_mission_ids','waiting_mission_ids','dispatch')){
  if($waveBody -notmatch "pub\s+$requiredField\s*:"){throw "FleetReadyWave field missing: $requiredField"}
}
foreach($requiredField in @('dispatch_id')){
  if($dispatchBody -notmatch "pub\s+$requiredField\s*:"){throw "MultiAgentDispatchPlan field missing: $requiredField"}
}
foreach($requiredField in @('execution_id')){
  if($assignmentBody -notmatch "pub\s+$requiredField\s*:"){throw "AgentMissionDispatch field missing: $requiredField"}
}

$assignmentFields=@(
  [regex]::Matches($assignmentBody,'pub\s+(?<name>\w+)\s*:') |
  ForEach-Object { $_.Groups['name'].Value }
)
Write-Host ("AgentMissionDispatch fields: " + ($assignmentFields -join ', ')) -ForegroundColor Green
Write-Host 'V9 rule: execution_id is the only required direct field.' -ForegroundColor Green
Write-Host 'Mission/Agent mapping will not be inferred from AgentMissionDispatch.' -ForegroundColor Yellow
foreach($requiredField in @('sequence','session_id','wave_id','dispatch_id','mission_ids','process_results','emitted_event_count','checkpoint','resulting_status')){
  if($recordBody -notmatch "pub\s+$requiredField\s*:"){throw "AutonomousWaveRecord field missing: $requiredField"}
}

$assignmentFieldMatch=[regex]::Match($dispatchBody,'pub\s+(?<name>\w+)\s*:\s*Vec\s*<\s*AgentMissionDispatch\s*>')
if(-not $assignmentFieldMatch.Success){throw 'Could not discover Vec<AgentMissionDispatch> field in MultiAgentDispatchPlan.'}
$assignmentField=$assignmentFieldMatch.Groups['name'].Value
Write-Host "Dispatch assignment field: $assignmentField" -ForegroundColor Green

$loopFile=$loopHit.Path
$loopText=[IO.File]::ReadAllText($loopFile)
if($loopText.Contains('VERTEX LIVE SESSION BUS V1')){throw 'Live Session Bus marker already present.'}

$stepMatch=[regex]::Match($loopText,'pub\s+fn\s+run_autonomous_mission_step\b[\s\S]*?\{')
if(-not $stepMatch.Success){throw 'Cannot locate run_autonomous_mission_step opening brace.'}
$stepOpen=$stepMatch.Index+$stepMatch.Length

$stepModule=FindEnclosingModule $loopText $stepMatch.Index
if($null -eq $stepModule){throw 'Cannot locate enclosing module for run_autonomous_mission_step.'}
Write-Host ("Autonomous step module : " + $stepModule.Name) -ForegroundColor Green

$recordMatch=[regex]::Match($loopText,'let\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*AutonomousWaveRecord\s*\{')
if(-not $recordMatch.Success){throw 'Cannot discover AutonomousWaveRecord construction.'}
$recordVar=$recordMatch.Groups['name'].Value
$recordOpen=$loopText.IndexOf('{',$recordMatch.Index)
$recordClose=FindMatchingBrace $loopText $recordOpen
if($recordClose -lt 0){throw 'Cannot find end of AutonomousWaveRecord construction.'}
$afterRecord=$recordClose+1
while($afterRecord -lt $loopText.Length -and [char]::IsWhiteSpace($loopText[$afterRecord])){$afterRecord++}
if($afterRecord -lt $loopText.Length -and $loopText[$afterRecord] -eq ';'){$afterRecord++}

Write-Host "Autonomous loop file : $loopFile" -ForegroundColor Green
Write-Host "Wave record variable : $recordVar" -ForegroundColor Green

$mothershipRoot=Split-Path -Parent (Split-Path -Parent $loopFile)
$mothershipCargo=Join-Path $mothershipRoot 'Cargo.toml'
if(-not(Test-Path -LiteralPath $mothershipCargo)){throw "Mothership Cargo.toml missing: $mothershipCargo"}

Write-Host "`n[2/10] ATOMIC BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
foreach($p in @($loopFile,$tauriLib,$transport,$editor)){BackupFile $p}
if(Test-Path -LiteralPath $panel){BackupFile $panel}

$runtimeBefore=0
$timeline=Join-Path $runtimeDir 'live_session.ndjson'
if(Test-Path -LiteralPath $timeline){
  $runtimeBefore=@(Get-Content -LiteralPath $timeline -ErrorAction SilentlyContinue).Count
}
Write-Host "Live timeline baseline lines: $runtimeBefore" -ForegroundColor Green

try{
  Write-Host "`n[3/10] INSTALL MOTHERSHIP LIVE SESSION OBSERVER" -ForegroundColor Yellow

  $helpers=@"


// VERTEX LIVE SESSION BUS V1
fn vertex_live_json_escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 16);
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn vertex_live_quote(value: &str) -> String {
    format!("\"{}\"", vertex_live_json_escape(value))
}

fn vertex_live_string_array(values: &[String]) -> String {
    let body = values
        .iter()
        .map(|value| vertex_live_quote(value))
        .collect::<Vec<_>>()
        .join(",");
    format!("[{}]", body)
}

fn vertex_live_runtime_dir() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("_vertex_runtime")
}

fn vertex_live_publish_json(json: &str) {
    use std::io::Write;

    let dir = vertex_live_runtime_dir();
    if std::fs::create_dir_all(&dir).is_err() {
        return;
    }

    let latest = dir.join("live_session_latest.json");
    let temp = dir.join("live_session_latest.tmp");

    if std::fs::write(&temp, json.as_bytes()).is_ok() {
        let _ = std::fs::remove_file(&latest);
        let _ = std::fs::rename(&temp, &latest);
    }

    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join("live_session.ndjson"))
    {
        let _ = writeln!(file, "{}", json);
    }
}

fn vertex_live_publish_preflight(session: &FleetControllerSession) {
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();

    let (dispatch_id, executions) = match session.current_wave.dispatch.as_ref() {
        Some(dispatch) => {
            let executions = dispatch.$assignmentField
                .iter()
                .map(|execution| {
                    format!(
                        "{{\"execution_id\":{}}}",
                        vertex_live_quote(&execution.execution_id)
                    )
                })
                .collect::<Vec<_>>()
                .join(",");

            (dispatch.dispatch_id.clone(), format!("[{}]", executions))
        }
        None => (String::new(), "[]".to_owned()),
    };

    let json = format!(
        "{{\"schema\":\"vertex.mothership.live-session.v1\",\"kind\":\"wave_scheduled\",\"timestamp_ms\":{},\"session\":{{\"session_id\":{},\"status\":{},\"completed_waves\":{}}},\"wave\":{{\"wave_id\":{},\"ready\":{},\"blocked\":{},\"waiting\":{}}},\"dispatch\":{{\"dispatch_id\":{},\"mission_set\":{},\"executions\":{}}},\"genesis\":{{\"event_count\":0}},\"vsp\":null}}",
        now_ms,
        vertex_live_quote(&session.session_id),
        vertex_live_quote(&format!("{:?}", session.status)),
        session.completed_waves,
        vertex_live_quote(&session.current_wave.wave_id),
        vertex_live_string_array(&session.current_wave.ready_mission_ids),
        vertex_live_string_array(&session.current_wave.blocked_mission_ids),
        vertex_live_string_array(&session.current_wave.waiting_mission_ids),
        vertex_live_quote(&dispatch_id),
        vertex_live_string_array(&session.current_wave.ready_mission_ids),
        executions
    );

    vertex_live_publish_json(&json);
}

fn vertex_live_publish_postflight<C: std::fmt::Debug>(
    record: &AutonomousWaveRecord,
    checkpoint: &C,
) {
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();

    let json = format!(
        "{{\"schema\":\"vertex.mothership.live-session.v1\",\"kind\":\"wave_completed\",\"timestamp_ms\":{},\"session\":{{\"session_id\":{},\"status\":{},\"completed_waves\":{}}},\"wave\":{{\"sequence\":{},\"wave_id\":{},\"missions\":{},\"resulting_status\":{}}},\"dispatch\":{{\"dispatch_id\":{},\"confirmed_missions\":{},\"process_result_count\":{}}},\"genesis\":{{\"event_count\":{}}},\"vsp\":{{\"checkpoint_debug\":{}}}}}",
        now_ms,
        vertex_live_quote(&record.session_id),
        vertex_live_quote(&format!("{:?}", record.resulting_status)),
        record.sequence,
        record.sequence,
        vertex_live_quote(&record.wave_id),
        vertex_live_string_array(&record.mission_ids),
        vertex_live_quote(&format!("{:?}", record.resulting_status)),
        vertex_live_quote(&record.dispatch_id),
        vertex_live_string_array(&record.mission_ids),
        record.process_results.len(),
        record.emitted_event_count,
        vertex_live_quote(&format!("{:#?}", checkpoint))
    );

    vertex_live_publish_json(&json);
}
// END VERTEX LIVE SESSION BUS V1
"@

  $patched=$loopText.Insert($stepOpen,"`n    vertex_live_publish_preflight(&session);")
  # Recompute record location after first insertion.
  $recordMatch2=[regex]::Match($patched,'let\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*AutonomousWaveRecord\s*\{')
  if(-not $recordMatch2.Success){throw 'Record constructor disappeared after preflight injection.'}
  $recordOpen2=$patched.IndexOf('{',$recordMatch2.Index)
  $recordClose2=FindMatchingBrace $patched $recordOpen2
  if($recordClose2 -lt 0){throw 'Record close not found after injection.'}
  $afterRecord2=$recordClose2+1
  while($afterRecord2 -lt $patched.Length -and [char]::IsWhiteSpace($patched[$afterRecord2])){$afterRecord2++}
  if($afterRecord2 -lt $patched.Length -and $patched[$afterRecord2] -eq ';'){$afterRecord2++}

  $postCall="`n    vertex_live_publish_postflight(&$recordVar, &$recordVar.checkpoint);"
  $patched=$patched.Insert($afterRecord2,$postCall)

  $stepMatchPatched=[regex]::Match($patched,'pub\s+fn\s+run_autonomous_mission_step\b[\s\S]*?\{')
  if(-not $stepMatchPatched.Success){throw 'Patched run_autonomous_mission_step not found.'}

  $stepModulePatched=FindEnclosingModule $patched $stepMatchPatched.Index
  if($null -eq $stepModulePatched){throw 'Patched enclosing module not found.'}

  if($stepModulePatched.Name -ne $stepModule.Name){
    throw "Enclosing module changed unexpectedly: $($stepModule.Name) -> $($stepModulePatched.Name)"
  }

  $helperInsertion="`n$helpers`n"
  $patched=$patched.Insert($stepModulePatched.Close,$helperInsertion)

  Write-Host ("Live helpers scope     : module " + $stepModulePatched.Name) -ForegroundColor Green
  WriteUtf8 $loopFile $patched

  Write-Host "Live observer patched: $loopFile" -ForegroundColor Green

  Write-Host "`n[4/10] INSTALL TAURI LIVE IPC COMMANDS" -ForegroundColor Yellow

  $t=[IO.File]::ReadAllText($tauriLib)
  if($t.Contains('vertex_live_session_latest')){throw 'Tauri live IPC command already present.'}

  $rootCandidates=@()
  $rootMatches=[regex]::Matches(
    $t,
    'fn\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*->\s*Result\s*<\s*(?:std::path::)?PathBuf\s*,\s*String\s*>\s*\{'
  )

  foreach($m in $rootMatches){
    $open=$t.IndexOf('{',$m.Index)
    if($open -lt 0){continue}

    $close=FindMatchingBrace $t $open
    if($close -lt 0){continue}

    $body=$t.Substring($open+1,$close-$open-1)

    if(
      $body.Contains('ProgramSource') -and
      $body.Contains('Cargo.toml')
    ){
      $rootCandidates+=@(
        [pscustomobject]@{
          Name=$m.Groups['name'].Value
          Body=$body
        }
      )
    }
  }

  if($rootCandidates.Count -ne 1){
    $names=($rootCandidates|ForEach-Object{$_.Name}) -join ', '
    throw "Expected exactly one Tauri ProgramSource resolver; found $($rootCandidates.Count): $names"
  }

  $tauriRootFn=$rootCandidates[0].Name
  Write-Host ("Tauri ProgramSource resolver: " + $tauriRootFn + "()") -ForegroundColor Green

  $tauriBlock=@'

// VERTEX LIVE SESSION IPC V1
fn vertex_runtime_directory() -> Result<std::path::PathBuf, String> {
    Ok(__VERTEX_PROGRAMSOURCE_ROOT_FN__()?.join("_vertex_runtime"))
}

#[tauri::command]
fn vertex_live_session_latest() -> Result<String, String> {
    let path = vertex_runtime_directory()?.join("live_session_latest.json");

    if !path.is_file() {
        return Ok(String::new());
    }

    std::fs::read_to_string(&path)
        .map_err(|error| format!("cannot read live session latest: {error}"))
}

#[tauri::command]
fn vertex_live_session_tail(limit: Option<usize>) -> Result<Vec<String>, String> {
    let path = vertex_runtime_directory()?.join("live_session.ndjson");

    if !path.is_file() {
        return Ok(Vec::new());
    }

    let content = std::fs::read_to_string(&path)
        .map_err(|error| format!("cannot read live session timeline: {error}"))?;

    let limit = limit.unwrap_or(40).clamp(1, 500);
    let lines = content.lines().collect::<Vec<_>>();
    let start = lines.len().saturating_sub(limit);

    Ok(lines[start..].iter().map(|line| (*line).to_owned()).collect())
}
// END VERTEX LIVE SESSION IPC V1

'@

  $tauriBlock=$tauriBlock.Replace(
    '__VERTEX_PROGRAMSOURCE_ROOT_FN__',
    $tauriRootFn
  )

  if($tauriBlock.Contains('__VERTEX_PROGRAMSOURCE_ROOT_FN__')){
    throw 'Tauri ProgramSource resolver placeholder was not replaced.'
  }

  $handler='tauri::generate_handler!['
  $handlerPos=$t.IndexOf($handler)
  if($handlerPos -lt 0){throw 'Tauri generate_handler anchor missing.'}
  $insertPos=$t.IndexOf("pub fn run()",[StringComparison]::Ordinal)
  if($insertPos -lt 0){throw 'Tauri run() anchor missing.'}
  $t=$t.Insert($insertPos,$tauriBlock)

  $handlerPos2=$t.IndexOf($handler)
  $listStart=$handlerPos2+$handler.Length
  $t=$t.Insert($listStart,"`n            vertex_live_session_latest,`n            vertex_live_session_tail,")

  WriteUtf8 $tauriLib $t
  Write-Host 'Tauri live IPC commands: INSTALLED' -ForegroundColor Green

  Write-Host "`n[5/10] EXTEND FRONTEND TRANSPORT" -ForegroundColor Yellow

  $tr=[IO.File]::ReadAllText($transport)
  if($tr.Contains('liveSessionLatest')){throw 'Frontend live transport already present.'}
  $tr += @'

export interface LiveSessionSnapshot {
  schema: string
  kind: 'wave_scheduled' | 'wave_completed' | string
  timestamp_ms: number
  session?: {
    session_id?: string
    status?: string
    completed_waves?: number
  }
  wave?: {
    sequence?: number
    wave_id?: string
    ready?: string[]
    blocked?: string[]
    waiting?: string[]
    missions?: string[]
    resulting_status?: string
  }
  dispatch?: {
    dispatch_id?: string
    mission_set?: string[]
    executions?: Array<{
      execution_id?: string
    }>
    confirmed_missions?: string[]
    process_result_count?: number
  }
  genesis?: {
    event_count?: number
    events_debug?: string
  }
  vsp?: {
    checkpoint_debug?: string
  } | null
}

export async function liveSessionLatest(): Promise<LiveSessionSnapshot | null> {
  const raw = await call<string>('vertex_live_session_latest')
  if (!raw.trim()) return null
  return JSON.parse(raw) as LiveSessionSnapshot
}

export async function liveSessionTail(limit = 40): Promise<LiveSessionSnapshot[]> {
  const lines = await call<string[]>('vertex_live_session_tail', { limit })
  const snapshots: LiveSessionSnapshot[] = []
  for (const line of lines) {
    try {
      snapshots.push(JSON.parse(line) as LiveSessionSnapshot)
    } catch {
      // Fail closed at the display boundary: malformed telemetry is ignored,
      // never converted into controller state.
    }
  }
  return snapshots
}
'@
  WriteUtf8 $transport $tr
  Write-Host 'Frontend live transport: INSTALLED' -ForegroundColor Green

  Write-Host "`n[6/10] BUILD LIVE FLIGHT PANEL" -ForegroundColor Yellow

  $panelText=@'
<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import {
  desktop,
  liveSessionLatest,
  liveSessionTail,
  type LiveSessionSnapshot,
} from './transport'

const latest = ref<LiveSessionSnapshot | null>(null)
const timeline = ref<LiveSessionSnapshot[]>([])
const expanded = ref(false)
const error = ref('')
let timer: number | undefined
let working = false

const online = computed(() => desktop())
const executions = computed(() => {
  if (latest.value?.dispatch?.executions?.length) {
    return latest.value.dispatch.executions
  }

  const dispatchId = latest.value?.dispatch?.dispatch_id
  const previous = [...timeline.value]
    .reverse()
    .find((item) =>
      item.dispatch?.dispatch_id === dispatchId
      && item.dispatch?.executions?.length,
    )

  return previous?.dispatch?.executions ?? []
})

const scheduledMissions = computed(() => {
  if (latest.value?.dispatch?.mission_set?.length) {
    return latest.value.dispatch.mission_set
  }

  if (latest.value?.wave?.ready?.length) {
    return latest.value.wave.ready
  }

  if (latest.value?.dispatch?.confirmed_missions?.length) {
    return latest.value.dispatch.confirmed_missions
  }

  return latest.value?.wave?.missions ?? []
})

const processResultCount = computed(
  () => latest.value?.dispatch?.process_result_count ?? 0,
)

function compact(value: string | undefined, max = 34) {
  if (!value) return '-'
  if (value.length <= max) return value
  return `${value.slice(0, max - 3)}...`
}

async function refresh() {
  if (!online.value || working) return
  working = true
  try {
    const [next, history] = await Promise.all([
      liveSessionLatest(),
      liveSessionTail(24),
    ])
    latest.value = next
    timeline.value = history
    error.value = ''
  } catch (reason) {
    error.value = String(reason)
  } finally {
    working = false
  }
}

onMounted(() => {
  void refresh()
  timer = window.setInterval(() => void refresh(), 350)
})

onUnmounted(() => {
  if (timer !== undefined) window.clearInterval(timer)
})
</script>

<template>
  <section class="flight" :class="{ expanded }">
    <button class="toggle" @click="expanded = !expanded">
      <span class="pulse" :class="{ on: Boolean(latest) }"></span>
      LIVE FLIGHT
    </button>

    <div class="cell">
      <small>SESSION</small>
      <strong>{{ compact(latest?.session?.session_id) }}</strong>
    </div>

    <div class="cell">
      <small>STATUS</small>
      <strong>{{ latest?.session?.status || '-' }}</strong>
    </div>

    <div class="cell">
      <small>WAVE</small>
      <strong>{{ compact(latest?.wave?.wave_id) }}</strong>
    </div>

    <div class="cell">
      <small>DISPATCH</small>
      <strong>{{ compact(latest?.dispatch?.dispatch_id) }}</strong>
    </div>

    <div class="cell">
      <small>EXECUTION IDs</small>
      <strong>{{ executions.length }}</strong>
    </div>

    <div class="cell">
      <small>GENESIS</small>
      <strong>{{ latest?.genesis?.event_count ?? 0 }}</strong>
    </div>

    <div class="cell">
      <small>VSP</small>
      <strong>{{ latest?.vsp ? 'BOUND' : '-' }}</strong>
    </div>

    <div class="cell">
      <small>EVENT</small>
      <strong>{{ latest?.kind || 'WAITING' }}</strong>
    </div>

    <span v-if="error" class="error">{{ error }}</span>

    <div v-if="expanded" class="detail">
      <section>
        <h4>Scheduled Missions</h4>
        <article
          v-for="mission in scheduledMissions"
          :key="mission"
        >
          <strong>{{ mission }}</strong>
          <span>SCHEDULED</span>
          <small>
            Wave mission set. No inferred Mission-to-Execution mapping.
          </small>
        </article>

        <h4>Execution IDs</h4>
        <article
          v-for="(execution, index) in executions"
          :key="index"
        >
          <strong>{{ execution.execution_id || '-' }}</strong>
          <span>DISPATCHED</span>
          <small>
            Agent/Mission ownership is not inferred from this thin dispatch contract.
          </small>
        </article>

        <article v-if="processResultCount > 0">
          <strong>Completed process results</strong>
          <span>{{ processResultCount }}</span>
          <small>
            Confirmed completed mission evidence is shown in the Mission set.
          </small>
        </article>
      </section>

      <section>
        <h4>Genesis</h4>
        <pre>Genesis event count: {{ latest?.genesis?.event_count ?? 0 }}</pre>
      </section>

      <section>
        <h4>VSP Checkpoint</h4>
        <pre>{{ latest?.vsp?.checkpoint_debug || 'No completed-wave checkpoint yet.' }}</pre>
      </section>

      <section class="timeline">
        <h4>Live Timeline</h4>
        <article
          v-for="(item, index) in [...timeline].reverse()"
          :key="`${item.timestamp_ms}:${index}`"
        >
          <strong>{{ item.kind }}</strong>
          <span>{{ item.session?.status || '-' }}</span>
          <small>
            {{ compact(item.wave?.wave_id, 22) }}
            / {{ compact(item.dispatch?.dispatch_id, 22) }}
          </small>
        </article>
      </section>
    </div>
  </section>
</template>

<style scoped>
.flight {
  display: grid;
  grid-template-columns: 96px repeat(8, minmax(80px, 1fr));
  min-height: 46px;
  border-bottom: 1px solid #283346;
  background: #0d131d;
  color: #e9eef8;
  font-family: Inter, ui-sans-serif, system-ui, sans-serif;
}
.toggle {
  border: 0;
  border-right: 1px solid #283346;
  background: #121b28;
  color: #dfe8f7;
  font-size: 10px;
  font-weight: 800;
  cursor: pointer;
}
.pulse {
  display: inline-block;
  width: 7px;
  height: 7px;
  margin-right: 5px;
  border-radius: 50%;
  background: #707c90;
}
.pulse.on {
  background: #42d99f;
  box-shadow: 0 0 9px rgba(66, 217, 159, .8);
}
.cell {
  min-width: 0;
  padding: 7px 8px;
  border-right: 1px solid #202a3b;
}
.cell small,
.cell strong {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cell small {
  color: #7f8ca2;
  font-size: 8px;
  letter-spacing: .08em;
}
.cell strong {
  margin-top: 3px;
  font: 10px ui-monospace, SFMono-Regular, Consolas, monospace;
}
.error {
  grid-column: 1 / -1;
  padding: 5px 8px;
  color: #ff8a98;
  font: 10px Consolas, monospace;
}
.detail {
  grid-column: 1 / -1;
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  max-height: 270px;
  overflow: auto;
  border-top: 1px solid #283346;
  background: #090d14;
}
.detail > section {
  min-width: 0;
  padding: 8px;
  border-right: 1px solid #202a3b;
}
.detail h4 {
  margin: 0 0 7px;
  color: #9eacc2;
  font-size: 10px;
}
.detail article {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 3px 8px;
  margin-bottom: 5px;
  padding: 5px;
  border: 1px solid #263147;
  border-radius: 5px;
  background: #0e1520;
  font: 9px Consolas, monospace;
}
.detail article small {
  grid-column: 1 / -1;
  color: #8491a6;
}
.detail pre {
  max-height: 190px;
  margin: 0;
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-word;
  color: #b8c5d8;
  font: 9px/1.4 Consolas, monospace;
}
@media (max-width: 1280px) {
  .flight {
    grid-template-columns: 90px repeat(4, 1fr);
  }
  .cell:nth-of-type(n+6) {
    display: none;
  }
  .detail {
    grid-template-columns: 1fr 1fr;
  }
}
</style>
'@
  WriteUtf8 $panel $panelText

  $ed=[IO.File]::ReadAllText($editor)
  if($ed.Contains('VertexLiveFlightPanel')){throw 'Editor already imports Live Flight Panel.'}

  $scriptTag=[regex]::Match($ed,'<script setup[^>]*>')
  if(-not $scriptTag.Success){throw 'Editor script setup tag missing.'}
  $ed=$ed.Insert($scriptTag.Index+$scriptTag.Length,"`nimport VertexLiveFlightPanel from './VertexLiveFlightPanel.vue'")

  $headerClose=$ed.IndexOf('</header>')
  if($headerClose -lt 0){throw 'Editor header close anchor missing.'}
  $headerClose += '</header>'.Length
  $ed=$ed.Insert($headerClose,"`n<VertexLiveFlightPanel />")

  WriteUtf8 $editor $ed
  Write-Host 'Live Flight Panel: DOCKED' -ForegroundColor Green

  Write-Host "`n[7/10] RUSTFMT / TARGETED COMPILE" -ForegroundColor Yellow

  RunChecked '[live-bus] rustfmt Mothership loop' {& $rustfmt.Source --edition 2024 $loopFile}
  RunChecked '[live-ipc] rustfmt Tauri bridge' {& $rustfmt.Source --edition 2024 $tauriLib}

  RunChecked '[live-bus] Mothership cargo check' {& $cargo.Source check --manifest-path $mothershipCargo --all-targets}
  RunChecked '[live-ipc] Tauri cargo check' {& $cargo.Source check --manifest-path $tauriCargo --all-targets}

  Write-Host "`n[8/10] REAL EMISSION SMOKE TEST" -ForegroundColor Yellow

  RunChecked '[live-bus] autonomous real voyage targeted test' {
    & $cargo.Source test --manifest-path $mothershipCargo --test autonomous_real_voyage autonomous_real_voyage_build_test_vve_completed -- --exact
  }

  $latest=Join-Path $runtimeDir 'live_session_latest.json'
  if(-not(Test-Path -LiteralPath $latest)){throw "Live latest file not emitted: $latest"}
  if(-not(Test-Path -LiteralPath $timeline)){throw "Live timeline file not emitted: $timeline"}

  $latestText=[IO.File]::ReadAllText($latest)
  foreach($needle in @(
    '"schema":"vertex.mothership.live-session.v1"',
    '"session":',
    '"wave":',
    '"dispatch":',
    '"genesis":',
    '"vsp":'
  )){
    if(-not $latestText.Contains($needle)){throw "Live telemetry missing field: $needle"}
  }

  $runtimeAfter=@(Get-Content -LiteralPath $timeline -ErrorAction Stop).Count
  if($runtimeAfter -le $runtimeBefore){throw "Targeted voyage did not append live timeline. Before=$runtimeBefore After=$runtimeAfter"}

  Write-Host "Live timeline appended: $runtimeBefore -> $runtimeAfter" -ForegroundColor Green
  Write-Host 'Real Mothership state emission: VERIFIED' -ForegroundColor Green

  Write-Host "`n[9/10] FRONTEND / WORKSPACE RELEASE GATE" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[editor] frontend build with Live Flight Panel' {& $pnpm.Source build}
  }finally{Pop-Location}

  RunChecked '[release] cargo check --workspace --all-targets' {& $cargo.Source check --manifest-path $coreCargo --workspace --all-targets}
  RunChecked '[release] cargo test --workspace' {& $cargo.Source test --manifest-path $coreCargo --workspace}

  Write-Host "`n[10/10] REPORT" -ForegroundColor Yellow

  [ordered]@{
    schema='vertex.cic.live-session-bus-editor-flight-panel.v11'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    source_of_truth='FleetControllerSession'
    current_ui=$ui
    current_core=$core
    legacy='UNTOUCHED'
    contracts=@{
      session=$sessionDef.Path
      wave=$waveDef.Path
      dispatch=$dispatchDef.Path
      assignment=$assignmentDef.Path
      autonomous_record=$recordDef.Path
      autonomous_loop=$loopFile
      autonomous_step_module=$stepModule.Name
      dispatch_assignment_field=$assignmentField
      tauri_programsource_resolver=$tauriRootFn
    }
    live_bus=@{
      schema='vertex.mothership.live-session.v1'
      latest=$latest
      timeline=$timeline
      poll_ms=350
      real_emission='VERIFIED'
      timeline_before=$runtimeBefore
      timeline_after=$runtimeAfter
    }
    surfaces=@{
      session='LIVE'
      wave='LIVE'
      dispatch='LIVE'
      execution='LIVE_EXECUTION_ID_ONLY_NO_INFERRED_OWNERSHIP'
      mission_mapping='WAVE_MISSION_SET_AND_COMPLETED_RECORD_EVIDENCE'
      genesis='LIVE_EVENT_COUNT_AND_DEBUG'
      vsp='LIVE_CHECKPOINT_DEBUG'
      tauri_ipc='LIVE'
      editor_flight_panel='ONLINE'
    }
    safety=@{
      duplicate_controller_state='NOT_CREATED'
      mothership_control_semantics='UNCHANGED'
      arbitrary_shell='UNCHANGED_DENIED'
      legacy='UNTOUCHED'
    }
    validation=@{
      mothership_check='GREEN'
      tauri_check='GREEN'
      real_voyage_smoke='GREEN'
      frontend_build='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
    }
    backup=$backup
  }|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX — LIVE SESSION BUS V11 GREEN
============================================================
 FleetControllerSession Source of Truth     LOCKED
 Session                                 LIVE
 Wave                                    LIVE
 Dispatch                                LIVE
 Mission Set                             LIVE
 Execution IDs                           LIVE
 Agent Ownership                          NOT_INFERRED
 Mission Mapping                          RECORD_EVIDENCE_ONLY
 Genesis                                 LIVE
 VSP Checkpoint                          LIVE
 Live Observer Module Scope              LOCKED
 Tauri ProgramSource Resolver            DISCOVERED
 Mothership -> Runtime Bus               VERIFIED
 Runtime Bus -> Tauri IPC                ONLINE
 Tauri IPC -> Editor Flight Panel        ONLINE
 Poll Interval                           350 ms
 Real Autonomous Voyage Emission         VERIFIED
 Mothership Check                        GREEN
 Tauri Check                             GREEN
 Frontend Build                          GREEN
 Workspace Release Gate                  GREEN
 LEGACY                                  UNTOUCHED
------------------------------------------------------------
 REPORT: $report
 LIVE:   $latest
 LOG:    $timeline
============================================================
 LIVE FLIGHT TELEMETRY: DOCKED
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' LIVE SESSION BUS V11 RED — DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null
  foreach($p in @($loopFile,$tauriLib,$transport,$editor,$panel)){
    if($p -and(Test-Path -LiteralPath $p)){
      $dest=Join-Path $failed ([IO.Path]::GetFileName($p))
      Copy-Item -LiteralPath $p -Destination $dest -Force -ErrorAction SilentlyContinue
    }
  }

  foreach($p in @($loopFile,$tauriLib,$transport,$editor)){
    if($p){RestoreBackupFile $p}
  }
  if(Test-Path -LiteralPath $panel){Remove-Item -LiteralPath $panel -Force -ErrorAction SilentlyContinue}

  Write-Host 'Core/UI source rollback: COMPLETE' -ForegroundColor Yellow
  Write-Host 'Runtime telemetry files are evidence and are NOT used as controller state.' -ForegroundColor DarkYellow
  Write-Host "Failure evidence: $failed" -ForegroundColor Yellow
  throw
}
}