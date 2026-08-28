& {
$ErrorActionPreference='Stop'

$base='G:\Vertex_Project\Vertex_Studio_AI\HANGER\Startup_Package\VSA_Startup_Package_v0.2'
$ui=Join-Path $base 'apps\vsa-shell'
$core=Join-Path $base 'ProgramSource'
$reports=Join-Path $core '_vertex_reports'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $reports "VSA_EDITOR_V5_BACKUP.$stamp"
$failed=Join-Path $reports "VSA_EDITOR_V5_FAILED.$stamp"
$report=Join-Path $reports "VSA_EDITOR_V5.$stamp.json"
$utf8=New-Object System.Text.UTF8Encoding($false)

function W([string]$p,[string]$c){
  $d=Split-Path -Parent $p
  if($d){New-Item -ItemType Directory -Path $d -Force|Out-Null}
  [IO.File]::WriteAllText($p,$c,$utf8)
}
function Need([string]$n){
  $c=Get-Command $n -ErrorAction SilentlyContinue
  if(-not $c){throw "Missing command: $n"}
  $c
}
function Run([string]$label,[scriptblock]$action){
  Write-Host "`n$label" -ForegroundColor Cyan
  & $action
  if($LASTEXITCODE -ne 0){throw "$label RED ($LASTEXITCODE)"}
}
function B([string]$p){
  if(-not(Test-Path -LiteralPath $p)){return}
  $r=$p.Substring($base.Length).TrimStart('\').Replace('\','__')
  Copy-Item -LiteralPath $p -Destination (Join-Path $backup $r) -Force
}
function Restore-BackupFile([string]$p){
  $r=$p.Substring($base.Length).TrimStart('\').Replace('\','__')
  $s=Join-Path $backup $r
  if(Test-Path -LiteralPath $s){Copy-Item -LiteralPath $s -Destination $p -Force}
}

Write-Host @'
============================================================
 VERTEX CIC - VSA ULTIMATE EDITOR DOCKING V5
 CURRENT v0.2 ONLY / LEGACY EXCLUDED / FAIL-CLOSED
============================================================
'@ -ForegroundColor Cyan

foreach($p in @($base,$ui,$core)){
  if(-not(Test-Path -LiteralPath $p)){throw "Missing current VSA path: $p"}
}
New-Item -ItemType Directory -Path $reports -Force|Out-Null

$pkg=Join-Path $ui 'package.json'
$app=Join-Path $ui 'src\App.vue'
$main=Join-Path $ui 'src\main.ts'
$coreCargo=Join-Path $core 'Cargo.toml'
foreach($p in @($pkg,$app,$main,$coreCargo)){
  if(-not(Test-Path -LiteralPath $p)){throw "Missing required file: $p"}
}

Write-Host "`n[0/9] CURRENT TOPOLOGY LOCK" -ForegroundColor Yellow
$pjson=Get-Content -LiteralPath $pkg -Raw|ConvertFrom-Json
$deps=@{}
foreach($s in @('dependencies','devDependencies')){
  if($pjson.$s){
    foreach($x in $pjson.$s.PSObject.Properties){$deps[$x.Name]=[string]$x.Value}
  }
}
if(-not $deps.ContainsKey('vue')){throw 'vsa-shell is not Vue. Refusing.'}
$at=[IO.File]::ReadAllText($app)
if(-not $at.Contains('<template>') -or -not $at.Contains('<script setup')){throw 'Unsupported App.vue structure.'}

$mHits=@(Get-ChildItem (Join-Path $core 'crates') -Filter Cargo.toml -File -Recurse -ErrorAction SilentlyContinue|
  Select-String -Pattern 'mothership' -SimpleMatch -List -ErrorAction SilentlyContinue)
if($mHits.Count -eq 0){throw 'Mothership crate not found in current ProgramSource.'}
$hHits=@(Get-ChildItem (Join-Path $core 'crates') -Filter '*.rs' -File -Recurse -ErrorAction SilentlyContinue|
  Select-String -Pattern 'real_hyper_agent_runtime','REAL HYPER AGENT RUNTIME V2' -SimpleMatch -List -ErrorAction SilentlyContinue)

Write-Host "UI       : $ui" -ForegroundColor Green
Write-Host "CORE     : $core" -ForegroundColor Green
Write-Host "MShip    : $($mHits.Count) hit(s)" -ForegroundColor Green
Write-Host "Hyper    : $($hHits.Count) hit(s)" -ForegroundColor Green
Write-Host "LEGACY   : EXCLUDED" -ForegroundColor Green

Write-Host "`n[1/9] TOOLCHAIN" -ForegroundColor Yellow
$cargo=Need 'cargo'
$rustfmt=Need 'rustfmt'
if(Test-Path (Join-Path $ui 'pnpm-lock.yaml')){$pm='pnpm'}
elseif(Test-Path (Join-Path $ui 'package-lock.json')){$pm='npm'}
elseif(Get-Command pnpm -ErrorAction SilentlyContinue){$pm='pnpm'}
else{$pm='npm'}
$pmc=Need $pm
Write-Host "Package manager: $pm" -ForegroundColor Green

function PmBuild {
  if($pm -eq 'pnpm'){& $pmc.Source build}else{& $pmc.Source run build}
}
function PmInstall([string]$name,[bool]$dev){
  if($pm -eq 'pnpm'){
    if($dev){& $pmc.Source add -D $name}else{& $pmc.Source add $name}
  } else {
    if($dev){& $pmc.Source install --save-dev $name}else{& $pmc.Source install --save $name}
  }
  if($LASTEXITCODE -ne 0){throw "Dependency install failed: $name"}
}

Write-Host "`n[2/9] BASELINE" -ForegroundColor Yellow
Push-Location $ui
try{
  if(-not(Test-Path (Join-Path $ui 'node_modules'))){& $pmc.Source install;if($LASTEXITCODE -ne 0){throw 'Frontend install failed'}}
  Run '[baseline] frontend build' {PmBuild}
}finally{Pop-Location}
Run '[baseline] core cargo check' {& $cargo.Source check --manifest-path $coreCargo --workspace --all-targets}

Write-Host "`n[3/9] BACKUP" -ForegroundColor Yellow
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$locks=@((Join-Path $ui 'pnpm-lock.yaml'),(Join-Path $ui 'package-lock.json'))
foreach($p in @($pkg,$app,$main)+$locks){if($p -and(Test-Path $p)){B $p}}

$tauri=Join-Path $ui 'src-tauri'
$ed=Join-Path $ui 'src\vertex-editor'
$created=@()
try{
  Write-Host "`n[4/9] DEPENDENCIES + DESKTOP BRIDGE" -ForegroundColor Yellow
  Push-Location $ui
  try{
    if(-not $deps.ContainsKey('monaco-editor')){PmInstall 'monaco-editor@latest' $false}
    if(-not $deps.ContainsKey('@tauri-apps/api')){PmInstall '@tauri-apps/api@latest' $false}
    if(-not $deps.ContainsKey('@tauri-apps/cli')){PmInstall '@tauri-apps/cli@latest' $true}
  }finally{Pop-Location}

  if(Test-Path $tauri){throw "src-tauri already exists. Refusing overwrite: $tauri"}

  $tc=Join-Path $tauri 'Cargo.toml'
  $tb=Join-Path $tauri 'build.rs'
  $tm=Join-Path $tauri 'src\main.rs'
  $tl=Join-Path $tauri 'src\lib.rs'
  $tconf=Join-Path $tauri 'tauri.conf.json'
  $tcap=Join-Path $tauri 'capabilities\default.json'

  W $tc @'
[package]
name="vsa-shell-desktop"
version="0.1.0"
edition="2024"
rust-version="1.97.1"
license="Proprietary"

[lib]
name="vsa_shell_desktop_lib"
crate-type=["staticlib","cdylib","rlib"]

[build-dependencies]
tauri-build={version="2",features=[]}

[dependencies]
serde={version="1",features=["derive"]}
tauri={version="2",features=[]}
tokio={version="1",features=["process","rt-multi-thread","time"]}
'@
  W $tb 'fn main(){tauri_build::build()}'
  W $tm 'fn main(){vsa_shell_desktop_lib::run();}'
  $devCommand=if($pm -eq 'pnpm'){'pnpm dev'}else{'npm run dev'}
  $buildCommand=if($pm -eq 'pnpm'){'pnpm build'}else{'npm run build'}
  W $tconf @"
{
 "`$schema":"https://schema.tauri.app/config/2",
 "productName":"Vertex Studio AI",
 "version":"0.1.0",
 "identifier":"net.vertex.studio.ai",
 "build":{"beforeDevCommand":"$devCommand","devUrl":"http://127.0.0.1:5173","beforeBuildCommand":"$buildCommand","frontendDist":"../dist"},
 "app":{"windows":[{"label":"main","title":"Vertex Studio AI","width":1700,"height":1050,"minWidth":1100,"minHeight":720}],"security":{"csp":null}},
 "bundle":{"active":false}
}
"@
  W $tcap @'
{"identifier":"default","description":"Vertex Studio AI main window","windows":["main"],"permissions":["core:default"]}
'@
    $iconDir=Join-Path $tauri 'icons'
  $icon=Join-Path $iconDir 'icon.ico'
  New-Item -ItemType Directory -Path $iconDir -Force|Out-Null
  [IO.File]::WriteAllBytes($icon,[Convert]::FromBase64String('AAABAAEAICAAAAEAIABfAQAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAgAAAAIAgGAAAAc3p69AAAASZJREFUeJztV7EVgjAQ/fhcwIJnrw3QuQB7pHcBB7BiABewzx4uQCc0TsAQWoV3BIS7EInv6a9CSO7+/dzdS6LNdvdEQKxCOgeAtRkcT49FHV8vewDfpICBYfYp2EoHV+BPoJcDFHV1b8dJmomNc/aPKuDiVGqHfQQ0Gp/rJwm4qqAazdovSsLD7SxaZ0jMJpCkWWtsigT9X+aFHwIAoGM16ITO0Xm6fgyjZUiRpBnq6t5TosyLQcfc3BE3Ih2rt2pwo3YmQKOyz5d+SyrHuRXbecCtkNkEVKM75UUjV40W9w3nPkBzwc4JiRpsAlP1rWPVmeeSYBMwxm3nds+XkhAdwVimD1WI104oBcc5IOiEQ/BxXwh+JQtOoHcES7+QgisQ/fzr+AWu9GjhayhCCgAAAABJRU5ErkJggg=='))
  if(-not(Test-Path -LiteralPath $icon)){throw 'Tauri Windows icon generation failed'}
  Write-Host "Tauri Windows icon: $icon" -ForegroundColor Green
  $created+=@($tc,$tb,$tm,$tconf,$tcap,$icon)

  W $tl @'
use serde::{Deserialize,Serialize};
use std::{fs,path::{Component,Path,PathBuf},process::Stdio,time::{Duration,Instant}};
use tokio::{process::Command,time::timeout};

const MAX_FILE:u64=4*1024*1024;
const MAX_TREE:usize=20000;

#[derive(Serialize)]
struct RuntimeInfo{
 core_root:String,cargo_workspace:bool,mothership:bool,autonomous_loop:bool,
 real_hyper_agent:bool,bridge:bool,recent_reports:Vec<String>
}
#[derive(Serialize)]
struct FileSnapshot{path:String,content:String,language:String,bytes:usize,lines:usize}
#[derive(Serialize)]
struct WriteResult{path:String,bytes:usize,lines:usize}
#[derive(Serialize)]
struct ActionResult{
 action:String,executable:String,args:Vec<String>,success:bool,timed_out:bool,
 exit_code:Option<i32>,stdout:String,stderr:String,duration_ms:u128
}
#[derive(Deserialize)]
struct WriteInput{path:String,content:String}

fn norm(p:&Path)->String{p.to_string_lossy().replace('\\',"/")}
fn root()->Result<PathBuf,String>{
 let m=PathBuf::from(env!("CARGO_MANIFEST_DIR"));
 let b=m.ancestors().nth(3).ok_or("cannot resolve v0.2 root")?;
 let c=fs::canonicalize(b.join("ProgramSource")).map_err(|e|e.to_string())?;
 if !c.join("Cargo.toml").is_file(){return Err("ProgramSource Cargo.toml missing".into())}
 Ok(c)
}
fn secret(p:&Path)->bool{
 let n=p.file_name().and_then(|x|x.to_str()).unwrap_or("").to_ascii_lowercase();
 n==".env"||n.starts_with(".env.")||matches!(n.as_str(),"id_rsa"|"id_ed25519")||
 matches!(p.extension().and_then(|x|x.to_str()).map(str::to_ascii_lowercase).as_deref(),Some("pem"|"pfx"|"key"))
}
fn rel(s:&str)->Result<PathBuf,String>{
 let p=Path::new(s);
 if s.trim().is_empty()||p.is_absolute()||p.components().any(|c|matches!(c,Component::ParentDir|Component::RootDir|Component::Prefix(_))){
  return Err("absolute/parent traversal denied".into())
 }
 if secret(p){return Err("secret-like path denied".into())}
 Ok(p.to_path_buf())
}
fn existing(r:&Path,s:&str)->Result<PathBuf,String>{
 let p=fs::canonicalize(r.join(rel(s)?)).map_err(|e|e.to_string())?;
 if !p.starts_with(r){return Err("workspace escape denied".into())}
 if secret(&p){return Err("secret-like path denied".into())}
 Ok(p)
}
fn writable(r:&Path,s:&str)->Result<PathBuf,String>{
 let p=r.join(rel(s)?);
 let mut a=p.as_path();
 while !a.exists(){a=a.parent().ok_or("no workspace ancestor")?}
 let a=fs::canonicalize(a).map_err(|e|e.to_string())?;
 if !a.starts_with(r){return Err("workspace escape denied".into())}
 Ok(p)
}
fn ignored(n:&str)->bool{matches!(n,".git"|"target"|"node_modules"|"dist"|"build"|".idea"|".vscode")}
fn tree(r:&Path,c:&Path,d:usize,max:usize,out:&mut Vec<String>)->Result<(),String>{
 if d>max||out.len()>=MAX_TREE{return Ok(())}
 let mut es=fs::read_dir(c).map_err(|e|e.to_string())?.filter_map(Result::ok).collect::<Vec<_>>();
 es.sort_by_key(|e|e.file_name().to_string_lossy().to_ascii_lowercase());
 for e in es{
  if out.len()>=MAX_TREE{break}
  let p=e.path();let md=e.metadata().map_err(|x|x.to_string())?;let n=e.file_name().to_string_lossy().into_owned();
  if md.is_dir()&&ignored(&n){continue}
  let rr=p.strip_prefix(r).unwrap_or(&p);let k=if md.is_dir(){"D"}else{"F"};
  out.push(format!("{}[{}] {}","  ".repeat(d),k,norm(rr)));
  if md.is_dir(){tree(r,&p,d+1,max,out)?}
 }
 Ok(())
}
fn has_named(r:&Path,target:&str,max:usize)->bool{
 fn go(c:&Path,t:&str,d:usize,m:usize)->bool{
  if d>m{return false}
  let Ok(es)=fs::read_dir(c)else{return false};
  for e in es.filter_map(Result::ok){
   let p=e.path();let Ok(md)=e.metadata()else{continue};
   if md.is_dir(){
    let n=e.file_name().to_string_lossy().into_owned();if ignored(&n){continue}
    if go(&p,t,d+1,m){return true}
   }else if e.file_name().to_str().is_some_and(|x|x.eq_ignore_ascii_case(t)){return true}
  }false
 }go(r,target,0,max)
}
fn lang(p:&str)->String{
 let e=Path::new(p).extension().and_then(|x|x.to_str()).unwrap_or("").to_ascii_lowercase();
 match e.as_str(){
  "rs"=>"rust","ts"|"tsx"=>"typescript","js"|"jsx"|"mjs"|"cjs"=>"javascript",
  "json"=>"json","css"|"scss"=>"css","vue"|"html"=>"html","md"=>"markdown",
  "toml"=>"ini","yaml"|"yml"=>"yaml","ps1"=>"powershell","py"=>"python","sql"=>"sql","xml"=>"xml",_=>"plaintext"
 }.into()
}
#[tauri::command]
fn vertex_runtime_info()->Result<RuntimeInfo,String>{
 let r=root()?;let crates=r.join("crates");let reports=r.join("_vertex_reports");
 let names=fs::read_dir(&crates).ok().into_iter().flatten().filter_map(Result::ok)
  .map(|e|e.file_name().to_string_lossy().to_ascii_lowercase()).collect::<Vec<_>>();
 let mut rep=fs::read_dir(&reports).ok().into_iter().flatten().filter_map(Result::ok)
  .map(|e|e.path()).filter(|p|p.extension().and_then(|x|x.to_str()).is_some_and(|x|x.eq_ignore_ascii_case("json")))
  .collect::<Vec<_>>();
 rep.sort_by_key(|p|std::cmp::Reverse(fs::metadata(p).and_then(|m|m.modified()).ok()));
 rep.truncate(30);
 Ok(RuntimeInfo{
  core_root:norm(&r),cargo_workspace:r.join("Cargo.toml").is_file(),
  mothership:names.iter().any(|n|n.contains("mothership")),
  autonomous_loop:has_named(&crates,"autonomous_mission_loop.rs",5),
  real_hyper_agent:has_named(&crates,"real_hyper_agent_runtime.rs",5),
  bridge:names.iter().any(|n|n.contains("bridge")),
  recent_reports:rep.iter().map(|p|norm(p)).collect()
 })
}
#[tauri::command]
fn vertex_project_tree(depth:Option<usize>)->Result<String,String>{
 let r=root()?;let mut out=Vec::new();tree(&r,&r,0,depth.unwrap_or(5).clamp(1,8),&mut out)?;Ok(out.join("\n"))
}
#[tauri::command]
fn vertex_read_file(path:String)->Result<FileSnapshot,String>{
 let r=root()?;let p=existing(&r,&path)?;let md=fs::metadata(&p).map_err(|e|e.to_string())?;
 if !md.is_file(){return Err("not a file".into())}if md.len()>MAX_FILE{return Err("file exceeds 4MiB".into())}
 let b=fs::read(&p).map_err(|e|e.to_string())?;let c=String::from_utf8(b).map_err(|_|"not UTF-8".to_string())?;
 Ok(FileSnapshot{path:path.clone(),language:lang(&path),bytes:c.len(),lines:c.lines().count().max(1),content:c})
}
#[tauri::command]
fn vertex_write_file(input:WriteInput)->Result<WriteResult,String>{
 let r=root()?;if input.content.len() as u64>MAX_FILE{return Err("file exceeds 4MiB".into())}
 let p=writable(&r,&input.path)?;if let Some(d)=p.parent(){fs::create_dir_all(d).map_err(|e|e.to_string())?}
 fs::write(&p,input.content.as_bytes()).map_err(|e|e.to_string())?;
 Ok(WriteResult{path:input.path,bytes:input.content.len(),lines:input.content.lines().count().max(1)})
}
#[tauri::command]
async fn vertex_run_action(action:String)->Result<ActionResult,String>{
 let r=root()?;
 let (exe,args,ms)=match action.as_str(){
  "cargo_fmt"=>("cargo",vec!["fmt","--all"],120000),
  "cargo_check"=>("cargo",vec!["check","--workspace","--all-targets"],600000),
  "cargo_test"=>("cargo",vec!["test","--workspace"],900000),
  "git_status"=>("git",vec!["status","--short","--branch"],60000),
  "git_diff"=>("git",vec!["diff","--"],60000),
  _=>return Err("unsupported fixed control action".into())
 };
 let start=Instant::now();let mut c=Command::new(exe);
 c.args(&args).current_dir(&r).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);
 match timeout(Duration::from_millis(ms),c.output()).await{
  Ok(Ok(o))=>Ok(ActionResult{
   action,executable:exe.into(),args:args.iter().map(|x|x.to_string()).collect(),success:o.status.success(),
   timed_out:false,exit_code:o.status.code(),stdout:String::from_utf8_lossy(&o.stdout).into_owned(),
   stderr:String::from_utf8_lossy(&o.stderr).into_owned(),duration_ms:start.elapsed().as_millis()
  }),
  Ok(Err(e))=>Err(e.to_string()),
  Err(_)=>Ok(ActionResult{action,executable:exe.into(),args:args.iter().map(|x|x.to_string()).collect(),
   success:false,timed_out:true,exit_code:None,stdout:String::new(),stderr:format!("timeout after {ms}ms"),duration_ms:start.elapsed().as_millis()})
 }
}
#[cfg_attr(mobile,tauri::mobile_entry_point)]
pub fn run(){
 tauri::Builder::default().invoke_handler(tauri::generate_handler![
  vertex_runtime_info,vertex_project_tree,vertex_read_file,vertex_write_file,vertex_run_action
 ]).run(tauri::generate_context!()).expect("failed to run VSA desktop shell")
}
'@
  $created+=$tl

  Write-Host "`n[5/9] FRONTEND TRANSPORT + MONACO" -ForegroundColor Yellow
  $tr=Join-Path $ed 'transport.ts'
  $me=Join-Path $ed 'monaco-env.ts'
  $vw=Join-Path $ed 'VertexEditorDock.vue'

  W $tr @'
export interface RuntimeInfo{core_root:string;cargo_workspace:boolean;mothership:boolean;autonomous_loop:boolean;real_hyper_agent:boolean;bridge:boolean;recent_reports:string[]}
export interface FileSnapshot{path:string;content:string;language:string;bytes:number;lines:number}
export interface ActionResult{action:string;executable:string;args:string[];success:boolean;timed_out:boolean;exit_code:number|null;stdout:string;stderr:string;duration_ms:number}
export const desktop=()=>Boolean((window as unknown as{__TAURI_INTERNALS__?:unknown}).__TAURI_INTERNALS__)
async function call<T>(cmd:string,args?:Record<string,unknown>):Promise<T>{
 if(!desktop())throw new Error('Desktop bridge offline. Launch VSA through Tauri.')
 const{invoke}=await import('@tauri-apps/api/core');return invoke<T>(cmd,args)
}
export const runtimeInfo=()=>call<RuntimeInfo>('vertex_runtime_info')
export const projectTree=(depth=5)=>call<string>('vertex_project_tree',{depth})
export const readFile=(path:string)=>call<FileSnapshot>('vertex_read_file',{path})
export const writeFile=(path:string,content:string)=>call('vertex_write_file',{input:{path,content}})
export const runAction=(action:'cargo_fmt'|'cargo_check'|'cargo_test'|'git_status'|'git_diff')=>call<ActionResult>('vertex_run_action',{action})
'@
  W $me @'
import E from'monaco-editor/esm/vs/editor/editor.worker?worker'
import J from'monaco-editor/esm/vs/language/json/json.worker?worker'
import C from'monaco-editor/esm/vs/language/css/css.worker?worker'
import H from'monaco-editor/esm/vs/language/html/html.worker?worker'
import T from'monaco-editor/esm/vs/language/typescript/ts.worker?worker'
;(self as unknown as{MonacoEnvironment:{getWorker:(_m:string,l:string)=>Worker}}).MonacoEnvironment={getWorker(_m,l){if(l==='json')return new J();if(['css','scss','less'].includes(l))return new C();if(['html','handlebars','razor'].includes(l))return new H();if(['typescript','javascript'].includes(l))return new T();return new E()}}
'@

  W $vw @'
<script setup lang="ts">
import'./monaco-env'
import'monaco-editor/min/vs/editor/editor.main.css'
import*as monaco from'monaco-editor'
import{computed,nextTick,onMounted,onUnmounted,ref}from'vue'
import{desktop,projectTree,readFile,runAction,runtimeInfo,writeFile,type ActionResult,type RuntimeInfo}from'./transport'

type Entry={depth:number;kind:'file'|'directory';path:string}
type Doc={path:string;saved:string;model:monaco.editor.ITextModel}
type Tab='console'|'diff'|'diagnostics'|'runtime'|'reports'
const shown=ref(false),host=ref<HTMLElement|null>(null),rt=ref<RuntimeInfo|null>(null),raw=ref(''),filter=ref(''),depth=ref(5)
const docs=ref<Doc[]>([]),active=ref(''),busy=ref(false),err=ref(''),tab=ref<Tab>('console'),last=ref<ActionResult|null>(null),diff=ref(''),markers=ref<monaco.editor.IMarkerData[]>([])
const tabs:Tab[]=['console','diff','diagnostics','runtime','reports']
let editor:monaco.editor.IStandaloneCodeEditor|null=null
const online=computed(desktop),doc=computed(()=>docs.value.find(d=>d.path===active.value)||null),dirty=computed(()=>Boolean(doc.value&&doc.value.model.getValue()!==doc.value.saved))
const entries=computed<Entry[]>(()=>raw.value.split(/\r?\n/).map(l=>{const m=/^(\s*)\[(D|F)\]\s+(.+)$/.exec(l);return m?{depth:Math.floor(m[1].length/2),kind:m[2]==='D'?'directory':'file',path:m[3]}as Entry:null}).filter((x):x is Entry=>x!==null).filter(x=>!filter.value.trim()||x.path.toLowerCase().includes(filter.value.toLowerCase())))
const uri=(p:string)=>monaco.Uri.parse('vertex-core:///'+p.split('/').map(encodeURIComponent).join('/'))
function diag(){
 const d=doc.value;if(!d)return
 const out=`${last.value?.stdout||''}\n${last.value?.stderr||''}`.split(/\r?\n/),a:monaco.editor.IMarkerData[]=[]
 for(let i=0;i<out.length;i++){const m=/^\s*-->\s+(.+?):(\d+):(\d+)/.exec(out[i]);if(!m)continue;const p=m[1].replace(/\\\\/g,'/');if(p===d.path||p.endsWith('/'+d.path))a.push({severity:monaco.MarkerSeverity.Error,message:out.slice(Math.max(0,i-2),i).reverse().find(x=>/\berror\b/i.test(x))?.trim()||'Cargo diagnostic',source:'cargo',startLineNumber:+m[2],startColumn:+m[3],endLineNumber:+m[2],endColumn:+m[3]+1})}
 markers.value=a;monaco.editor.setModelMarkers(d.model,'vertex-evidence',a)
}
async function refresh(){if(!online.value)return;[rt.value,raw.value]=await Promise.all([runtimeInfo(),projectTree(depth.value)])}
async function openFile(p:string){
 const x=docs.value.find(d=>d.path===p);if(x){active.value=p;editor?.setModel(x.model);diag();return}
 try{const s=await readFile(p);let m=monaco.editor.getModel(uri(p));if(!m)m=monaco.editor.createModel(s.content,s.language,uri(p));docs.value.push({path:p,saved:s.content,model:m});active.value=p;editor?.setModel(m);diag()}catch(e){err.value=String(e)}
}
function pick(p:string){const d=docs.value.find(x=>x.path===p);if(d){active.value=p;editor?.setModel(d.model);diag()}}
function close(p:string){const i=docs.value.findIndex(x=>x.path===p);if(i<0)return;const[d]=docs.value.splice(i,1);d.model.dispose();if(active.value===p){const n=docs.value[Math.max(0,i-1)]||docs.value[0];active.value=n?.path||'';editor?.setModel(n?.model||null)}}
async function save(){const d=doc.value;if(!d||busy.value)return;busy.value=true;try{const c=d.model.getValue();await writeFile(d.path,c);d.saved=c;last.value=await runAction('git_diff');diff.value=last.value.stdout||last.value.stderr;tab.value='diff'}catch(e){err.value=String(e)}finally{busy.value=false}}
async function act(a:'cargo_fmt'|'cargo_check'|'cargo_test'|'git_status'|'git_diff'){if(busy.value)return;busy.value=true;err.value='';try{last.value=await runAction(a);if(a==='git_diff')diff.value=last.value.stdout||last.value.stderr;if(a.startsWith('cargo_'))diag();tab.value=a==='git_diff'?'diff':markers.value.length?'diagnostics':'console';rt.value=await runtimeInfo()}catch(e){err.value=String(e)}finally{busy.value=false}}
async function show(){shown.value=true;await nextTick();if(!editor&&host.value){editor=monaco.editor.create(host.value,{theme:'vs-dark',automaticLayout:true,fontSize:14,lineHeight:22,minimap:{enabled:true},smoothScrolling:true,folding:true,stickyScroll:{enabled:true},bracketPairColorization:{enabled:true},guides:{bracketPairs:true,indentation:true},scrollBeyondLastLine:false});editor.addCommand(monaco.KeyMod.CtrlCmd|monaco.KeyCode.KeyS,()=>void save())}try{await refresh()}catch(e){err.value=String(e)}}
function key(e:KeyboardEvent){if(e.key==='F9'){e.preventDefault();shown.value?shown.value=false:void show()}if(e.key==='Escape'&&shown.value)shown.value=false}
onMounted(()=>window.addEventListener('keydown',key));onUnmounted(()=>{window.removeEventListener('keydown',key);editor?.dispose();docs.value.forEach(d=>!d.model.isDisposed()&&d.model.dispose())})
</script>

<template>
<button class="vx-launch" :class="{on:online}" @click="show"><i></i>VSA EDITOR</button>
<Teleport to="body">
<section v-if="shown" class="vx">
<header><b>VX</b><div><strong>Vertex Ultimate Editor</strong><small>Command - Development - Inspector Surface</small></div><span class="grow"></span><em :class="{ok:rt?.mothership}">Mothership {{rt?.mothership?'DETECTED':'OFFLINE'}}</em><em :class="{ok:rt?.real_hyper_agent}">Hyper Agent {{rt?.real_hyper_agent?'ABOARD':'N/A'}}</em><button @click="refresh">Refresh</button><button :disabled="!dirty||busy" @click="save">Save</button><button @click="shown=false">X</button></header>
<p v-if="err" class="error">{{err}}</p>
<div class="body">
<aside><div class="head"><strong>Source Explorer</strong><select v-model.number="depth" @change="refresh"><option :value="4">D4</option><option :value="5">D5</option><option :value="6">D6</option><option :value="8">D8</option></select></div><input v-model="filter" placeholder="Filter ProgramSource..."><div class="tree"><button v-for="e in entries" :key="e.kind+e.path" :disabled="e.kind==='directory'" :style="{paddingLeft:(8+e.depth*12)+'px'}" @click="e.kind==='file'&&openFile(e.path)">{{e.kind==='directory'?'>':'*'}} {{e.path}}</button></div></aside>
<main><nav><button v-for="d in docs" :key="d.path" :class="{active:active===d.path}" @click="pick(d.path)">{{d.path.split('/').slice(-1)[0]}}<i v-if="d.model.getValue()!==d.saved">●</i><span @click.stop="close(d.path)">X</span></button></nav><div ref="host" class="editor"></div><footer>{{active||'No document'}}<span></span><i v-if="dirty">MODIFIED</i><small>Ctrl+S - F9</small></footer></main>
<section class="inspect"><nav><button v-for="t in tabs" :key="t" :class="{active:tab===t}" @click="tab=t">{{t}}</button></nav><div class="pane">
<template v-if="tab==='console'"><article v-if="last"><strong>{{last.executable}} {{last.args.join(' ')}}</strong><em :class="{ok:last.success,bad:!last.success}">{{last.timed_out?'TIMEOUT':last.success?'PASS':'FAIL'}}</em><pre v-if="last.stdout">{{last.stdout}}</pre><pre v-if="last.stderr" class="bad">{{last.stderr}}</pre></article><p v-else>NO MACHINE EVIDENCE</p></template>
<pre v-else-if="tab==='diff'">{{diff||'No Git diff captured.'}}</pre>
<template v-else-if="tab==='diagnostics'"><article v-for="(m,i) in markers" :key="i"><strong>line {{m.startLineNumber}}:{{m.startColumn}}</strong><p>{{m.message}}</p></article><p v-if="!markers.length">No active-file diagnostics.</p></template>
<dl v-else-if="tab==='runtime'&&rt"><dt>Core</dt><dd>{{rt.core_root}}</dd><dt>Mothership</dt><dd>{{rt.mothership}}</dd><dt>Autonomous</dt><dd>{{rt.autonomous_loop}}</dd><dt>Real Hyper Agent</dt><dd>{{rt.real_hyper_agent}}</dd><dt>Bridge</dt><dd>{{rt.bridge}}</dd><dt>Live Session IPC</dt><dd class="wait">NOT WIRED YET</dd></dl>
<div v-else><p v-for="r in rt?.recent_reports||[]" :key="r">{{r}}</p></div>
</div></section>
</div>
<section class="controls"><strong>Mothership Control Deck</strong><button :disabled="busy" @click="act('cargo_fmt')">Cargo Fmt</button><button :disabled="busy" @click="act('cargo_check')">Cargo Check</button><button :disabled="busy" @click="act('cargo_test')">Cargo Test</button><button :disabled="busy" @click="act('git_status')">Git Status</button><button :disabled="busy" @click="act('git_diff')">Git Diff</button><span>Escape DENIED - Secrets DENIED - Shell DENIED - Timeout/Kill ACTIVE</span></section>
</section>
</Teleport>
</template>

<style scoped>
.vx-launch{position:fixed;right:18px;bottom:18px;z-index:20000;height:36px;border:1px solid #39465d;border-radius:9px;background:#111722;color:#e7edf8;padding:0 12px;font:700 11px system-ui;cursor:pointer}.vx-launch i{display:inline-block;width:7px;height:7px;border-radius:50%;background:#7d8797;margin-right:7px}.vx-launch.on i{background:#42d99f;box-shadow:0 0 8px #42d99f}
.vx{--p:#111722;--l:#283346;--t:#e9eef8;--m:#8e9ab0;--a:#7588ff;position:fixed;inset:8px;z-index:25000;display:flex;flex-direction:column;min-width:900px;min-height:620px;background:#090c12;color:var(--t);border:1px solid var(--l);border-radius:13px;overflow:hidden;box-shadow:0 25px 90px #0009;font-family:system-ui}.vx header{height:58px;display:flex;align-items:center;gap:9px;padding:0 10px;background:var(--p);border-bottom:1px solid var(--l)}.vx header>b{display:grid;place-items:center;width:35px;height:35px;border-radius:8px;background:var(--a)}.vx header strong,.vx header small{display:block}.vx small{color:var(--m)}.grow{flex:1}.vx button,.vx select,.vx input{border:1px solid var(--l);background:#151d29;color:var(--t);border-radius:6px}.vx button{min-height:30px;padding:0 9px;cursor:pointer}.vx button:disabled{opacity:.45}.vx header em{font:700 10px system-ui;color:var(--m);border:1px solid var(--l);border-radius:999px;padding:5px 8px;font-style:normal}.ok{color:#42d99f!important}.bad{color:#ff7b89!important}.wait{color:#f2c86e!important}.error{margin:0;padding:7px 10px;background:#34151a;color:#ffc0c7;font:11px Consolas}.body{flex:1;min-height:0;display:grid;grid-template-columns:255px minmax(420px,1fr) 350px}.body>aside,.inspect{display:flex;flex-direction:column;min-width:0;background:var(--p)}.body>aside{border-right:1px solid var(--l)}.inspect{border-left:1px solid var(--l)}.head{height:42px;display:flex;align-items:center;justify-content:space-between;padding:0 8px;border-bottom:1px solid var(--l)}.body>aside>input{margin:7px;padding:7px}.tree{flex:1;overflow:auto}.tree button{display:block;width:100%;min-height:23px;border:0;border-radius:0;background:transparent;text-align:left;font:11px Consolas;color:#cbd5e7}.tree button:hover:not(:disabled){background:#182131}.tree button:disabled{color:var(--m)}.body>main{display:flex;flex-direction:column;min-width:0;min-height:0}.body main>nav,.inspect>nav{display:flex;min-height:34px;overflow:auto;background:var(--p);border-bottom:1px solid var(--l)}.body main>nav button{min-width:115px;border-radius:0;border-width:0 1px 0 0;color:var(--m)}nav button.active{color:var(--t);box-shadow:inset 0 -2px var(--a)}.body main>nav button i{color:#f2c86e;margin-left:5px}.body main>nav button span{float:right;margin-left:8px}.editor{flex:1;min-height:280px}.body main>footer{height:25px;display:flex;align-items:center;gap:10px;padding:0 8px;background:var(--p);border-top:1px solid var(--l);font:10px Consolas;color:var(--m)}.body main>footer span{flex:1}.body main>footer i{color:#f2c86e}.inspect>nav button{flex:1;min-width:60px;border-radius:0;border:0;color:var(--m);font-size:10px}.pane{flex:1;overflow:auto;padding:8px}.pane article,.pane>p,.pane div>p{padding:8px;border:1px solid var(--l);border-radius:6px;background:#0b1018;font:10px Consolas;overflow-wrap:anywhere}.pane article em{float:right;font-style:normal}.pane pre{padding:8px;background:#070a0f;color:#bdc8da;white-space:pre-wrap;word-break:break-word;overflow:auto;font:10px/1.45 Consolas}.pane dl{display:grid;grid-template-columns:110px 1fr;gap:0;margin:0}.pane dt,.pane dd{padding:7px 0;border-bottom:1px solid var(--l);font:10px Consolas}.pane dt{color:var(--m)}.pane dd{margin:0;overflow-wrap:anywhere}.controls{min-height:62px;display:flex;align-items:center;gap:7px;padding:0 10px;background:var(--p);border-top:1px solid var(--l)}.controls>strong{margin-right:10px}.controls>span{margin-left:auto;color:var(--m);font:9px Consolas}
@media(max-width:1100px){.body{grid-template-columns:220px 1fr}.inspect{grid-column:1/-1;min-height:220px;border-left:0;border-top:1px solid var(--l)}.controls{flex-wrap:wrap}.controls>span{margin-left:0}}
</style>
'@
  $created+=@($tr,$me,$vw)

  Write-Host "`n[6/9] DOCK WORKBENCH INTO CURRENT App.vue" -ForegroundColor Yellow
  $s=[IO.File]::ReadAllText($app)
  if($s.Contains('VertexEditorDock')){throw 'VertexEditorDock already present; refusing duplicate'}
  $m=[regex]::Match($s,'<script setup[^>]*>')
  if(-not $m.Success){throw 'script setup anchor missing'}
  $s=$s.Insert($m.Index+$m.Length,"`r`nimport VertexEditorDock from './vertex-editor/VertexEditorDock.vue'")
  $i=$s.IndexOf('<template>')
  if($i -lt 0){throw 'template anchor missing'}
  $s=$s.Insert($i+'<template>'.Length,"`r`n  <VertexEditorDock />")
  W $app $s

  Write-Host "`n[7/9] TARGETED VALIDATION" -ForegroundColor Yellow
  Run '[editor] rustfmt' {& $rustfmt.Source --edition 2024 $tl $tm $tb}
  Run '[editor] Tauri cargo check' {& $cargo.Source check --manifest-path $tc --all-targets}
  Push-Location $ui
  try{Run '[editor] frontend build' {PmBuild}}finally{Pop-Location}

  Write-Host "`n[8/9] PROGRAMSOURCE RELEASE GATE" -ForegroundColor Yellow
  Run '[release] cargo check --workspace --all-targets' {& $cargo.Source check --manifest-path $coreCargo --workspace --all-targets}
  Run '[release] cargo test --workspace' {& $cargo.Source test --manifest-path $coreCargo --workspace}

  Write-Host "`n[9/9] REPORT" -ForegroundColor Yellow
  [ordered]@{
    schema='vertex.cic.vsa-editor-v3';timestamp=(Get-Date).ToString('o');status='GREEN'
    ui=$ui;core=$core;legacy='EXCLUDED'
    editor=@{monaco='ONLINE';explorer='ONLINE';tabs='ONLINE';save='ONLINE';diagnostics='ONLINE';inspector='ONLINE';diff='ONLINE'}
    control=@{cargo='CONTROLLED';git='CONTROLLED';arbitrary_shell='DENIED';workspace_escape='DENIED';secrets='DENIED';timeout_kill='ACTIVE'}
    mothership=@{detected=($mHits.Count -gt 0);real_hyper_agent=($hHits.Count -gt 0);live_session_ipc='NOT_WIRED_YET'}
    validation=@{frontend='GREEN';tauri='GREEN';workspace_check='GREEN';workspace_test='GREEN'}
    backup=$backup
  }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $report -Encoding UTF8

  Write-Host @"
============================================================
 VERTEX - ULTIMATE EDITOR CURRENT-CORE DOCKING GREEN
============================================================
 v0.2 UI                       LOCKED
 ProgramSource Core            LOCKED
 LEGACY / v0.1                 EXCLUDED
 Monaco Editor                 ONLINE
 Source Explorer               ONLINE
 Multi-file Tabs               ONLINE
 Ctrl+S Save                   ONLINE
 Cargo Diagnostics             ONLINE
 Console Inspector             ONLINE
 Git Diff                      ONLINE
 Runtime / Voyage Reports      ONLINE
 Cargo / Git Control           CONTROLLED
 Arbitrary Shell               DENIED
 Workspace Escape              DENIED
 Secret-like Files             DENIED
 Tauri Check                   GREEN
 Frontend Build                GREEN
 Workspace Release Gate        GREEN
------------------------------------------------------------
 Live Session/Wave IPC         NEXT DOCKING TARGET
------------------------------------------------------------
 REPORT: $report
============================================================
"@ -ForegroundColor Green
}
catch{
  Write-Host "`nV5 RED - DAMAGE CONTROL" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  New-Item -ItemType Directory -Path $failed -Force|Out-Null
  if(Test-Path $tauri){Copy-Item $tauri (Join-Path $failed 'src-tauri') -Recurse -Force -ErrorAction SilentlyContinue;Remove-Item $tauri -Recurse -Force -ErrorAction SilentlyContinue}
  if(Test-Path $ed){Copy-Item $ed (Join-Path $failed 'vertex-editor') -Recurse -Force -ErrorAction SilentlyContinue;Remove-Item $ed -Recurse -Force -ErrorAction SilentlyContinue}
  foreach($p in @($pkg,$app,$main)+$locks){if($p){Restore-BackupFile $p}}
  Write-Host "ROLLBACK: COMPLETE" -ForegroundColor Yellow
  Write-Host "EVIDENCE: $failed" -ForegroundColor Yellow
  throw
}
}