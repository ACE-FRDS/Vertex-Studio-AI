$VertexScriptPath = $PSCommandPath
& {
$ErrorActionPreference='Stop'

# ============================================================
# VERTEX - ADAPTIVE GRID EQUIPMENT WORKSPACE V7R11
#
# Requires VSA MAX IMPLEMENTATION V6.
#
# Mission:
# - Full desktop = Adaptive Grid Workspace
# - Every visible capability = Equipment Unit
# - Grid move / resize / snap / persistence
# - Editor = PRIMARY equipment, default center, NEVER float
# - Micro Drone compatibility contract
# - RPG excluded
# ============================================================

$startup='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package'
$base=Join-Path $startup 'VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'

$cockpit=Join-Path $ui 'src\vertex-cockpit'
$workspaceDir=Join-Path $cockpit 'workspace'
$rolePanels=Join-Path $cockpit 'role-layout\panels'
$equipmentDir=Join-Path $cockpit 'equipment'

$shell=Join-Path $cockpit 'VertexCockpitShell.vue'
$editor=Join-Path $ui 'src\vertex-editor\VertexEditorDock.vue'
$mainEditor=Join-Path $workspaceDir 'VertexMainEditor.vue'
$servicesDir=Join-Path $ui 'src\services'
$developerShim=Join-Path $servicesDir 'developer.ts'
$editorShim=Join-Path $servicesDir 'vertex-editor.ts'
$tauriSrc=Join-Path $ui 'src-tauri\src'


$coreCargo=Join-Path $core 'Cargo.toml'
$tauriCargo=Join-Path $ui 'src-tauri\Cargo.toml'
$tauriTarget=Join-Path $startup '_build\VSA_TAURI_GRID_V7_CHECK'

$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VSA_ADAPTIVE_GRID_V7R11_BACKUP.$stamp"
$failed=Join-Path $reports "VSA_ADAPTIVE_GRID_V7R11_FAILED.$stamp"
$report=Join-Path $reports "VSA_ADAPTIVE_GRID_V7R11.$stamp.json"

$utf8=New-Object System.Text.UTF8Encoding($false)

function WriteUtf8([string]$Path,[string]$Content){
  $parent=Split-Path -Parent $Path
  if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,$Content,$utf8)
}

function Get-RelativePathCompat(
  [string]$BaseDirectory,
  [string]$TargetPath
){
  $baseFull=[IO.Path]::GetFullPath($BaseDirectory)
  $targetFull=[IO.Path]::GetFullPath($TargetPath)

  $separator=[IO.Path]::DirectorySeparatorChar.ToString()

  if(-not $baseFull.EndsWith($separator)){
    $baseFull += $separator
  }

  $baseUri=New-Object System.Uri($baseFull)
  $targetUri=New-Object System.Uri($targetFull)

  $relativeUri=$baseUri.MakeRelativeUri($targetUri)
  $relative=[Uri]::UnescapeDataString($relativeUri.ToString())

  return $relative.Replace('/',$separator)
}

function RequireCommand([string]$Name){
  $cmd=Get-Command $Name -ErrorAction SilentlyContinue
  if(-not $cmd){throw "Missing command: $Name"}
  return $cmd
}

function RunChecked([string]$Label,[scriptblock]$Action){
  Write-Host "`n$Label" -ForegroundColor Cyan
  & $Action
  if($LASTEXITCODE -ne 0){throw "$Label RED ($LASTEXITCODE)"}
}

# PowerShell automatic/reserved variable safety guard.
# `$Host` is read-only in Windows PowerShell 5.1, so generated scripts must
# never assign to an exact variable named `$host` / `$Host`.
$selfPath=$VertexScriptPath

if([string]::IsNullOrWhiteSpace($selfPath)){
  $selfPath=$PSCommandPath
}

if(
  [string]::IsNullOrWhiteSpace($selfPath) -or
  -not(Test-Path -LiteralPath $selfPath)
){
  throw 'Self-path audit RED: script path could not be resolved.'
}

$selfText=[IO.File]::ReadAllText($selfPath)

if(
  $selfText -match '(?im)^\s*\$host\s*='
){
  throw 'Reserved variable audit RED: assignment to PowerShell $Host detected.'
}

Write-Host ("Self path audit                  : GREEN -> {0}" -f $selfPath) -ForegroundColor Green
Write-Host 'Reserved variable audit          : GREEN' -ForegroundColor Green

Write-Host @'
============================================================
 VERTEX - ADAPTIVE GRID EQUIPMENT WORKSPACE V7R11
 FULL DESKTOP GRID / EQUIPMENT UNIT / DRONE READY
 PS5.1 COMPAT / CONDITIONAL SAFE
============================================================
'@ -ForegroundColor Magenta


function EnsureBootstrapBase {
  Write-Host "`n[BOOTSTRAP] FULL FRONTEND / TAURI TOPOLOGY DISCOVERY" -ForegroundColor Yellow

  foreach($requiredBase in @(
    $cockpit,$shell,$editor,$tauriCargo,$coreCargo,$tauriSrc
  )){
    if(-not(Test-Path -LiteralPath $requiredBase)){
      throw "Bootstrap base artifact missing: $requiredBase"
    }
  }

  New-Item -ItemType Directory -Path $workspaceDir -Force|Out-Null
  New-Item -ItemType Directory -Path $rolePanels -Force|Out-Null
  New-Item -ItemType Directory -Path $servicesDir -Force|Out-Null

  # ==========================================================
  # DISCOVER EDITOR FRONTEND API / TAURI IPC
  # ==========================================================
  Write-Host "  Editor API                     : TOPOLOGY DISCOVERY" -ForegroundColor Cyan

  $editorCandidates=@(
    Get-ChildItem -LiteralPath (Join-Path $ui 'src') -Recurse -File -Include '*.ts','*.tsx','*.vue' |
    Where-Object {
      $_.FullName -ne $editorShim -and (
        ([IO.File]::ReadAllText($_.FullName)).Contains('editorProjectTree') -or
        ([IO.File]::ReadAllText($_.FullName)).Contains('editorReadFile') -or
        ([IO.File]::ReadAllText($_.FullName)).Contains('editorWriteFile') -or
        ([IO.File]::ReadAllText($_.FullName)).Contains('vertex_project_tree') -or
        ([IO.File]::ReadAllText($_.FullName)).Contains('vertex_read_file') -or
        ([IO.File]::ReadAllText($_.FullName)).Contains('editor_run_action')
      )
    }
  )

  if(-not(Test-Path -LiteralPath $editorShim)){
    $editorSource=$editorCandidates |
      Where-Object {$_.Extension -in '.ts','.tsx'} |
      Select-Object -First 1

    if($editorSource){
      $shimDir=Split-Path -Parent $editorShim
      $relative=(Get-RelativePathCompat $shimDir $editorSource.FullName).Replace('\','/')
      if(-not $relative.StartsWith('.')){$relative="./$relative"}
      $relative=$relative -replace '\.(ts|tsx)$',''

      $editorSourceText=[IO.File]::ReadAllText($editorSource.FullName)

      $exportNames=@(
        [regex]::Matches(
          $editorSourceText,
          '(?m)^\s*export\s+(?:async\s+)?(?:function|const|let|class)\s+([A-Za-z_$][A-Za-z0-9_$]*)'
        ) |
        ForEach-Object {$_.Groups[1].Value}
      )

      $editorExportReport=Join-Path $reports "EDITOR_FRONTEND_EXPORTS.$stamp.json"

      [ordered]@{
        schema='vertex.discovery.editor-exports.v1'
        timestamp=(Get-Date).ToString('o')
        source=$editorSource.FullName
        exports=@($exportNames)
      } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $editorExportReport -Encoding UTF8

      $editorAdapter=@'
import * as actual from '__VERTEX_TRANSPORT_IMPORT__'

export interface EditorRuntimeInfo {
  workspace_name: string
  workspace_root: string
  mothership_detected: boolean
  hyper_agent_runtime_detected: boolean
  git_enabled: boolean
  branch?: string
}

export interface EditorFileSnapshot {
  path: string
  content: string
  language: string
}

export interface EditorCommandResult {
  id: string
  executable: string
  args: string[]
  status: string
  stdout: string
  stderr: string
}

type AnyFunction = (...args: any[]) => any

const api = actual as unknown as Record<string, unknown>

function normalized(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '')
}

function functions(): Array<[string, AnyFunction]> {
  return Object.entries(api)
    .filter((entry): entry is [string, AnyFunction] => typeof entry[1] === 'function')
}

function pick(
  exact: string[],
  tokenGroups: string[][],
): AnyFunction | null {
  for (const name of exact) {
    const value = api[name]
    if (typeof value === 'function') return value as AnyFunction
  }

  const available = functions()

  for (const tokens of tokenGroups) {
    const hit = available.find(([name]) => {
      const value = normalized(name)
      return tokens.every((token) => value.includes(normalized(token)))
    })
    if (hit) return hit[1]
  }

  return null
}

async function invokeAdaptive(
  fn: AnyFunction,
  positional: unknown[],
  named: Record<string, unknown>,
): Promise<unknown> {
  if (fn.length === 0) return await fn()
  if (fn.length === 1) return await fn(named)
  return await fn(...positional)
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function textValue(
  object: Record<string, unknown> | null,
  keys: string[],
  fallback = '',
): string {
  if (!object) return fallback

  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'string') return value
  }

  return fallback
}

function boolValue(
  object: Record<string, unknown> | null,
  keys: string[],
  fallback = false,
): boolean {
  if (!object) return fallback

  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'boolean') return value
  }

  return fallback
}

export async function editorProjectTree(
  workspaceId: string,
  depth = 7,
): Promise<string> {
  const fn = pick(
    [
      'editorProjectTree',
      'projectTree',
      'getProjectTree',
      'fetchProjectTree',
      'vertexProjectTree',
    ],
    [
      ['project', 'tree'],
      ['workspace', 'tree'],
      ['tree'],
    ],
  )

  if (!fn) return ''

  const result = await invokeAdaptive(
    fn,
    [workspaceId, depth],
    {
      workspaceId,
      workspace_id: workspaceId,
      depth,
      maxDepth: depth,
      max_depth: depth,
    },
  )

  if (typeof result === 'string') return result

  const object = objectValue(result)
  const nested = textValue(
    object,
    ['tree', 'text', 'output', 'value'],
  )

  return nested || JSON.stringify(result, null, 2)
}

export async function editorRuntimeInfo(
  workspaceId: string,
): Promise<EditorRuntimeInfo> {
  const fn = pick(
    [
      'editorRuntimeInfo',
      'runtimeInfo',
      'getRuntimeInfo',
      'workspaceRuntimeInfo',
    ],
    [
      ['runtime', 'info'],
      ['workspace', 'info'],
    ],
  )

  if (!fn) {
    return {
      workspace_name: 'UNBOUND',
      workspace_root: '',
      mothership_detected: false,
      hyper_agent_runtime_detected: false,
      git_enabled: false,
    }
  }

  const result = await invokeAdaptive(
    fn,
    [workspaceId],
    {
      workspaceId,
      workspace_id: workspaceId,
    },
  )

  const object = objectValue(result)

  return {
    workspace_name: textValue(
      object,
      ['workspace_name', 'workspaceName', 'name'],
      'Workspace',
    ),
    workspace_root: textValue(
      object,
      ['workspace_root', 'workspaceRoot', 'root', 'path'],
    ),
    mothership_detected: boolValue(
      object,
      ['mothership_detected', 'mothershipDetected'],
    ),
    hyper_agent_runtime_detected: boolValue(
      object,
      ['hyper_agent_runtime_detected', 'hyperAgentRuntimeDetected'],
    ),
    git_enabled: boolValue(
      object,
      ['git_enabled', 'gitEnabled'],
    ),
    branch: textValue(
      object,
      ['branch', 'git_branch', 'gitBranch'],
    ) || undefined,
  }
}

export async function editorSearchFiles(
  workspaceId: string,
  query: string,
): Promise<string> {
  const fn = pick(
    [
      'editorSearchFiles',
      'searchFiles',
      'findFiles',
      'workspaceSearch',
    ],
    [
      ['search', 'file'],
      ['find', 'file'],
      ['workspace', 'search'],
    ],
  )

  if (!fn) return ''

  const result = await invokeAdaptive(
    fn,
    [workspaceId, query],
    {
      workspaceId,
      workspace_id: workspaceId,
      query,
      pattern: query,
    },
  )

  if (typeof result === 'string') return result
  if (Array.isArray(result)) return result.map((item) => String(item)).join('\n')

  const object = objectValue(result)
  const nested = object?.results ?? object?.files ?? object?.items

  if (Array.isArray(nested)) {
    return nested.map((item) => String(item)).join('\n')
  }

  return ''
}

export async function editorReadFile(
  workspaceId: string,
  path: string,
): Promise<EditorFileSnapshot> {
  const fn = pick(
    [
      'editorReadFile',
      'readFile',
      'readWorkspaceFile',
      'workspaceReadFile',
      'getFile',
    ],
    [
      ['read', 'file'],
      ['file', 'read'],
    ],
  )

  if (!fn) {
    throw new Error(
      'Editor read transport is UNBOUND. ' +
      'No compatible export was discovered in transport.ts.'
    )
  }

  const result = await invokeAdaptive(
    fn,
    [workspaceId, path],
    {
      workspaceId,
      workspace_id: workspaceId,
      path,
      relativePath: path,
      relative_path: path,
    },
  )

  if (typeof result === 'string') {
    return {
      path,
      content: result,
      language: 'plaintext',
    }
  }

  const object = objectValue(result)

  return {
    path: textValue(
      object,
      ['path', 'relative_path', 'relativePath'],
      path,
    ),
    content: textValue(
      object,
      ['content', 'text', 'value'],
    ),
    language: textValue(
      object,
      ['language', 'language_id', 'languageId'],
      'plaintext',
    ),
  }
}

export async function editorWriteFile(
  workspaceId: string,
  path: string,
  content: string,
): Promise<void> {
  const fn = pick(
    [
      'editorWriteFile',
      'writeFile',
      'writeWorkspaceFile',
      'workspaceWriteFile',
      'saveFile',
    ],
    [
      ['write', 'file'],
      ['save', 'file'],
      ['file', 'write'],
    ],
  )

  if (!fn) {
    throw new Error(
      'Editor write transport is UNBOUND. ' +
      'No compatible export was discovered in transport.ts.'
    )
  }

  await invokeAdaptive(
    fn,
    [workspaceId, path, content],
    {
      workspaceId,
      workspace_id: workspaceId,
      path,
      relativePath: path,
      relative_path: path,
      content,
    },
  )
}

export async function editorRunAction(
  workspaceId: string,
  action: string,
): Promise<EditorCommandResult> {
  const fn = pick(
    [
      'editorRunAction',
      'runAction',
      'runEditorAction',
      'controlledAction',
    ],
    [
      ['run', 'action'],
      ['editor', 'action'],
      ['controlled', 'action'],
    ],
  )

  if (!fn) {
    throw new Error(
      'Editor action transport is UNBOUND. ' +
      'No compatible export was discovered in transport.ts.'
    )
  }

  const result = await invokeAdaptive(
    fn,
    [workspaceId, action],
    {
      workspaceId,
      workspace_id: workspaceId,
      action,
    },
  )

  const object = objectValue(result)

  return {
    id: textValue(
      object,
      ['id', 'command_id', 'commandId'],
      String(Date.now()),
    ),
    executable: textValue(
      object,
      ['executable', 'program', 'command'],
      action,
    ),
    args: Array.isArray(object?.args)
      ? object.args.map((item) => String(item))
      : [],
    status: textValue(
      object,
      ['status', 'state'],
      'UNKNOWN',
    ),
    stdout: textValue(
      object,
      ['stdout', 'output'],
    ),
    stderr: textValue(
      object,
      ['stderr', 'error'],
    ),
  }
}
'@
      $editorAdapter=$editorAdapter.Replace('__VERTEX_TRANSPORT_IMPORT__',$relative)

      WriteUtf8 $editorShim $editorAdapter
      Write-Host "    Found editor API : $($editorSource.FullName)" -ForegroundColor Green
      Write-Host "    Export count     : $($exportNames.Count)" -ForegroundColor Green
      Write-Host "    Contract adapter : $editorShim" -ForegroundColor Green
      Write-Host "    Export report    : $editorExportReport" -ForegroundColor Green
    }
    else {
      Write-Host "    Frontend editor service not found. Tauri commands: DISCOVER" -ForegroundColor Yellow

      $editorRustHits=@()

      foreach($file in Get-ChildItem -LiteralPath $tauriSrc -Recurse -File -Filter '*.rs'){
        $body=[IO.File]::ReadAllText($file.FullName)

        if(
          $body -match '(?i)project_tree' -or
          $body -match '(?i)read_file' -or
          $body -match '(?i)write_file' -or
          $body -match '(?i)editor_run_action' -or
          $body -match '(?i)search_files'
        ){
          $editorRustHits += [pscustomobject]@{
            Path=$file.FullName
            ProjectTree=($body -match '(?i)project_tree')
            ReadFile=($body -match '(?i)read_file')
            WriteFile=($body -match '(?i)write_file')
            RunAction=($body -match '(?i)editor_run_action|run_action')
            Search=($body -match '(?i)search_files')
          }
        }
      }

      $editorTopologyReport=Join-Path $reports "EDITOR_TOPOLOGY.$stamp.json"

      [ordered]@{
        schema='vertex.discovery.editor.v1'
        timestamp=(Get-Date).ToString('o')
        frontend_candidates=@($editorCandidates | ForEach-Object {$_.FullName})
        rust_candidates=@($editorRustHits)
        status=if($editorRustHits.Count){'RUST_CANDIDATE_FOUND'}else{'UNBOUND'}
      } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $editorTopologyReport -Encoding UTF8

      # Compile-safe UNBOUND service. Never invents success or Tauri command names.
      $editorFallback=@'
export interface EditorRuntimeInfo {
  workspace_name: string
  workspace_root: string
  mothership_detected: boolean
  hyper_agent_runtime_detected: boolean
  git_enabled: boolean
  branch?: string
}

export interface EditorFileSnapshot {
  path: string
  content: string
  language: string
}

export interface EditorCommandResult {
  id: string
  executable: string
  args: string[]
  status: string
  stdout: string
  stderr: string
}

function unbound(name: string): never {
  throw new Error(
    `Editor transport ${name} is UNBOUND. ` +
    'V7R8 refused to invent Tauri command names.'
  )
}

export async function editorProjectTree(
  _workspaceId: string,
  _depth = 7,
): Promise<string> {
  return ''
}

export async function editorRuntimeInfo(
  _workspaceId: string,
): Promise<EditorRuntimeInfo> {
  return {
    workspace_name: 'UNBOUND',
    workspace_root: '',
    mothership_detected: false,
    hyper_agent_runtime_detected: false,
    git_enabled: false,
  }
}

export async function editorSearchFiles(
  _workspaceId: string,
  _query: string,
): Promise<string> {
  return ''
}

export async function editorReadFile(
  _workspaceId: string,
  _path: string,
): Promise<EditorFileSnapshot> {
  return unbound('editorReadFile')
}

export async function editorWriteFile(
  _workspaceId: string,
  _path: string,
  _content: string,
): Promise<void> {
  return unbound('editorWriteFile')
}

export async function editorRunAction(
  _workspaceId: string,
  _action: string,
): Promise<EditorCommandResult> {
  return unbound('editorRunAction')
}
'@

      WriteUtf8 $editorShim $editorFallback
      Write-Host "    Editor transport   : UNBOUND shim created" -ForegroundColor Yellow
      Write-Host "    Discovery report  : $editorTopologyReport" -ForegroundColor Yellow
    }
  }
  else {
    $existingEditorShim=[IO.File]::ReadAllText($editorShim)

    $contractComplete=(
      $existingEditorShim.Contains('export async function editorProjectTree') -and
      $existingEditorShim.Contains('export async function editorRuntimeInfo') -and
      $existingEditorShim.Contains('export async function editorSearchFiles') -and
      $existingEditorShim.Contains('export async function editorReadFile') -and
      $existingEditorShim.Contains('export async function editorWriteFile') -and
      $existingEditorShim.Contains('export async function editorRunAction')
    )

    if($contractComplete){
      Write-Host "    vertex-editor.ts contract: PRESERVED" -ForegroundColor Green
    }
    else {
      Write-Host "    Existing editor shim is incomplete: REPAIR" -ForegroundColor Yellow

      $editorSource=$editorCandidates |
        Where-Object {$_.Extension -in '.ts','.tsx'} |
        Select-Object -First 1

      if(-not $editorSource){
        throw 'Existing vertex-editor.ts is incomplete and no transport source was rediscovered.'
      }

      $shimDir=Split-Path -Parent $editorShim
      $relative=(Get-RelativePathCompat $shimDir $editorSource.FullName).Replace('\','/')
      if(-not $relative.StartsWith('.')){$relative="./$relative"}
      $relative=$relative -replace '\.(ts|tsx)$',''

      $editorSourceText=[IO.File]::ReadAllText($editorSource.FullName)

      $exportNames=@(
        [regex]::Matches(
          $editorSourceText,
          '(?m)^\s*export\s+(?:async\s+)?(?:function|const|let|class)\s+([A-Za-z_$][A-Za-z0-9_$]*)'
        ) |
        ForEach-Object {$_.Groups[1].Value}
      )

      $repairAdapter=@'
import * as actual from '__VERTEX_TRANSPORT_IMPORT__'

export interface EditorRuntimeInfo {
  workspace_name: string
  workspace_root: string
  mothership_detected: boolean
  hyper_agent_runtime_detected: boolean
  git_enabled: boolean
  branch?: string
}

export interface EditorFileSnapshot {
  path: string
  content: string
  language: string
}

export interface EditorCommandResult {
  id: string
  executable: string
  args: string[]
  status: string
  stdout: string
  stderr: string
}

type AnyFunction = (...args: any[]) => any
const api = actual as unknown as Record<string, unknown>

function normalized(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '')
}

function functions(): Array<[string, AnyFunction]> {
  return Object.entries(api)
    .filter((entry): entry is [string, AnyFunction] => typeof entry[1] === 'function')
}

function pick(
  exact: string[],
  tokenGroups: string[][],
): AnyFunction | null {
  for (const name of exact) {
    const value = api[name]
    if (typeof value === 'function') return value as AnyFunction
  }

  const available = functions()

  for (const tokens of tokenGroups) {
    const hit = available.find(([name]) => {
      const value = normalized(name)
      return tokens.every((token) => value.includes(normalized(token)))
    })
    if (hit) return hit[1]
  }

  return null
}

async function invokeAdaptive(
  fn: AnyFunction,
  positional: unknown[],
  named: Record<string, unknown>,
): Promise<unknown> {
  if (fn.length === 0) return await fn()
  if (fn.length === 1) return await fn(named)
  return await fn(...positional)
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null
}

function textValue(
  object: Record<string, unknown> | null,
  keys: string[],
  fallback = '',
): string {
  if (!object) return fallback
  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'string') return value
  }
  return fallback
}

function boolValue(
  object: Record<string, unknown> | null,
  keys: string[],
  fallback = false,
): boolean {
  if (!object) return fallback
  for (const key of keys) {
    const value = object[key]
    if (typeof value === 'boolean') return value
  }
  return fallback
}

export async function editorProjectTree(
  workspaceId: string,
  depth = 7,
): Promise<string> {
  const fn = pick(
    ['editorProjectTree','projectTree','getProjectTree','fetchProjectTree','vertexProjectTree'],
    [['project','tree'],['workspace','tree'],['tree']],
  )
  if (!fn) return ''

  const result = await invokeAdaptive(
    fn,
    [workspaceId, depth],
    {
      workspaceId,
      workspace_id: workspaceId,
      depth,
      maxDepth: depth,
      max_depth: depth,
    },
  )

  if (typeof result === 'string') return result
  const object = objectValue(result)
  return textValue(object,['tree','text','output','value']) || JSON.stringify(result,null,2)
}

export async function editorRuntimeInfo(
  workspaceId: string,
): Promise<EditorRuntimeInfo> {
  const fn = pick(
    ['editorRuntimeInfo','runtimeInfo','getRuntimeInfo','workspaceRuntimeInfo'],
    [['runtime','info'],['workspace','info']],
  )

  if (!fn) {
    return {
      workspace_name: 'UNBOUND',
      workspace_root: '',
      mothership_detected: false,
      hyper_agent_runtime_detected: false,
      git_enabled: false,
    }
  }

  const result = await invokeAdaptive(
    fn,
    [workspaceId],
    { workspaceId, workspace_id: workspaceId },
  )

  const object = objectValue(result)

  return {
    workspace_name: textValue(object,['workspace_name','workspaceName','name'],'Workspace'),
    workspace_root: textValue(object,['workspace_root','workspaceRoot','root','path']),
    mothership_detected: boolValue(object,['mothership_detected','mothershipDetected']),
    hyper_agent_runtime_detected: boolValue(object,['hyper_agent_runtime_detected','hyperAgentRuntimeDetected']),
    git_enabled: boolValue(object,['git_enabled','gitEnabled']),
    branch: textValue(object,['branch','git_branch','gitBranch']) || undefined,
  }
}

export async function editorSearchFiles(
  workspaceId: string,
  query: string,
): Promise<string> {
  const fn = pick(
    ['editorSearchFiles','searchFiles','findFiles','workspaceSearch'],
    [['search','file'],['find','file'],['workspace','search']],
  )
  if (!fn) return ''

  const result = await invokeAdaptive(
    fn,
    [workspaceId,query],
    { workspaceId, workspace_id: workspaceId, query, pattern: query },
  )

  if (typeof result === 'string') return result
  if (Array.isArray(result)) return result.map((item) => String(item)).join('\n')

  const object=objectValue(result)
  const nested=object?.results ?? object?.files ?? object?.items
  return Array.isArray(nested)
    ? nested.map((item) => String(item)).join('\n')
    : ''
}

export async function editorReadFile(
  workspaceId: string,
  path: string,
): Promise<EditorFileSnapshot> {
  const fn = pick(
    ['editorReadFile','readFile','readWorkspaceFile','workspaceReadFile','getFile'],
    [['read','file'],['file','read']],
  )

  if (!fn) {
    throw new Error('Editor read transport is UNBOUND.')
  }

  const result = await invokeAdaptive(
    fn,
    [workspaceId,path],
    {
      workspaceId,
      workspace_id: workspaceId,
      path,
      relativePath: path,
      relative_path: path,
    },
  )

  if (typeof result === 'string') {
    return { path, content: result, language: 'plaintext' }
  }

  const object=objectValue(result)

  return {
    path: textValue(object,['path','relative_path','relativePath'],path),
    content: textValue(object,['content','text','value']),
    language: textValue(object,['language','language_id','languageId'],'plaintext'),
  }
}

export async function editorWriteFile(
  workspaceId: string,
  path: string,
  content: string,
): Promise<void> {
  const fn = pick(
    ['editorWriteFile','writeFile','writeWorkspaceFile','workspaceWriteFile','saveFile'],
    [['write','file'],['save','file'],['file','write']],
  )

  if (!fn) {
    throw new Error('Editor write transport is UNBOUND.')
  }

  await invokeAdaptive(
    fn,
    [workspaceId,path,content],
    {
      workspaceId,
      workspace_id: workspaceId,
      path,
      relativePath: path,
      relative_path: path,
      content,
    },
  )
}

export async function editorRunAction(
  workspaceId: string,
  action: string,
): Promise<EditorCommandResult> {
  const fn = pick(
    ['editorRunAction','runAction','runEditorAction','controlledAction'],
    [['run','action'],['editor','action'],['controlled','action']],
  )

  if (!fn) {
    throw new Error('Editor action transport is UNBOUND.')
  }

  const result=await invokeAdaptive(
    fn,
    [workspaceId,action],
    { workspaceId, workspace_id: workspaceId, action },
  )

  const object=objectValue(result)

  return {
    id: textValue(object,['id','command_id','commandId'],String(Date.now())),
    executable: textValue(object,['executable','program','command'],action),
    args: Array.isArray(object?.args) ? object.args.map((item)=>String(item)) : [],
    status: textValue(object,['status','state'],'UNKNOWN'),
    stdout: textValue(object,['stdout','output']),
    stderr: textValue(object,['stderr','error']),
  }
}
'@
      $repairAdapter=$repairAdapter.Replace('__VERTEX_TRANSPORT_IMPORT__',$relative)

      WriteUtf8 $editorShim $repairAdapter

      $repairReport=Join-Path $reports "EDITOR_FRONTEND_EXPORTS.$stamp.json"
      [ordered]@{
        schema='vertex.discovery.editor-exports.v1'
        timestamp=(Get-Date).ToString('o')
        source=$editorSource.FullName
        exports=@($exportNames)
        repaired_existing_shim=$true
      } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $repairReport -Encoding UTF8

      Write-Host "    Contract adapter repaired: $editorShim" -ForegroundColor Green
      Write-Host "    Export count             : $($exportNames.Count)" -ForegroundColor Green
      Write-Host "    Export report            : $repairReport" -ForegroundColor Green
    }
  }

  # ==========================================================
  # DISCOVER DEVELOPER AGENT FRONTEND API / TAURI IPC
  # ==========================================================
  Write-Host "  Developer Agent API            : TOPOLOGY DISCOVERY" -ForegroundColor Cyan

  $developerCandidates=@(
    Get-ChildItem -LiteralPath (Join-Path $ui 'src') -Recurse -File -Include '*.ts','*.tsx' |
    Where-Object {
      $_.FullName -ne $developerShim -and (
        ([IO.File]::ReadAllText($_.FullName)).Contains('startDeveloperTask') -or
        ([IO.File]::ReadAllText($_.FullName)).Contains('getDeveloperTask') -or
        ([IO.File]::ReadAllText($_.FullName)).Contains('listDeveloperWorkspaces')
      )
    }
  )

  if(-not(Test-Path -LiteralPath $developerShim)){
    $developerSource=$developerCandidates | Select-Object -First 1

    if($developerSource){
      $shimDir=Split-Path -Parent $developerShim
      $relative=(Get-RelativePathCompat $shimDir $developerSource.FullName).Replace('\','/')
      if(-not $relative.StartsWith('.')){$relative="./$relative"}
      $relative=$relative -replace '\.ts$',''

      WriteUtf8 $developerShim "export * from '$relative'`n"
      Write-Host "    Found frontend API: $($developerSource.FullName)" -ForegroundColor Green
      Write-Host "    Adapter shim       : $developerShim" -ForegroundColor Green
    }
    else {
      Write-Host "    Frontend API not found. Rust/Tauri candidates will be recorded." -ForegroundColor Yellow

      $rustHits=@()
      foreach($file in Get-ChildItem -LiteralPath $tauriSrc -Recurse -File -Filter '*.rs'){
        $body=[IO.File]::ReadAllText($file.FullName)
        if(
          $body -match '(?i)developer.*task' -or
          $body -match '(?i)start.*task' -or
          $body -match '(?i)workspace.*task'
        ){
          $rustHits += $file.FullName
        }
      }

      $topologyReport=Join-Path $reports "DEVELOPER_AGENT_TOPOLOGY.$stamp.json"
      [ordered]@{
        schema='vertex.discovery.developer-agent.v1'
        timestamp=(Get-Date).ToString('o')
        frontend_candidates=@($developerCandidates | ForEach-Object {$_.FullName})
        rust_candidates=@($rustHits)
        status=if($rustHits.Count){'RUST_CANDIDATE_FOUND'}else{'UNBOUND'}
      } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $topologyReport -Encoding UTF8

      $shim=@'
export interface DeveloperWorkspace {
  id: string
  name: string
  path?: string
}

export interface DeveloperActivity {
  sequence: number
  kind: string
  message: string
  detail?: string
  risk?: string
}

export interface DeveloperCommand {
  id: string
  executable: string
  args: string[]
  status: string
  stdout: string
  stderr: string
}

export interface DeveloperError {
  error_type: string
  code?: string
  message: string
  file?: string
  line?: number
}

export interface DeveloperTask {
  id: string
  state: string
  activities?: DeveloperActivity[]
  commands?: DeveloperCommand[]
  errors?: DeveloperError[]
  unified_diff?: string
}

export interface StartDeveloperTaskInput {
  workspace_id: string
  request: string
  mode: string
  provider_id: string
  model_id: string
}

function unbound(): never {
  throw new Error(
    'Developer Agent transport is UNBOUND. ' +
    'V7R3 does not invent Tauri command names.'
  )
}

export async function listDeveloperWorkspaces(): Promise<DeveloperWorkspace[]> {
  return []
}

export async function startDeveloperTask(
  _input: StartDeveloperTaskInput,
): Promise<DeveloperTask> {
  return unbound()
}

export async function getDeveloperTask(
  _id: string,
): Promise<DeveloperTask> {
  return unbound()
}

export async function cancelDeveloperTask(
  _id: string,
): Promise<void> {
  return unbound()
}

export async function rollbackDeveloperTask(
  _id: string,
): Promise<DeveloperTask> {
  return unbound()
}
'@
      WriteUtf8 $developerShim $shim
      Write-Host "    Developer transport : UNBOUND shim created" -ForegroundColor Yellow
      Write-Host "    Discovery report    : $topologyReport" -ForegroundColor Yellow
    }
  }else{
    Write-Host "    developer.ts already exists: PRESERVED" -ForegroundColor Green
  }

  $workspaceStore=Join-Path $workspaceDir 'useVsaWorkspace.ts'
  $mainEditorLocal=Join-Path $workspaceDir 'VertexMainEditor.vue'

  if(-not(Test-Path -LiteralPath $workspaceStore)){
    Write-Host "  workspace/useVsaWorkspace.ts   : CREATE" -ForegroundColor Cyan

    $content=@'
import { computed, ref } from 'vue'

import {
  cancelDeveloperTask,
  getDeveloperTask,
  listDeveloperWorkspaces,
  rollbackDeveloperTask,
  startDeveloperTask,
  type DeveloperCommand,
  type DeveloperTask,
  type DeveloperWorkspace,
} from '../../services/developer'

import {
  editorProjectTree,
  editorRuntimeInfo,
  editorRunAction,
  editorSearchFiles,
  type EditorRuntimeInfo,
} from '../../services/vertex-editor'

export type ControlAction =
  | 'cargo_fmt'
  | 'cargo_check'
  | 'cargo_test'
  | 'git_status'
  | 'git_diff'
  | 'cargo_build'
  | 'cargo_build_release'
  | 'cargo_clippy'

export interface ChatMessage {
  id: string
  role: 'human' | 'hyperagent' | 'system'
  text: string
  at: string
}

const workspaces = ref<DeveloperWorkspace[]>([])
const workspaceId = ref('')
const runtimeInfo = ref<EditorRuntimeInfo | null>(null)

const rawTree = ref('')
const treeDepth = ref(7)
const treeFilter = ref('')
const remoteSearchResults = ref<string[]>([])

const activeFilePath = ref('')
const openFileRequest = ref({ token: 0, path: '' })
const workspaceRevision = ref(0)

const providerId = ref('ollama')
const modelId = ref('qwen3:8b')
const developerTask = ref<DeveloperTask | null>(null)

const busy = ref(false)
const actionBusy = ref('')
const lastError = ref('')

const controlOutputs = ref<Partial<Record<ControlAction, DeveloperCommand>>>({})
const chatMessages = ref<ChatMessage[]>([])

let initialized = false
let pollTimer = 0

const activities = computed(() => developerTask.value?.activities ?? [])
const commands = computed(() => developerTask.value?.commands ?? [])
const errors = computed(() => developerTask.value?.errors ?? [])
const taskDiff = computed(() => developerTask.value?.unified_diff ?? '')

const taskStateLabel = computed(() => {
  switch(developerTask.value?.state){
    case 'COMPLETED': return '完了'
    case 'FAILED': return '失敗'
    case 'CANCELLED': return '中止'
    case 'RUNNING': return '実行中'
    case 'PAUSED': return '一時停止'
    case 'BLOCKED': return '待機'
    case 'CREATED': return '作成済み'
    default: return '待機中'
  }
})

const taskTone = computed(() => {
  const state=developerTask.value?.state
  if(state==='COMPLETED') return 'green'
  if(state==='FAILED'||state==='CANCELLED') return 'red'
  if(state) return 'amber'
  return 'muted'
})

const parsedTree = computed(() =>
  rawTree.value
    .split(/\r?\n/)
    .map((line) => {
      const match=/^(\s*)\[(D|F)\]\s+(.+)$/.exec(line)
      if(!match) return null
      return {
        path: match[3],
        kind: match[2]==='D' ? 'directory' as const : 'file' as const,
        depth: Math.floor(match[1].length/2),
      }
    })
    .filter((value): value is {path:string;kind:'file'|'directory';depth:number} => Boolean(value))
)

const visibleTree = computed(() => {
  const q=treeFilter.value.trim().toLowerCase()
  return q
    ? parsedTree.value.filter((item)=>item.path.toLowerCase().includes(q))
    : parsedTree.value
})

function pushMessage(role: ChatMessage['role'], text: string){
  chatMessages.value.push({
    id:`${Date.now()}-${Math.random().toString(36).slice(2)}`,
    role,
    text,
    at:new Date().toLocaleTimeString(),
  })
  chatMessages.value=chatMessages.value.slice(-100)
}

async function ensureInitialized(){
  if(initialized) return

  lastError.value=''
  try{
    workspaces.value=await listDeveloperWorkspaces()
    if(!workspaceId.value && workspaces.value.length){
      workspaceId.value=workspaces.value[0].id
    }
    if(workspaceId.value){
      const [tree,info]=await Promise.all([
        editorProjectTree(workspaceId.value,treeDepth.value),
        editorRuntimeInfo(workspaceId.value),
      ])
      rawTree.value=tree
      runtimeInfo.value=info
    }
    initialized=true
  }catch(error){
    lastError.value=String(error)
    throw error
  }
}

async function refreshTree(){
  if(!workspaceId.value) return
  rawTree.value=await editorProjectTree(workspaceId.value,treeDepth.value)
}

async function changeWorkspace(id:string){
  workspaceId.value=id
  activeFilePath.value=''
  developerTask.value=null
  controlOutputs.value={}
  await refreshTree()
  runtimeInfo.value=await editorRuntimeInfo(workspaceId.value)
  workspaceRevision.value++
}

async function changeTreeDepth(depth:number){
  treeDepth.value=depth
  await refreshTree()
}

async function remoteSearch(query:string){
  treeFilter.value=query.trim()
  if(!workspaceId.value || !treeFilter.value){
    remoteSearchResults.value=[]
    return
  }
  const result=await editorSearchFiles(workspaceId.value,treeFilter.value)
  remoteSearchResults.value=result
    .split(/\r?\n/)
    .map((value)=>value.trim())
    .filter(Boolean)
}

function requestOpenFile(path:string){
  if(!path) return
  openFileRequest.value={token:openFileRequest.value.token+1,path}
}

function setActiveFile(path:string){
  activeFilePath.value=path
}

function stopPolling(){
  window.clearInterval(pollTimer)
}

function beginPolling(taskId:string){
  stopPolling()
  pollTimer=window.setInterval(async()=>{
    try{
      const task=await getDeveloperTask(taskId)
      developerTask.value=task
      if(['COMPLETED','FAILED','CANCELLED'].includes(task.state)){
        stopPolling()
        await refreshTree()
        workspaceRevision.value++
      }
    }catch(error){
      lastError.value=String(error)
      stopPolling()
    }
  },700)
}

async function sendIntent(text:string, extraContext=''){
  const normalized=text.trim()
  if(!normalized || !workspaceId.value || busy.value) return

  busy.value=true
  pushMessage('human',normalized)

  try{
    const context=[
      `workspace_id=${workspaceId.value}`,
      activeFilePath.value ? `active_file=${activeFilePath.value}` : '',
      extraContext.trim(),
    ].filter(Boolean).join('\n')

    const request=context
      ? `${normalized}\n\n[VSA CONTEXT]\n${context}`
      : normalized

    const task=await startDeveloperTask({
      workspace_id:workspaceId.value,
      request,
      mode:'AUTO',
      provider_id:providerId.value,
      model_id:modelId.value,
    })

    developerTask.value=task
    pushMessage(
      'hyperagent',
      `ミッション ${task.id} を受領しました。状態: ${task.state}`
    )
    beginPolling(task.id)
  }catch(error){
    lastError.value=String(error)
    pushMessage('system',`送信失敗: ${String(error)}`)
    throw error
  }finally{
    busy.value=false
  }
}

async function cancelMission(){
  if(!developerTask.value) return
  await cancelDeveloperTask(developerTask.value.id)
  developerTask.value=await getDeveloperTask(developerTask.value.id)
}

async function rollbackMission(){
  if(!developerTask.value) return
  developerTask.value=await rollbackDeveloperTask(developerTask.value.id)
  await refreshTree()
  workspaceRevision.value++
}

async function runAction(action:ControlAction){
  if(!workspaceId.value || actionBusy.value) return null
  actionBusy.value=action
  try{
    const result=await editorRunAction(workspaceId.value,action)
    controlOutputs.value={...controlOutputs.value,[action]:result}
    return result
  }finally{
    actionBusy.value=''
  }
}

export function useVsaWorkspace(){
  return {
    workspaces,workspaceId,runtimeInfo,
    rawTree,treeDepth,treeFilter,remoteSearchResults,
    parsedTree,visibleTree,
    activeFilePath,openFileRequest,workspaceRevision,
    providerId,modelId,developerTask,
    busy,actionBusy,lastError,
    controlOutputs,chatMessages,
    activities,commands,errors,taskDiff,
    taskStateLabel,taskTone,
    ensureInitialized,refreshTree,changeWorkspace,changeTreeDepth,
    remoteSearch,requestOpenFile,setActiveFile,
    sendIntent,cancelMission,rollbackMission,runAction,
  }
}
'@
    WriteUtf8 $workspaceStore $content
  }

  if(-not(Test-Path -LiteralPath $mainEditorLocal)){
    Write-Host "  workspace/VertexMainEditor.vue : CREATE" -ForegroundColor Cyan

    $content=@'
<script setup lang="ts">
import 'monaco-editor/min/vs/editor/editor.main.css'
import * as monaco from 'monaco-editor'
import { computed,onMounted,onUnmounted,ref,watch } from 'vue'

import {
  editorReadFile,
  editorWriteFile,
} from '../../services/vertex-editor'

import { useVsaWorkspace } from './useVsaWorkspace'

const workspace=useVsaWorkspace()
const host=ref<HTMLElement|null>(null)
const docs=ref<Array<{
  path:string
  saved:string
  model:monaco.editor.ITextModel
}>>([])
const activePath=ref('')
const saving=ref(false)
const error=ref('')

let editor:monaco.editor.IStandaloneCodeEditor|null=null

const activeDoc=computed(
  ()=>docs.value.find((item)=>item.path===activePath.value) ?? null
)
const dirty=computed(
  ()=>Boolean(activeDoc.value && activeDoc.value.model.getValue()!==activeDoc.value.saved)
)

function languageFor(path:string){
  const lower=path.toLowerCase()
  if(lower.endsWith('.rs')) return 'rust'
  if(lower.endsWith('.vue')) return 'html'
  if(lower.endsWith('.ts')||lower.endsWith('.tsx')) return 'typescript'
  if(lower.endsWith('.js')) return 'javascript'
  if(lower.endsWith('.json')) return 'json'
  if(lower.endsWith('.css')||lower.endsWith('.scss')) return 'css'
  if(lower.endsWith('.md')) return 'markdown'
  return 'plaintext'
}

async function openFile(path:string){
  if(!workspace.workspaceId.value || !path) return

  const existing=docs.value.find((item)=>item.path===path)
  if(existing){
    activePath.value=path
    workspace.setActiveFile(path)
    editor?.setModel(existing.model)
    return
  }

  try{
    const snap=await editorReadFile(workspace.workspaceId.value,path)
    const uri=monaco.Uri.parse(
      `vertex-workspace:///${encodeURIComponent(snap.path)}`
    )
    let model=monaco.editor.getModel(uri)
    if(!model){
      model=monaco.editor.createModel(
        snap.content,
        languageFor(snap.path),
        uri
      )
    }else{
      model.setValue(snap.content)
    }

    docs.value.push({
      path:snap.path,
      saved:snap.content,
      model,
    })
    activePath.value=snap.path
    workspace.setActiveFile(snap.path)
    editor?.setModel(model)
  }catch(reason){
    error.value=String(reason)
  }
}

async function save(){
  const doc=activeDoc.value
  if(!doc || !workspace.workspaceId.value) return

  saving.value=true
  try{
    const value=doc.model.getValue()
    await editorWriteFile(workspace.workspaceId.value,doc.path,value)
    doc.saved=value
    await workspace.refreshTree()
  }finally{
    saving.value=false
  }
}

watch(
  ()=>workspace.openFileRequest.value.token,
  ()=>{
    const path=workspace.openFileRequest.value.path
    if(path) void openFile(path)
  }
)

onMounted(async()=>{
  if(!host.value) return

  editor=monaco.editor.create(host.value,{
    value:'',
    language:'plaintext',
    theme:'vs-dark',
    automaticLayout:true,
    fontSize:15,
    lineHeight:24,
    minimap:{enabled:true},
    smoothScrolling:true,
    stickyScroll:{enabled:true},
    bracketPairColorization:{enabled:true},
    padding:{top:12,bottom:12},
    scrollBeyondLastLine:false,
  })

  editor.addCommand(
    monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyS,
    ()=>void save()
  )

  await workspace.ensureInitialized()
})

onUnmounted(()=>{
  editor?.dispose()
  docs.value.forEach((doc)=>doc.model.dispose())
})
</script>

<template>
  <section class="vertex-main-editor">
    <header class="toolbar">
      <div>
        <strong>VSA エディター</strong>
        <small>PRIMARY EQUIPMENT / 中央作業面</small>
      </div>

      <select
        :value="workspace.workspaceId.value"
        @change="workspace.changeWorkspace(($event.target as HTMLSelectElement).value)"
      >
        <option
          v-for="item in workspace.workspaces.value"
          :key="item.id"
          :value="item.id"
        >
          {{ item.name }}
        </option>
      </select>

      <span>{{ workspace.taskStateLabel.value }}</span>

      <button
        :disabled="!dirty || saving"
        @click="save"
      >
        {{ saving ? '保存中…' : '保存' }}
      </button>
    </header>

    <div
      v-if="error || workspace.lastError.value"
      class="error"
    >
      {{ error || workspace.lastError.value }}
    </div>

    <nav class="tabs">
      <button
        v-for="doc in docs"
        :key="doc.path"
        :class="{active:doc.path===activePath}"
        @click="
          activePath=doc.path;
          workspace.setActiveFile(doc.path);
          editor?.setModel(doc.model)
        "
      >
        {{ doc.path.split(/[\\/]/).slice(-1)[0] }}
        <b v-if="doc.model.getValue()!==doc.saved">●</b>
      </button>

      <span v-if="!docs.length">
        VVEからファイルを選択してください
      </span>
    </nav>

    <div ref="host" class="host"/>

    <footer>
      {{ activePath || 'ファイル未選択' }}
    </footer>
  </section>
</template>

<style scoped>
.vertex-main-editor{
  position:absolute;inset:0;
  display:grid;min-width:0;min-height:0;
  grid-template-rows:50px auto 36px minmax(0,1fr) 26px;
  overflow:hidden;border:0;border-radius:0;
  background:#070812;box-shadow:none
}
.toolbar{
  display:flex;align-items:center;gap:8px;padding:6px 9px;
  border-bottom:1px solid #29304d;background:#0d1020
}
.toolbar>div{min-width:180px}
.toolbar strong,.toolbar small{display:block}
.toolbar strong{color:#d8def0;font-size:13px}
.toolbar small{margin-top:3px;color:#687391;font-size:8px}
.toolbar select{
  min-width:180px;height:30px;border:1px solid #343d61;
  background:#090c19;color:#c2cbe0
}
.toolbar span{margin-left:auto;color:#9b8adb;font-size:9px}
.toolbar button{
  height:30px;border:1px solid #6a52b7;
  background:#251f4b;color:#c7baf9
}
.error{
  padding:6px 9px;border-bottom:1px solid rgba(255,116,143,.35);
  background:#28111c;color:#ffc0cd;font-size:10px
}
.tabs{
  display:flex;overflow-x:auto;
  border-bottom:1px solid #29304d;background:#0b0e1b
}
.tabs button{
  min-width:120px;height:36px;border:0;border-right:1px solid #29304d;
  background:#0e1222;color:#77829f
}
.tabs button.active{
  background:#070812;color:#d7def0;
  box-shadow:inset 0 -2px 0 #8b5cf6
}
.tabs b{color:#f2c66d}
.tabs>span{
  display:flex;align-items:center;padding:0 10px;
  color:#596581;font-size:9px
}
.host{min-width:0;min-height:0;width:100%;height:100%}
footer{
  display:flex;align-items:center;padding:0 8px;
  border-top:1px solid #29304d;background:#0a0d18;color:#65708c;
  font:9px/1 ui-monospace,Consolas,monospace
}
</style>
'@
    WriteUtf8 $mainEditorLocal $content
  }

  $panelFiles=@(
    'HyperAgentChatPanel.vue',
    'VveExplorerPanel.vue',
    'AiActivityPanel.vue',
    'TerminalPanel.vue',
    'BuildPanel.vue',
    'TestPanel.vue',
    'ReviewerPanel.vue',
    'AiAssistantPanel.vue',
    'GitPanel.vue',
    'SystemMonitorPanelJa.vue',
    'VspStatusPanelJa.vue'
  )

  foreach($name in $panelFiles){
    $path=Join-Path $rolePanels $name
    if(Test-Path -LiteralPath $path){continue}

    $title=Switch($name){
      'HyperAgentChatPanel.vue' {'HYPERAgent チャット'}
      'VveExplorerPanel.vue' {'VVE エクスプローラー'}
      'AiActivityPanel.vue' {'AI 活動モニター'}
      'TerminalPanel.vue' {'ターミナル'}
      'BuildPanel.vue' {'ビルド'}
      'TestPanel.vue' {'テスト'}
      'ReviewerPanel.vue' {'レビュアー'}
      'AiAssistantPanel.vue' {'AI アシスタント'}
      'GitPanel.vue' {'Git'}
      'SystemMonitorPanelJa.vue' {'システム監視'}
      'VspStatusPanelJa.vue' {'VSP 状態'}
      default {$name}
    }

    $content=@"
<template>
  <section class="bootstrap-panel">
    <header><strong>$title</strong><span>BOOTSTRAP</span></header>
    <div class="body">
      <p>V7R1 Self-Bootstrap により生成された互換パネルです。</p>
      <p>既存のV6実装が存在する場合はそちらを優先して保持します。</p>
    </div>
  </section>
</template>

<style scoped>
.bootstrap-panel{
  display:grid;height:100%;grid-template-rows:40px minmax(0,1fr);
  background:#080a16
}
header{
  display:flex;align-items:center;justify-content:space-between;
  padding:0 8px;border-bottom:1px solid #29304d;background:#0d1020
}
header strong{color:#cbd3e6;font-size:10px}
header span{color:#8b78d0;font-size:7px}
.body{padding:10px;overflow:auto;color:#6f7a98;font-size:9px;line-height:1.5}
</style>
"@
    WriteUtf8 $path $content
  }

  Write-Host "  Full topology bootstrap        : READY" -ForegroundColor Green
}

EnsureBootstrapBase

Write-Host "`n[BOOTSTRAP-REPAIR] TypeScript surface normalization" -ForegroundColor Yellow

# Repair malformed TypeScript produced by older interpolating here-strings.
# Search patterns are SINGLE-QUOTED so PowerShell 5.1 cannot expand ${...}.
if(Test-Path -LiteralPath $editorShim){
  $existingGenerated=[IO.File]::ReadAllText($editorShim)

  $existingGenerated=$existingGenerated.Replace(
    'id: textValue(object,[''id'',''command_id'',''commandId''],${Date.now()}),',
    'id: textValue(object,[''id'',''command_id'',''commandId''],String(Date.now())),'
  )

  # Whitespace-tolerant fallback.
  $existingGenerated=[regex]::Replace(
    $existingGenerated,
    '\$\{Date\.now\(\)\}',
    'String(Date.now())'
  )

  WriteUtf8 $editorShim $existingGenerated

  # Re-read the actual file from disk and verify.
  $verifiedGenerated=[IO.File]::ReadAllText($editorShim)

  if(
    $verifiedGenerated.Contains('${Date.now()}') -or
    $verifiedGenerated -match '\$\{Date\.now\(\)\}'
  ){
    throw 'Editor adapter sanitation RED: literal ${Date.now()} still exists after rewrite.'
  }

  if(
    $verifiedGenerated -notmatch 'String\(Date\.now\(\)\)'
  ){
    throw 'Editor adapter sanitation RED: expected String(Date.now()) fallback is absent.'
  }

  Write-Host '  Existing generated adapter     : SANITIZED + VERIFIED' -ForegroundColor Green
}


$workspaceStoreRepair=Join-Path $workspaceDir 'useVsaWorkspace.ts'
$mainEditorRepair=Join-Path $workspaceDir 'VertexMainEditor.vue'

if(Test-Path -LiteralPath $workspaceStoreRepair){
  $storeText=[IO.File]::ReadAllText($workspaceStoreRepair)

  $storeText=$storeText.Replace(
    '.map((value)=>value.trim())',
    '.map((value: string) => value.trim())'
  )

  $storeText=$storeText.Replace(
    '.map((value) => value.trim())',
    '.map((value: string) => value.trim())'
  )

  WriteUtf8 $workspaceStoreRepair $storeText
  Write-Host '  useVsaWorkspace implicit-any   : REPAIRED' -ForegroundColor Green
}

if(Test-Path -LiteralPath $mainEditorRepair){
  $mainText=[IO.File]::ReadAllText($mainEditorRepair)

  if(-not $mainText.Contains('function selectDocument(')){
    $functionAnchor='async function save(){'

    if($mainText.Contains($functionAnchor)){
      $selectFunction=@'
function selectDocument(path: string) {
  const document = docs.value.find((item) => item.path === path)
  if (!document) return

  activePath.value = path
  workspace.setActiveFile(path)

  const instance = editor
  if (instance) {
    instance.setModel(document.model)
  }
}

'@

      $mainText=$mainText.Replace(
        $functionAnchor,
        $selectFunction+$functionAnchor
      )
    }
  }

  $oldTemplate=@'
        @click="
          activePath=doc.path;
          workspace.setActiveFile(doc.path);
          editor?.setModel(doc.model)
        "
'@

  $newTemplate=@'
        @click="selectDocument(doc.path)"
'@

  $mainText=$mainText.Replace($oldTemplate,$newTemplate)

  WriteUtf8 $mainEditorRepair $mainText
  Write-Host '  Monaco template setModel       : REPAIRED' -ForegroundColor Green
}

$required=@(
  $cockpit,$workspaceDir,$rolePanels,$shell,$editor,$mainEditor,
  (Join-Path $workspaceDir 'useVsaWorkspace.ts'),
  (Join-Path $rolePanels 'HyperAgentChatPanel.vue'),
  (Join-Path $rolePanels 'VveExplorerPanel.vue'),
  (Join-Path $rolePanels 'AiActivityPanel.vue'),
  (Join-Path $rolePanels 'TerminalPanel.vue'),
  (Join-Path $rolePanels 'BuildPanel.vue'),
  (Join-Path $rolePanels 'TestPanel.vue'),
  (Join-Path $rolePanels 'ReviewerPanel.vue'),
  (Join-Path $rolePanels 'AiAssistantPanel.vue'),
  (Join-Path $rolePanels 'GitPanel.vue'),
  (Join-Path $rolePanels 'SystemMonitorPanelJa.vue'),
  (Join-Path $rolePanels 'VspStatusPanelJa.vue'),
  $coreCargo,$tauriCargo
)

foreach($item in $required){
  if(-not(Test-Path -LiteralPath $item)){
    throw "Topology-bootstrap artifact missing after recovery: $item"
  }
}

$cargo=RequireCommand 'cargo'
$pnpm=RequireCommand 'pnpm'

Write-Host "`n[0/10] SELF-BOOTSTRAP BASELINE" -ForegroundColor Yellow

# Hard guard against known PowerShell interpolation residue.
if(Test-Path -LiteralPath $editorShim){
  $guardText=[IO.File]::ReadAllText($editorShim)

  foreach($token in @(
    '${Date.now()}',
    '${workspaceId}',
    '${action}'
  )){
    if($guardText.Contains($token)){
      throw "Generated editor adapter contains forbidden interpolation residue: $token"
    }
  }

  Write-Host '  Generated adapter syntax guard : GREEN' -ForegroundColor Green
}
RunChecked '[baseline] frontend build' {
  Push-Location $ui
  try{& $pnpm.Source build}finally{Pop-Location}
}

Write-Host "`n[1/10] BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
Copy-Item -LiteralPath $cockpit -Destination (Join-Path $backup 'vertex-cockpit') -Recurse -Force
Copy-Item -LiteralPath $editor -Destination (Join-Path $backup 'VertexEditorDock.vue') -Force

try{
  if(Test-Path -LiteralPath $equipmentDir){
    Remove-Item -LiteralPath $equipmentDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $equipmentDir -Force|Out-Null

  Write-Host "`n[2/10] EQUIPMENT UNIT CONTRACT" -ForegroundColor Yellow

  $registry=@'
export type EquipmentRuntimeMode =
  | 'static'
  | 'dockable'
  | 'agent'
  | 'drone'

export type EquipmentKind =
  | 'primary'
  | 'human-interface'
  | 'explorer'
  | 'monitor'
  | 'execution'
  | 'build'
  | 'test'
  | 'review'
  | 'assistant'
  | 'source-control'
  | 'memory'
  | 'system'

export type EquipmentPermission =
  | 'read-workspace'
  | 'write-workspace'
  | 'run-controlled-action'
  | 'mission-submit'
  | 'mission-observe'
  | 'runtime-read'

export interface EquipmentPort {
  id: string
  label: string
  direction: 'in' | 'out' | 'bidirectional'
  signal: string
}

export interface EquipmentLayout {
  col: number
  row: number
  colSpan: number
  rowSpan: number
  minColSpan: number
  minRowSpan: number
}

export interface EquipmentUnitDescriptor {
  id: string
  title: string
  subtitle: string
  kind: EquipmentKind
  runtimeMode: EquipmentRuntimeMode

  primary: boolean
  movable: boolean
  resizable: boolean
  floatable: boolean

  droneEligible: boolean
  droneRuntimeImplemented: boolean

  capabilities: string[]
  ports: EquipmentPort[]
  permissions: EquipmentPermission[]

  layout: EquipmentLayout
}

export const equipmentRegistry: EquipmentUnitDescriptor[] = [
  {
    id: 'hyperagent-chat',
    title: 'HYPERAgent チャット',
    subtitle: 'ヒューマン意図入力',
    kind: 'human-interface',
    runtimeMode: 'agent',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: false,
    droneRuntimeImplemented: false,
    capabilities: ['intent','mission-submit','mission-observe'],
    ports: [
      {
        id: 'intent-out',
        label: 'Human Intent',
        direction: 'out',
        signal: 'vertex.intent',
      },
      {
        id: 'mission-state-in',
        label: 'Mission State',
        direction: 'in',
        signal: 'vertex.mission.state',
      },
    ],
    permissions: ['mission-submit','mission-observe','runtime-read'],
    layout: {
      col: 1,row: 1,colSpan: 5,rowSpan: 10,minColSpan: 4,minRowSpan: 5,
    },
  },
  {
    id: 'vsa-editor',
    title: 'VSA エディター',
    subtitle: 'Primary Development Surface',
    kind: 'primary',
    runtimeMode: 'static',
    primary: true,
    movable: true,
    resizable: true,
    floatable: false,
    droneEligible: false,
    droneRuntimeImplemented: false,
    capabilities: ['read','write','diagnostics'],
    ports: [
      {
        id: 'file-open-in',
        label: 'File Open',
        direction: 'in',
        signal: 'vertex.file.open',
      },
      {
        id: 'active-file-out',
        label: 'Active File',
        direction: 'out',
        signal: 'vertex.file.active',
      },
    ],
    permissions: ['read-workspace','write-workspace','runtime-read'],
    layout: {
      col: 6,row: 1,colSpan: 13,rowSpan: 10,minColSpan: 8,minRowSpan: 5,
    },
  },
  {
    id: 'vve-explorer',
    title: 'VVE エクスプローラー',
    subtitle: 'Project World',
    kind: 'explorer',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['tree','search','file-open'],
    ports: [
      {
        id: 'file-open-out',
        label: 'File Open',
        direction: 'out',
        signal: 'vertex.file.open',
      },
      {
        id: 'structure-out',
        label: 'Project Structure',
        direction: 'out',
        signal: 'vertex.structure',
      },
    ],
    permissions: ['read-workspace','runtime-read'],
    layout: {
      col: 19,row: 1,colSpan: 6,rowSpan: 10,minColSpan: 4,minRowSpan: 5,
    },
  },
  {
    id: 'ai-activity',
    title: 'AI 活動モニター',
    subtitle: 'Agent Activity',
    kind: 'monitor',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['observe'],
    ports: [
      {
        id: 'activity-in',
        label: 'Activity',
        direction: 'in',
        signal: 'vertex.agent.activity',
      },
    ],
    permissions: ['mission-observe','runtime-read'],
    layout: {
      col: 1,row: 11,colSpan: 5,rowSpan: 6,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'terminal',
    title: 'ターミナル',
    subtitle: 'Controlled Execution',
    kind: 'execution',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['controlled-exec','evidence'],
    ports: [
      {
        id: 'command-in',
        label: 'Controlled Command',
        direction: 'in',
        signal: 'vertex.command.controlled',
      },
      {
        id: 'evidence-out',
        label: 'Execution Evidence',
        direction: 'out',
        signal: 'vertex.execution.evidence',
      },
    ],
    permissions: ['run-controlled-action','runtime-read'],
    layout: {
      col: 6,row: 11,colSpan: 7,rowSpan: 6,minColSpan: 5,minRowSpan: 3,
    },
  },
  {
    id: 'build',
    title: 'ビルド',
    subtitle: 'Cargo Build',
    kind: 'build',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['cargo-build','cargo-release'],
    ports: [
      {
        id: 'build-in',
        label: 'Build Request',
        direction: 'in',
        signal: 'vertex.build.request',
      },
      {
        id: 'build-out',
        label: 'Build Result',
        direction: 'out',
        signal: 'vertex.build.result',
      },
    ],
    permissions: ['run-controlled-action'],
    layout: {
      col: 13,row: 11,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'test',
    title: 'テスト',
    subtitle: 'Cargo Test',
    kind: 'test',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['cargo-test'],
    ports: [
      {
        id: 'test-in',
        label: 'Test Request',
        direction: 'in',
        signal: 'vertex.test.request',
      },
      {
        id: 'test-out',
        label: 'Test Result',
        direction: 'out',
        signal: 'vertex.test.result',
      },
    ],
    permissions: ['run-controlled-action'],
    layout: {
      col: 17,row: 11,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'reviewer',
    title: 'レビュアー',
    subtitle: 'Diagnostics / Clippy / Diff',
    kind: 'review',
    runtimeMode: 'agent',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['diagnostics','clippy','diff'],
    ports: [
      {
        id: 'review-in',
        label: 'Review Input',
        direction: 'in',
        signal: 'vertex.review.input',
      },
      {
        id: 'review-out',
        label: 'Review Result',
        direction: 'out',
        signal: 'vertex.review.result',
      },
    ],
    permissions: ['read-workspace','run-controlled-action','mission-observe'],
    layout: {
      col: 21,row: 11,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'ai-assistant',
    title: 'AI アシスタント',
    subtitle: 'Activity-derived Suggestions',
    kind: 'assistant',
    runtimeMode: 'agent',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['suggest'],
    ports: [
      {
        id: 'suggestion-out',
        label: 'Suggestion',
        direction: 'out',
        signal: 'vertex.suggestion',
      },
    ],
    permissions: ['mission-observe','runtime-read'],
    layout: {
      col: 13,row: 14,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'git',
    title: 'Git',
    subtitle: 'Status / Diff',
    kind: 'source-control',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['status','diff'],
    ports: [
      {
        id: 'git-state-out',
        label: 'Git State',
        direction: 'out',
        signal: 'vertex.git.state',
      },
    ],
    permissions: ['read-workspace','run-controlled-action'],
    layout: {
      col: 17,row: 14,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'system-monitor',
    title: 'システム監視',
    subtitle: 'Runtime Telemetry',
    kind: 'system',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['telemetry'],
    ports: [
      {
        id: 'telemetry-in',
        label: 'Telemetry',
        direction: 'in',
        signal: 'vertex.telemetry',
      },
    ],
    permissions: ['runtime-read'],
    layout: {
      col: 21,row: 14,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'vsp-status',
    title: 'VSP 状態',
    subtitle: 'Save Point / Lineage',
    kind: 'memory',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: false,
    droneRuntimeImplemented: false,
    capabilities: ['savepoint-observe'],
    ports: [
      {
        id: 'vsp-in',
        label: 'VSP State',
        direction: 'in',
        signal: 'vertex.vsp.state',
      },
    ],
    permissions: ['runtime-read'],
    layout: {
      col: 1,row: 14,colSpan: 5,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
]

export const equipmentById = Object.fromEntries(
  equipmentRegistry.map((item) => [item.id, item]),
) as Record<string, EquipmentUnitDescriptor>
'@
  WriteUtf8 (Join-Path $equipmentDir 'equipmentRegistry.ts') $registry

  Write-Host '  Equipment Contract : ONLINE' -ForegroundColor Green
  Write-Host '  Drone Eligibility  : ONLINE' -ForegroundColor Green

  Write-Host "`n[3/10] ADAPTIVE GRID STATE" -ForegroundColor Yellow

  $grid=@'
import { computed, ref, watch } from 'vue'

import {
  equipmentRegistry,
  type EquipmentLayout,
} from './equipmentRegistry'

export interface EquipmentPlacement extends EquipmentLayout {
  id: string
  visible: boolean
  z: number
}

export interface AdaptiveGridSnapshot {
  schema: 'vertex.adaptive-grid.v7'
  columns: 24
  rows: 16
  gap: number
  editMode: boolean
  placements: EquipmentPlacement[]
}

const STORAGE_KEY = 'vertex.adaptive-grid.v7'

function defaultSnapshot(): AdaptiveGridSnapshot {
  return {
    schema: 'vertex.adaptive-grid.v7',
    columns: 24,
    rows: 16,
    gap: 6,
    editMode: false,
    placements: equipmentRegistry.map((item, index) => ({
      id: item.id,
      visible: true,
      z: item.primary ? 10 : index + 20,
      ...item.layout,
    })),
  }
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

function load(): AdaptiveGridSnapshot {
  const fallback = defaultSnapshot()

  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return fallback

    const parsed = JSON.parse(raw) as Partial<AdaptiveGridSnapshot>
    if (parsed.schema !== 'vertex.adaptive-grid.v7') return fallback

    const incoming = Array.isArray(parsed.placements)
      ? parsed.placements
      : []

    return {
      schema: 'vertex.adaptive-grid.v7',
      columns: 24,
      rows: 16,
      gap: clamp(Number(parsed.gap ?? fallback.gap), 0, 18),
      editMode: Boolean(parsed.editMode),
      placements: fallback.placements.map((base) => {
        const rawPlacement = incoming.find(
          (item) =>
            item
            && typeof item === 'object'
            && (item as Partial<EquipmentPlacement>).id === base.id,
        ) as Partial<EquipmentPlacement> | undefined

        const colSpan = clamp(
          Number(rawPlacement?.colSpan ?? base.colSpan),
          base.minColSpan,
          24,
        )
        const rowSpan = clamp(
          Number(rawPlacement?.rowSpan ?? base.rowSpan),
          base.minRowSpan,
          16,
        )

        return {
          ...base,
          visible:
            typeof rawPlacement?.visible === 'boolean'
              ? rawPlacement.visible
              : base.visible,
          z: clamp(Number(rawPlacement?.z ?? base.z), 1, 9999),
          colSpan,
          rowSpan,
          col: clamp(
            Number(rawPlacement?.col ?? base.col),
            1,
            Math.max(1, 25 - colSpan),
          ),
          row: clamp(
            Number(rawPlacement?.row ?? base.row),
            1,
            Math.max(1, 17 - rowSpan),
          ),
        }
      }),
    }
  } catch {
    return fallback
  }
}

const snapshot = ref(load())
const activeDragId = ref('')
const activeResizeId = ref('')

const visiblePlacements = computed(() =>
  snapshot.value.placements.filter((item) => item.visible),
)

function bringToFront(id: string) {
  const target = snapshot.value.placements.find((item) => item.id === id)
  if (!target) return

  target.z = Math.max(
    1,
    ...snapshot.value.placements.map((item) => item.z),
  ) + 1
}

function show(id: string) {
  const item = snapshot.value.placements.find((value) => value.id === id)
  if (!item) return
  item.visible = true
  bringToFront(id)
}

function hide(id: string) {
  const item = snapshot.value.placements.find((value) => value.id === id)
  if (item) item.visible = false
}

function toggleEditMode() {
  snapshot.value.editMode = !snapshot.value.editMode
}

function setGap(value: number) {
  snapshot.value.gap = clamp(value, 0, 18)
}

function updatePlacement(
  id: string,
  patch: Partial<Pick<EquipmentPlacement,'col'|'row'|'colSpan'|'rowSpan'>>,
) {
  const target = snapshot.value.placements.find((item) => item.id === id)
  const descriptor = equipmentRegistry.find((item) => item.id === id)
  if (!target || !descriptor) return

  const colSpan = clamp(
    patch.colSpan ?? target.colSpan,
    descriptor.layout.minColSpan,
    24,
  )
  const rowSpan = clamp(
    patch.rowSpan ?? target.rowSpan,
    descriptor.layout.minRowSpan,
    16,
  )

  target.colSpan = colSpan
  target.rowSpan = rowSpan
  target.col = clamp(
    patch.col ?? target.col,
    1,
    Math.max(1, 25 - colSpan),
  )
  target.row = clamp(
    patch.row ?? target.row,
    1,
    Math.max(1, 17 - rowSpan),
  )

  bringToFront(id)
}

function reset() {
  snapshot.value = defaultSnapshot()
}

function exportLayout() {
  return JSON.stringify(snapshot.value, null, 2)
}

function importLayout(raw: string) {
  const parsed = JSON.parse(raw)
  if (parsed?.schema !== 'vertex.adaptive-grid.v7') {
    throw new Error('Unsupported layout schema')
  }

  localStorage.setItem(STORAGE_KEY, JSON.stringify(parsed))
  snapshot.value = load()
}

watch(
  snapshot,
  (value) => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
  },
  { deep: true },
)

export function useAdaptiveGrid() {
  return {
    snapshot,
    visiblePlacements,
    activeDragId,
    activeResizeId,
    bringToFront,
    show,
    hide,
    toggleEditMode,
    setGap,
    updatePlacement,
    reset,
    exportLayout,
    importLayout,
  }
}
'@
  WriteUtf8 (Join-Path $equipmentDir 'useAdaptiveGrid.ts') $grid

  Write-Host '  Grid 24x16      : ONLINE' -ForegroundColor Green
  Write-Host '  Persistence     : ONLINE' -ForegroundColor Green
  Write-Host '  Import / Export : ONLINE' -ForegroundColor Green

  Write-Host "`n[4/10] EQUIPMENT FRAME" -ForegroundColor Yellow

  $frame=@'
<script setup lang="ts">
import { computed, ref } from 'vue'

import { equipmentById } from './equipmentRegistry'
import { useAdaptiveGrid } from './useAdaptiveGrid'

const props = defineProps<{ equipmentId: string }>()
const grid = useAdaptiveGrid()

const descriptor = computed(() => equipmentById[props.equipmentId])
const placement = computed(
  () =>
    grid.snapshot.value.placements.find(
      (item) => item.id === props.equipmentId,
    ) ?? null,
)

const moveStart = ref({ x:0,y:0,col:1,row:1 })
const resizeStart = ref({ x:0,y:0,colSpan:1,rowSpan:1 })

function metrics() {
  const host = document.querySelector('.adaptive-grid-surface') as HTMLElement | null
  if (!host) return null

  const rect = host.getBoundingClientRect()
  const gap = grid.snapshot.value.gap

  return {
    cellWidth: (rect.width - gap * 23) / 24,
    cellHeight: (rect.height - gap * 15) / 16,
    gap,
  }
}

function startMove(event: PointerEvent) {
  if (
    !grid.snapshot.value.editMode
    || !descriptor.value?.movable
    || !placement.value
  ) return

  event.preventDefault()
  event.stopPropagation()

  grid.activeDragId.value = props.equipmentId

  moveStart.value = {
    x: event.clientX,
    y: event.clientY,
    col: placement.value.col,
    row: placement.value.row,
  }

  const onMove = (e: PointerEvent) => {
    const m = metrics()
    if (!m) return

    const dx = Math.round(
      (e.clientX - moveStart.value.x) / (m.cellWidth + m.gap),
    )
    const dy = Math.round(
      (e.clientY - moveStart.value.y) / (m.cellHeight + m.gap),
    )

    grid.updatePlacement(props.equipmentId, {
      col: moveStart.value.col + dx,
      row: moveStart.value.row + dy,
    })
  }

  const onUp = () => {
    grid.activeDragId.value = ''
    window.removeEventListener('pointermove', onMove)
    window.removeEventListener('pointerup', onUp)
  }

  window.addEventListener('pointermove', onMove)
  window.addEventListener('pointerup', onUp)
}

function startResize(event: PointerEvent) {
  if (
    !grid.snapshot.value.editMode
    || !descriptor.value?.resizable
    || !placement.value
  ) return

  event.preventDefault()
  event.stopPropagation()

  grid.activeResizeId.value = props.equipmentId

  resizeStart.value = {
    x: event.clientX,
    y: event.clientY,
    colSpan: placement.value.colSpan,
    rowSpan: placement.value.rowSpan,
  }

  const onMove = (e: PointerEvent) => {
    const m = metrics()
    if (!m) return

    const dx = Math.round(
      (e.clientX - resizeStart.value.x) / (m.cellWidth + m.gap),
    )
    const dy = Math.round(
      (e.clientY - resizeStart.value.y) / (m.cellHeight + m.gap),
    )

    grid.updatePlacement(props.equipmentId, {
      colSpan: resizeStart.value.colSpan + dx,
      rowSpan: resizeStart.value.rowSpan + dy,
    })
  }

  const onUp = () => {
    grid.activeResizeId.value = ''
    window.removeEventListener('pointermove', onMove)
    window.removeEventListener('pointerup', onUp)
  }

  window.addEventListener('pointermove', onMove)
  window.addEventListener('pointerup', onUp)
}
</script>

<template>
  <section
    v-if="placement && descriptor"
    class="equipment-unit"
    :class="{
      primary: descriptor.primary,
      editable: grid.snapshot.value.editMode,
    }"
    :style="{
      gridColumn: `${placement.col} / span ${placement.colSpan}`,
      gridRow: `${placement.row} / span ${placement.rowSpan}`,
      zIndex: placement.z,
    }"
    @pointerdown="grid.bringToFront(equipmentId)"
  >
    <header
      v-if="!descriptor.primary || grid.snapshot.value.editMode"
      class="equipment-head"
      @pointerdown="startMove"
    >
      <div class="title">
        <span>◆</span>
        <div>
          <strong>{{ descriptor.title }}</strong>
          <small>{{ descriptor.subtitle }}</small>
        </div>
      </div>

      <div class="badges">
        <b v-if="descriptor.primary">PRIMARY</b>
        <b v-if="descriptor.droneEligible">DRONE READY</b>
        <b>{{ descriptor.runtimeMode.toUpperCase() }}</b>

        <button
          v-if="!descriptor.primary"
          type="button"
          @pointerdown.stop
          @click.stop="grid.hide(equipmentId)"
        >
          ×
        </button>
      </div>
    </header>

    <div class="body">
      <slot />
    </div>

    <button
      v-if="grid.snapshot.value.editMode && descriptor.resizable"
      class="resize"
      type="button"
      @pointerdown="startResize"
    >
      ◢
    </button>

    <div
      v-if="grid.snapshot.value.editMode"
      class="readout"
    >
      C{{ placement.col }} R{{ placement.row }}
      · {{ placement.colSpan }}×{{ placement.rowSpan }}
    </div>
  </section>
</template>

<style scoped>
.equipment-unit {
  position: relative;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  border: 1px solid rgba(48,56,88,.88);
  border-radius: 5px;
  background:
    radial-gradient(circle at 75% -45%, rgba(124,92,255,.07), transparent 48%),
    #090c19;
  box-shadow: 0 10px 28px rgba(0,0,0,.18);
}

.equipment-unit.primary {
  border: 0;
  border-radius: 0;
  background: #070812;
  box-shadow: none;
}

.equipment-unit.editable {
  outline: 1px dashed rgba(169,140,255,.35);
  outline-offset: -3px;
}

.equipment-head {
  display: flex;
  min-height: 40px;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 0 9px;
  border-bottom: 1px solid #2a314e;
  background:
    linear-gradient(90deg, rgba(124,92,255,.10), transparent 52%),
    #0d1020;
  cursor: grab;
  user-select: none;
}

.title {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 7px;
}

.title > span {
  color: #a98cff;
  font-size: 8px;
}

.title strong,
.title small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.title strong {
  color: #cbd3e6;
  font-size: 11px;
}

.title small {
  margin-top: 3px;
  color: #606b87;
  font-size: 8px;
}

.badges {
  display: flex;
  align-items: center;
  gap: 4px;
}

.badges b {
  height: 20px;
  display: inline-flex;
  align-items: center;
  padding: 0 5px;
  border: 1px solid #313959;
  border-radius: 3px;
  background: #0a0d19;
  color: #68738f;
  font: 700 7px/1 ui-monospace,Consolas,monospace;
}

.badges b:nth-child(2) {
  border-color: rgba(98,216,255,.25);
  color: #7ab7cf;
}

.badges button {
  width: 22px;
  height: 22px;
  border: 1px solid #303858;
  border-radius: 3px;
  background: #0a0d19;
  color: #65718d;
}

.body {
  position: relative;
  min-width: 0;
  min-height: 0;
  height: 100%;
  overflow: hidden;
}

.equipment-unit:not(.primary) .body {
  height: calc(100% - 40px);
}

.body > :deep(*) {
  width: 100%;
  height: 100%;
  min-width: 0;
  min-height: 0;
}

.resize {
  position: absolute;
  z-index: 50;
  right: 3px;
  bottom: 3px;
  width: 24px;
  height: 24px;
  border: 1px solid #55458f;
  border-radius: 3px;
  background: rgba(29,23,62,.92);
  color: #a98cff;
  cursor: nwse-resize;
}

.readout {
  position: absolute;
  z-index: 45;
  right: 31px;
  bottom: 5px;
  padding: 3px 5px;
  background: rgba(7,8,18,.82);
  color: #6e628e;
  font: 700 7px/1 ui-monospace,Consolas,monospace;
}
</style>
'@
  WriteUtf8 (Join-Path $equipmentDir 'EquipmentUnitFrame.vue') $frame

  Write-Host '  Move / Resize : ONLINE' -ForegroundColor Green
  Write-Host '  Editor Float  : DENIED' -ForegroundColor Green

  Write-Host "`n[5/10] ADAPTIVE GRID HOST" -ForegroundColor Yellow
  Write-Host '  PowerShell `$Host collision      : REMOVED' -ForegroundColor Green

  $adaptiveGridHostSource=@'
<script setup lang="ts">
import type { Component } from 'vue'

import AiActivityPanel from '../role-layout/panels/AiActivityPanel.vue'
import AiAssistantPanel from '../role-layout/panels/AiAssistantPanel.vue'
import BuildPanel from '../role-layout/panels/BuildPanel.vue'
import GitPanel from '../role-layout/panels/GitPanel.vue'
import HyperAgentChatPanel from '../role-layout/panels/HyperAgentChatPanel.vue'
import ReviewerPanel from '../role-layout/panels/ReviewerPanel.vue'
import SystemMonitorPanelJa from '../role-layout/panels/SystemMonitorPanelJa.vue'
import TerminalPanel from '../role-layout/panels/TerminalPanel.vue'
import TestPanel from '../role-layout/panels/TestPanel.vue'
import VspStatusPanelJa from '../role-layout/panels/VspStatusPanelJa.vue'
import VveExplorerPanel from '../role-layout/panels/VveExplorerPanel.vue'

import EquipmentUnitFrame from './EquipmentUnitFrame.vue'
import { equipmentRegistry } from './equipmentRegistry'
import { useAdaptiveGrid } from './useAdaptiveGrid'

defineProps<{ telemetry: any }>()

const grid = useAdaptiveGrid()

const componentMap: Record<string, Component | 'slot'> = {
  'hyperagent-chat': HyperAgentChatPanel,
  'vsa-editor': 'slot',
  'vve-explorer': VveExplorerPanel,
  'ai-activity': AiActivityPanel,
  terminal: TerminalPanel,
  build: BuildPanel,
  test: TestPanel,
  reviewer: ReviewerPanel,
  'ai-assistant': AiAssistantPanel,
  git: GitPanel,
  'system-monitor': SystemMonitorPanelJa,
  'vsp-status': VspStatusPanelJa,
}
</script>

<template>
  <div class="grid-shell">
    <div
      class="adaptive-grid-surface"
      :class="{ editing: grid.snapshot.value.editMode }"
      :style="{ '--gap': `${grid.snapshot.value.gap}px` }"
    >
      <EquipmentUnitFrame
        v-for="placement in grid.visiblePlacements.value"
        :key="placement.id"
        :equipment-id="placement.id"
      >
        <slot
          v-if="componentMap[placement.id] === 'slot'"
          name="primary"
        />

        <component
          :is="componentMap[placement.id]"
          v-else
          :telemetry="telemetry"
        />
      </EquipmentUnitFrame>
    </div>

    <aside
      v-if="grid.snapshot.value.editMode"
      class="palette"
    >
      <header>
        <strong>レイアウト編集</strong>
        <span>24 × 16 GRID</span>
      </header>

      <div class="list">
        <button
          v-for="item in equipmentRegistry"
          :key="item.id"
          type="button"
          :class="{
            active:
              grid.snapshot.value.placements.find(
                (placement) => placement.id === item.id,
              )?.visible,
          }"
          @click="
            grid.snapshot.value.placements.find(
              (placement) => placement.id === item.id,
            )?.visible
              ? grid.hide(item.id)
              : grid.show(item.id)
          "
        >
          <span>{{ item.title }}</span>
          <small>
            {{
              item.primary
                ? 'PRIMARY'
                : item.droneEligible
                  ? 'DRONE READY'
                  : item.runtimeMode.toUpperCase()
            }}
          </small>
        </button>
      </div>

      <label>
        <span>グリッド間隔</span>
        <input
          type="range"
          min="0"
          max="18"
          :value="grid.snapshot.value.gap"
          @input="
            grid.setGap(
              Number(($event.target as HTMLInputElement).value),
            )
          "
        >
      </label>

      <button
        type="button"
        class="reset"
        @click="grid.reset"
      >
        Default配置へ戻す
      </button>
    </aside>
  </div>
</template>

<style scoped>
.grid-shell {
  position: absolute;
  inset: 0;
  overflow: hidden;
  background: #070812;
}

.adaptive-grid-surface {
  position: absolute;
  inset: 0;
  display: grid;
  min-width: 0;
  min-height: 0;
  grid-template-columns: repeat(24,minmax(0,1fr));
  grid-template-rows: repeat(16,minmax(0,1fr));
  gap: var(--gap,6px);
  padding: var(--gap,6px);
  overflow: hidden;
  background:
    radial-gradient(circle at 50% -10%, rgba(124,92,255,.07), transparent 34%),
    #070812;
}

.adaptive-grid-surface.editing {
  background-image:
    linear-gradient(rgba(124,92,255,.055) 1px,transparent 1px),
    linear-gradient(90deg,rgba(124,92,255,.055) 1px,transparent 1px),
    radial-gradient(circle at 50% -10%,rgba(124,92,255,.08),transparent 34%);
  background-size:
    calc((100% - 23 * var(--gap,6px)) / 24 + var(--gap,6px))
    calc((100% - 15 * var(--gap,6px)) / 16 + var(--gap,6px)),
    calc((100% - 23 * var(--gap,6px)) / 24 + var(--gap,6px))
    calc((100% - 15 * var(--gap,6px)) / 16 + var(--gap,6px)),
    auto;
}

.palette {
  position: absolute;
  z-index: 12000;
  top: 12px;
  right: 12px;
  width: 250px;
  max-height: calc(100% - 24px);
  overflow: auto;
  border: 1px solid #4b407b;
  border-radius: 6px;
  background: rgba(10,12,25,.96);
  box-shadow: 0 20px 60px rgba(0,0,0,.48);
}

.palette header {
  padding: 11px;
  border-bottom: 1px solid #303858;
}

.palette header strong,
.palette header span {
  display: block;
}

.palette header strong {
  color: #d0d7e9;
  font-size: 12px;
}

.palette header span {
  margin-top: 4px;
  color: #665b89;
  font: 700 8px/1 ui-monospace,Consolas,monospace;
}

.list {
  padding: 7px;
}

.list button {
  display: flex;
  width: 100%;
  min-height: 34px;
  align-items: center;
  justify-content: space-between;
  gap: 7px;
  margin-bottom: 4px;
  padding: 0 8px;
  border: 1px solid #2e3655;
  border-radius: 3px;
  background: #0b0e1c;
  color: #7783a0;
}

.list button.active {
  border-color: #6550ae;
  background: #1b1838;
  color: #c1b5ed;
}

.list button span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 9px;
}

.list button small {
  flex: none;
  color: #5f6985;
  font: 700 7px/1 ui-monospace,Consolas,monospace;
}

.palette label {
  display: block;
  margin: 0 8px 8px;
  padding: 9px;
  border-top: 1px solid #303858;
}

.palette label span {
  display: block;
  color: #6b7694;
  font-size: 8px;
}

.palette input {
  width: 100%;
  margin-top: 7px;
}

.reset {
  width: calc(100% - 16px);
  min-height: 32px;
  margin: 0 8px 9px;
  border: 1px solid #6b52b8;
  border-radius: 3px;
  background: #241e49;
  color: #c7bbf9;
}
</style>
'@
  WriteUtf8 (Join-Path $equipmentDir 'AdaptiveGridHost.vue') $adaptiveGridHostSource

  Write-Host '  Adaptive Host : ONLINE' -ForegroundColor Green

  Write-Host "`n[6/10] REBUILD DESKTOP SHELL" -ForegroundColor Yellow

  $themeImport=''
  $aetherTheme=Join-Path $cockpit 'theme\vertex-aether-violet.css'
  if(Test-Path -LiteralPath $aetherTheme){
    $themeImport="import './theme/vertex-aether-violet.css'"
  }

  $shellSource=@'
<script setup lang="ts">
import { computed,onMounted,onUnmounted } from 'vue'

__THEME_IMPORT__

import AdaptiveGridHost from './equipment/AdaptiveGridHost.vue'
import { useAdaptiveGrid } from './equipment/useAdaptiveGrid'
import { useCockpitTelemetry } from './cockpitTelemetry'

const { telemetry } = useCockpitTelemetry()
const grid = useAdaptiveGrid()

const mode = computed(
  () => grid.snapshot.value.editMode ? 'LAYOUT EDIT' : 'CREATION',
)

function onKey(event: KeyboardEvent) {
  if (
    event.ctrlKey
    && event.shiftKey
    && event.key.toLowerCase() === 'l'
  ) {
    event.preventDefault()
    grid.toggleEditMode()
  }

  if (
    event.ctrlKey
    && event.shiftKey
    && event.key.toLowerCase() === 'r'
  ) {
    event.preventDefault()
    grid.reset()
  }
}

onMounted(() => window.addEventListener('keydown',onKey))
onUnmounted(() => window.removeEventListener('keydown',onKey))
</script>

<template>
  <div class="vertex-cockpit adaptive-v7">
    <header class="top-deck">
      <section class="brand">
        <div class="gem"><span>V</span></div>
        <div>
          <strong>VERTEX STUDIO AI</strong>
          <small>Adaptive Grid Equipment Workspace</small>
        </div>
      </section>

      <section class="status-strip">
        <div>
          <span>プロジェクト</span>
          <strong>{{ telemetry.projectLabel }}</strong>
          <small>Workspace</small>
        </div>

        <div>
          <span>VSP</span>
          <strong>{{ telemetry.checkpointId || '信号なし' }}</strong>
          <small>{{ telemetry.liveOnline ? 'Live Session' : '未接続' }}</small>
        </div>

        <div>
          <span>VXN</span>
          <strong>{{ telemetry.runtimeOnline ? 'オンライン' : 'オフライン' }}</strong>
          <small>{{ telemetry.runtimeLabel }}</small>
        </div>

        <div>
          <span>Agent</span>
          <strong>{{ telemetry.agentCount ?? '未公開' }}</strong>
          <small>実Live信号</small>
        </div>

        <div>
          <span>VertexHub</span>
          <strong>
            {{
              telemetry.hubOnline
                ? `${telemetry.hubEnabledCount}/${telemetry.hubPackageCount}`
                : '信号なし'
            }}
          </strong>
          <small>有効 / 導入</small>
        </div>
      </section>

      <section class="captain">
        <span>USER : CAPTAIN</span>
        <small>MODE : {{ mode }}</small>
        <strong>{{ telemetry.now }}</strong>
      </section>

      <button
        class="layout-toggle"
        type="button"
        :class="{ active: grid.snapshot.value.editMode }"
        @click="grid.toggleEditMode"
      >
        {{
          grid.snapshot.value.editMode
            ? '配置編集を終了'
            : '配置編集'
        }}
      </button>
    </header>

    <main class="desktop-grid-zone">
      <AdaptiveGridHost :telemetry="telemetry">
        <template #primary>
          <slot />
        </template>
      </AdaptiveGridHost>
    </main>

    <footer class="system-ribbon">
      <span>24×16 GRID</span>
      <span>Gap {{ grid.snapshot.value.gap }}px</span>
      <span>Layout {{ grid.snapshot.value.editMode ? 'EDIT' : 'LOCKED' }}</span>
      <span>Editor PRIMARY / NO FLOAT</span>
      <span>Drone CONTRACT READY / RUNTIME未実装</span>
      <strong>Ctrl+Shift+L 配置編集</strong>
    </footer>
  </div>
</template>

<style scoped>
.vertex-cockpit {
  position: fixed;
  inset: 0;
  display: grid;
  width: 100vw;
  height: 100vh;
  min-width: 0;
  min-height: 0;
  grid-template-rows: 92px minmax(0,1fr) 28px;
  overflow: hidden;
  background:
    radial-gradient(circle at 52% -15%,rgba(124,92,255,.17),transparent 35%),
    #070812;
  color: #d7def0;
  font-family: Inter,"Segoe UI","Yu Gothic UI",system-ui,sans-serif;
}

.top-deck {
  display: grid;
  min-width: 0;
  grid-template-columns: 290px minmax(0,1fr) 175px 94px;
  gap: 6px;
  padding: 7px;
  border-bottom: 1px solid rgba(105,82,182,.58);
  background:
    radial-gradient(circle at 38% -90%,rgba(124,92,255,.18),transparent 55%),
    linear-gradient(180deg,#111427,#080a15);
}

.brand,
.captain,
.status-strip > div {
  min-width: 0;
  border: 1px solid #303858;
  background:
    linear-gradient(155deg,rgba(17,21,41,.97),rgba(8,10,20,.99));
}

.brand {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 13px;
}

.gem {
  display: grid;
  width: 42px;
  height: 42px;
  place-items: center;
  border: 1px solid rgba(169,140,255,.62);
  transform: rotate(45deg);
  background:
    radial-gradient(circle,rgba(124,92,255,.28),#16152f 68%);
}

.gem span {
  transform: rotate(-45deg);
  color: #b89cff;
  font-size: 17px;
  font-weight: 850;
}

.brand strong,
.brand small {
  display: block;
}

.brand strong {
  color: #e5e7f2;
  font-size: 16px;
}

.brand small {
  margin-top: 5px;
  color: #727d9a;
  font-size: 9px;
}

.status-strip {
  display: grid;
  min-width: 0;
  grid-template-columns: repeat(5,minmax(135px,1fr));
  gap: 5px;
  overflow-x: auto;
}

.status-strip > div {
  padding: 10px;
}

.status-strip span,
.status-strip strong,
.status-strip small {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.status-strip span {
  color: #6c7897;
  font-size: 8px;
}

.status-strip strong {
  margin-top: 6px;
  color: #c6cee1;
  font-size: 11px;
}

.status-strip small {
  margin-top: 4px;
  color: #56617d;
  font-size: 8px;
}

.captain {
  display: grid;
  align-content: center;
  justify-items: end;
  padding: 0 11px;
}

.captain span,
.captain small {
  color: #7884a0;
  font: 700 8px/1 ui-monospace,Consolas,monospace;
}

.captain small {
  margin-top: 4px;
}

.captain strong {
  margin-top: 7px;
  color: #e1e4ef;
  font: 500 17px/1 ui-monospace,Consolas,monospace;
}

.layout-toggle {
  border: 1px solid #3d4366;
  border-radius: 3px;
  background: #0d1020;
  color: #7e89a6;
  font-size: 9px;
  font-weight: 750;
}

.layout-toggle.active {
  border-color: #755bc9;
  background: #241e49;
  color: #cabdff;
}

.desktop-grid-zone {
  position: relative;
  min-width: 0;
  min-height: 0;
  overflow: hidden;
  background: #070812;
}

.desktop-grid-zone > :deep(*) {
  width: 100%;
  height: 100%;
}

.system-ribbon {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 18px;
  padding: 0 9px;
  overflow: hidden;
  border-top: 1px solid #2a314e;
  background: #090c18;
  color: #5e6986;
  font: 700 8px/1 ui-monospace,Consolas,monospace;
}

.system-ribbon span,
.system-ribbon strong {
  white-space: nowrap;
}

.system-ribbon strong {
  margin-left: auto;
  color: #7867b4;
}

@media (min-width:2200px) {
  .vertex-cockpit {
    grid-template-rows: 100px minmax(0,1fr) 30px;
  }

  .top-deck {
    grid-template-columns: 320px minmax(0,1fr) 185px 105px;
    padding: 9px;
  }
}

@media (max-width:1279px) {
  .vertex-cockpit {
    grid-template-rows: 82px minmax(0,1fr) 26px;
  }

  .top-deck {
    grid-template-columns: 210px minmax(0,1fr) 120px 78px;
    padding: 5px;
  }

  .status-strip {
    display: flex;
    overflow-x: auto;
  }

  .status-strip > div {
    min-width: 140px;
  }

  .system-ribbon span:nth-of-type(2),
  .system-ribbon span:nth-of-type(4) {
    display: none;
  }
}
</style>
'@

  $shellSource=$shellSource.Replace('__THEME_IMPORT__',$themeImport)
  WriteUtf8 $shell $shellSource

  Write-Host '  Full Desktop Grid : ONLINE' -ForegroundColor Green
  Write-Host '  Editor Primary    : ONLINE' -ForegroundColor Green


  Write-Host "`n[6.5/10] ENSURE PRIMARY EDITOR WRAPPER + VERTEXHUB" -ForegroundColor Yellow
  Write-Host '  PS5.1 conditional syntax       : GREEN' -ForegroundColor Green

  $editorCurrent=[IO.File]::ReadAllText($editor)

  # ----------------------------------------------------------
  # Observe current topology BEFORE replacing the wrapper.
  # ----------------------------------------------------------
  $hubCandidates=@(
    Get-ChildItem -LiteralPath (Join-Path $ui 'src') -Recurse -File -Filter 'VertexHubDock.vue' -ErrorAction SilentlyContinue
  )

  $previewCandidates=@(
    Get-ChildItem -LiteralPath (Join-Path $ui 'src') -Recurse -File -Filter 'VertexLivePreview.vue' -ErrorAction SilentlyContinue
  )

  $hubComponent=$hubCandidates | Select-Object -First 1
  $previewComponent=$previewCandidates | Select-Object -First 1

  $hubExpected=(
    $editorCurrent.Contains('VertexHubDock') -or
    $null -ne $hubComponent
  )

  $previewExpected=(
    $editorCurrent.Contains('VertexLivePreview') -or
    $null -ne $previewComponent
  )

  $hubTopologyLabel='NOT PRESENT'
  $hubTopologyColor='Yellow'
  if($hubExpected){
    $hubTopologyLabel='DETECTED'
    $hubTopologyColor='Green'
  }

  $previewTopologyLabel='NOT PRESENT'
  $previewTopologyColor='Yellow'
  if($previewExpected){
    $previewTopologyLabel='DETECTED'
    $previewTopologyColor='Green'
  }

  Write-Host ("  VertexHub topology              : {0}" -f $hubTopologyLabel) -ForegroundColor $hubTopologyColor
  Write-Host ("  GUI Preview topology            : {0}" -f $previewTopologyLabel) -ForegroundColor $previewTopologyColor

  $editorDir=Split-Path -Parent $editor

  $hubImport=''
  $hubTemplate=''

  if($hubExpected){
    if(-not $hubComponent){
      throw 'VertexHub was referenced by the current editor but VertexHubDock.vue could not be located.'
    }

    $hubRelative=(Get-RelativePathCompat $editorDir $hubComponent.FullName).Replace('\','/')
    if(-not $hubRelative.StartsWith('.')){$hubRelative="./$hubRelative"}

    $hubImport="import VertexHubDock from '$hubRelative'"
    $hubTemplate='    <VertexHubDock />'
  }

  $previewImport=''
  $previewTemplate=''

  if($previewExpected){
    if(-not $previewComponent){
      throw 'GUI Preview was referenced by the current editor but VertexLivePreview.vue could not be located.'
    }

    $previewRelative=(Get-RelativePathCompat $editorDir $previewComponent.FullName).Replace('\','/')
    if(-not $previewRelative.StartsWith('.')){$previewRelative="./$previewRelative"}

    $previewImport="import VertexLivePreview from '$previewRelative'"
    $previewTemplate='    <VertexLivePreview />'
  }

  # ----------------------------------------------------------
  # Always normalize the wrapper to the V7 Grid architecture.
  # Optional equipment is injected from observed topology.
  # ----------------------------------------------------------
  $editorWrapper=@'
<script setup lang="ts">
import VertexCockpitShell from '../vertex-cockpit/VertexCockpitShell.vue'
import VertexMainEditor from '../vertex-cockpit/workspace/VertexMainEditor.vue'
__VERTEX_HUB_IMPORT__
__VERTEX_PREVIEW_IMPORT__
</script>

<template>
  <main class="vsa-desktop-root">
    <VertexCockpitShell>
      <VertexMainEditor />
    </VertexCockpitShell>
__VERTEX_HUB_TEMPLATE__
__VERTEX_PREVIEW_TEMPLATE__
  </main>
</template>

<style scoped>
.vsa-desktop-root{
  position:fixed;
  inset:0;
  width:100vw;
  height:100vh;
  min-width:0;
  min-height:0;
  margin:0;
  padding:0;
  overflow:hidden;
  border:0;
  border-radius:0;
  background:#070812;
  box-shadow:none;
}
</style>
'@

  $editorWrapper=$editorWrapper.Replace('__VERTEX_HUB_IMPORT__',$hubImport)
  $editorWrapper=$editorWrapper.Replace('__VERTEX_PREVIEW_IMPORT__',$previewImport)
  $editorWrapper=$editorWrapper.Replace('__VERTEX_HUB_TEMPLATE__',$hubTemplate)
  $editorWrapper=$editorWrapper.Replace('__VERTEX_PREVIEW_TEMPLATE__',$previewTemplate)

  WriteUtf8 $editor $editorWrapper

  $editorWrapperVerify=[IO.File]::ReadAllText($editor)

  if(-not $editorWrapperVerify.Contains('VertexMainEditor')){
    throw 'Primary Editor Wrapper verification RED.'
  }

  if($hubExpected -and -not $editorWrapperVerify.Contains('<VertexHubDock />')){
    throw 'VertexHub preservation RED: wrapper lost VertexHubDock.'
  }

  if($previewExpected -and -not $editorWrapperVerify.Contains('<VertexLivePreview />')){
    throw 'GUI Preview preservation RED: wrapper lost VertexLivePreview.'
  }

  Write-Host '  Primary Editor Wrapper         : NORMALIZED' -ForegroundColor Green
  $hubPreservationLabel='N/A'
  if($hubExpected){
    $hubPreservationLabel='WIRED'
  }

  $previewPreservationLabel='N/A'
  if($previewExpected){
    $previewPreservationLabel='WIRED'
  }

  Write-Host ("  VertexHub preservation         : {0}" -f $hubPreservationLabel) -ForegroundColor Green
  Write-Host ("  GUI Preview preservation       : {0}" -f $previewPreservationLabel) -ForegroundColor Green

  Write-Host "`n[7/10] FRONTEND TYPECHECK / BUILD" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[v7] vue-tsc' {
      & $pnpm.Source exec vue-tsc --noEmit
    }

    RunChecked '[v7] vite build' {
      & $pnpm.Source exec vite build
    }
  }finally{
    Pop-Location
  }

  Write-Host "`n[8/10] STATIC AUDIT" -ForegroundColor Yellow

  $registryNow=[IO.File]::ReadAllText((Join-Path $equipmentDir 'equipmentRegistry.ts'))
  $gridNow=[IO.File]::ReadAllText((Join-Path $equipmentDir 'useAdaptiveGrid.ts'))
  $frameNow=[IO.File]::ReadAllText((Join-Path $equipmentDir 'EquipmentUnitFrame.vue'))
  $hostNow=[IO.File]::ReadAllText((Join-Path $equipmentDir 'AdaptiveGridHost.vue'))
  $shellNow=[IO.File]::ReadAllText($shell)
  $editorNow=[IO.File]::ReadAllText($editor)

  $audits=@(
    [pscustomobject]@{Name='24x16 Grid';Pass=$gridNow.Contains('columns: 24') -and $gridNow.Contains('rows: 16')},
    [pscustomobject]@{Name='Capability Contract';Pass=$registryNow.Contains('capabilities:')},
    [pscustomobject]@{Name='Ports Contract';Pass=$registryNow.Contains('EquipmentPort')},
    [pscustomobject]@{Name='Permissions Contract';Pass=$registryNow.Contains('EquipmentPermission')},
    [pscustomobject]@{Name='Drone Eligibility';Pass=$registryNow.Contains('droneEligible')},
    [pscustomobject]@{Name='Fake Drone Runtime Denied';Pass=$registryNow.Contains('droneRuntimeImplemented: false')},
    [pscustomobject]@{Name='Editor Primary';Pass=$registryNow.Contains("id: 'vsa-editor'") -and $registryNow.Contains('primary: true')},
    [pscustomobject]@{Name='Editor Float Denied';Pass=$registryNow.Contains('floatable: false')},
    [pscustomobject]@{Name='Move';Pass=$frameNow.Contains('startMove')},
    [pscustomobject]@{Name='Resize';Pass=$frameNow.Contains('startResize')},
    [pscustomobject]@{Name='Persistence';Pass=$gridNow.Contains('localStorage.setItem(STORAGE_KEY')},
    [pscustomobject]@{Name='Import Export';Pass=$gridNow.Contains('exportLayout') -and $gridNow.Contains('importLayout')},
    [pscustomobject]@{Name='V6 Real Components Reused';Pass=$hostNow.Contains('HyperAgentChatPanel') -and $hostNow.Contains('VveExplorerPanel') -and $hostNow.Contains('TerminalPanel')},
    [pscustomobject]@{Name='Japanese Layout UI';Pass=$shellNow.Contains('配置編集') -and $hostNow.Contains('レイアウト編集')},
    [pscustomobject]@{Name='No RPG';Pass=(-not $shellNow.Contains('PlayerHud')) -and (-not $registryNow.Contains('XP'))},
    [pscustomobject]@{
      Name='VertexHub Preserved'
      Pass=(
        (-not $hubExpected) -or
        (
          $editorNow.Contains('import VertexHubDock') -and
          $editorNow.Contains('<VertexHubDock />')
        )
      )
    },
    [pscustomobject]@{
      Name='GUI Preview Preserved'
      Pass=(
        (-not $previewExpected) -or
        (
          $editorNow.Contains('import VertexLivePreview') -and
          $editorNow.Contains('<VertexLivePreview />')
        )
      )
    }
  )

  foreach($audit in $audits){
    if(-not $audit.Pass){throw "V7 audit RED: $($audit.Name)"}
    Write-Host ("  {0,-40} GREEN" -f $audit.Name) -ForegroundColor Green
  }

  Write-Host "`n[9/10] TAURI / WORKSPACE GATE" -ForegroundColor Yellow

  $previous=$env:CARGO_TARGET_DIR
  try{
    if(Test-Path -LiteralPath $tauriTarget){
      Remove-Item -LiteralPath $tauriTarget -Recurse -Force
    }

    New-Item -ItemType Directory -Path $tauriTarget -Force|Out-Null
    $env:CARGO_TARGET_DIR=$tauriTarget

    RunChecked '[release] Tauri check' {
      & $cargo.Source check --manifest-path $tauriCargo --all-targets
    }
  }finally{
    $env:CARGO_TARGET_DIR=$previous
  }

  RunChecked '[release] cargo check workspace' {
    & $cargo.Source check --manifest-path $coreCargo --workspace --all-targets
  }

  RunChecked '[release] cargo test workspace' {
    & $cargo.Source test --manifest-path $coreCargo --workspace
  }

  Write-Host "`n[10/10] FINAL BUILD / REPORT" -ForegroundColor Yellow

  Push-Location $ui
  try{
    RunChecked '[release] pnpm build' {
      & $pnpm.Source build
    }
  }finally{
    Pop-Location
  }

  [ordered]@{
    schema='vertex.cic.adaptive-grid-equipment.v7'
    timestamp=(Get-Date).ToString('o')
    status='GREEN'
    mission='VSA ADAPTIVE GRID EQUIPMENT V7'
    grid=[ordered]@{
      columns=24
      rows=16
      snap='YES'
      move='YES'
      resize='YES'
      edit_mode='YES'
      persistence='LOCAL STORAGE'
      import_export='YES'
    }
    equipment=[ordered]@{
      common_contract='YES'
      capabilities='YES'
      ports='YES'
      permissions='YES'
      runtime_mode='YES'
      layout='YES'
      persistence='YES'
    }
    editor=[ordered]@{
      equipment='PRIMARY'
      default_center='YES'
      move='LAYOUT EDIT ONLY'
      resize='LAYOUT EDIT ONLY'
      float='DENIED'
      full_bleed='PRESERVED'
    }
    preservation=[ordered]@{
      vertex_hub_expected=$hubExpected
      vertex_hub_preserved=(
        (-not $hubExpected) -or
        ([IO.File]::ReadAllText($editor)).Contains('<VertexHubDock />')
      )
      gui_preview_expected=$previewExpected
      gui_preview_preserved=(
        (-not $previewExpected) -or
        ([IO.File]::ReadAllText($editor)).Contains('<VertexLivePreview />')
      )
    }
    drone=[ordered]@{
      compatibility='YES'
      eligible='VVE / AI Activity / Terminal / Build / Test / Reviewer / AI Assistant / Git / System Monitor'
      runtime='NOT IMPLEMENTED'
      fake_runtime='DENIED'
    }
    rpg='EXCLUDED'
    validation=[ordered]@{
      vue_typecheck='GREEN'
      frontend_build='GREEN'
      tauri_check='GREEN'
      workspace_check='GREEN'
      workspace_test='GREEN'
    }
    next='EQUIPMENT PORT BUS / MICRO DRONE RUNTIME / VSP GRID SNAPSHOT'
    backup=$backup
  }|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX - ADAPTIVE GRID EQUIPMENT V7 GREEN
============================================================
 Desktop Model                 FULL ADAPTIVE GRID
 Grid                          24 x 16
 Move                          ONLINE
 Resize                        ONLINE
 Snap                          ONLINE
 Layout Persistence            ONLINE
 Layout Import / Export        ONLINE

 Equipment Unit Contract       ONLINE
 Capability                    ONLINE
 Ports                         ONLINE
 Permissions                   ONLINE
 Drone Eligibility             ONLINE

 HYPERAgent                    EQUIPMENT UNIT
 VSA Editor                    PRIMARY EQUIPMENT
 VVE                           EQUIPMENT UNIT
 AI Activity                   EQUIPMENT UNIT
 Terminal                      EQUIPMENT UNIT
 Build                         EQUIPMENT UNIT
 Test                          EQUIPMENT UNIT
 Reviewer                      EQUIPMENT UNIT
 AI Assistant                  EQUIPMENT UNIT
 Git                           EQUIPMENT UNIT
 System Monitor                EQUIPMENT UNIT
 VSP                           EQUIPMENT UNIT

 Editor Float                  DENIED
 Editor Card Visual            DENIED
 Micro Drone Runtime           NOT IMPLEMENTED
 Fake Drone Runtime            DENIED
 RPG                           EXCLUDED

 Ctrl+Shift+L                  LAYOUT EDIT
 Ctrl+Shift+R                  RESET

 Frontend / Tauri / Workspace  GREEN
------------------------------------------------------------
 NEXT:
 EQUIPMENT PORT BUS
 MICRO DRONE RUNTIME
 VSP GRID SNAPSHOT
============================================================
 THE DESKTOP IS NOW A WORKSPACE, NOT A FRAME.
 WE ARE VERTEX.
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`n============================================================" -ForegroundColor Red
  Write-Host ' V7 RED - DAMAGE CONTROL' -ForegroundColor Red
  Write-Host '============================================================' -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red

  New-Item -ItemType Directory -Path $failed -Force|Out-Null

  if(Test-Path -LiteralPath $cockpit){
    Copy-Item -LiteralPath $cockpit -Destination (Join-Path $failed 'vertex-cockpit.failed') -Recurse -Force -ErrorAction SilentlyContinue
  }

  $cockpitBackup=Join-Path $backup 'vertex-cockpit'
  $editorBackup=Join-Path $backup 'VertexEditorDock.vue'

  if(Test-Path -LiteralPath $cockpitBackup){
    if(Test-Path -LiteralPath $cockpit){
      Remove-Item -LiteralPath $cockpit -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $cockpitBackup -Destination $cockpit -Recurse -Force
  }

  if(Test-Path -LiteralPath $editorBackup){
    Copy-Item -LiteralPath $editorBackup -Destination $editor -Force
  }

  Write-Host 'Cockpit rollback : COMPLETE' -ForegroundColor Yellow
  Write-Host 'Editor rollback  : COMPLETE' -ForegroundColor Yellow
  Write-Host "Failure evidence : $failed" -ForegroundColor Yellow
  throw
}
}