#requires -Version 7.0
<#
VERTEX VXN — MAXIMUM ARCHITECTURE FOUNDATION
PHASE 0 / FOUNDATION
Sidecar build. Existing VSA is preserved.

PHILOSOPHY
  - Maximum Viable Architecture
  - Existing technology is preserved
  - VXN is a Hybrid Machine Cognitive Fabric
  - Native Representation remains the origin
  - LLM behavior is adapted, not forcibly replaced
  - Cognition and execution authority are separated
  - VTC owns reality mutation
  - VXN may think, observe, route, recall, and propose
  - Canonical truth is evidence-driven
  - Impact is attention, not truth
  - Human authority and locked states are first-class
  - Extension points are created from the beginning

DEFAULT TARGET
  G:\Vertex_Project\Vertex_Studio_AI\VXN

THIS SCRIPT MUTATES PROJECT FILES ONLY.
NO OS / FIREWALL / REGISTRY / SERVICE MUTATION.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [ValidateSet('Build','Plan')]
    [string]$Mode = 'Build',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-FOUNDATION-$stamp"

function Write-Banner {
    param([string]$Text)
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Ensure-Dir {
    param([Parameter(Mandatory)][string]$Path)

    if ($Mode -eq 'Plan') {
        Write-Host "PLAN  DIR  $Path"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "CREATE DIR  $Path" -ForegroundColor Green
    }
    else {
        Write-Host "KEEP   DIR  $Path"
    }
}

function Write-TextFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    if ($Mode -eq 'Plan') {
        Write-Host "PLAN  FILE $Path"
        return
    }

    $parent = Split-Path -Parent $Path
    if ($parent) {
        Ensure-Dir $parent
    }

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        Write-Host "KEEP   FILE $Path" -ForegroundColor Yellow
        return
    }

    $Content | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Host "WRITE  FILE $Path" -ForegroundColor Green
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )

    $json = $Object | ConvertTo-Json -Depth 100
    Write-TextFile -Path $Path -Content $json
}

Write-Banner 'VERTEX VXN — MAXIMUM ARCHITECTURE FOUNDATION'
Write-Host "Run ID      : $runId"
Write-Host "Project Root: $ProjectRoot"
Write-Host "VXN Root    : $VxnRoot"
Write-Host "Mode        : $Mode"
Write-Host "Force       : $Force"
Write-Host ''
Write-Host 'PROJECT FILE MUTATION ONLY'
Write-Host 'NO OS / FIREWALL / REGISTRY / SERVICE MUTATION'

# ---------------------------------------------------------------------
# 0. FOUNDATION DIRECTORIES
# ---------------------------------------------------------------------

$dirs = @(
    'core',
    'core\src',
    'core\src\native',
    'core\src\native\ir',
    'core\src\native\codec',
    'core\src\native\schema',
    'core\src\native\dictionary',
    'core\src\native\frame',
    'core\src\fabric',
    'core\src\fabric\event',
    'core\src\fabric\signal',
    'core\src\fabric\relation',
    'core\src\fabric\transport',
    'core\src\fabric\backpressure',
    'core\src\cognitive',
    'core\src\cognitive\identity',
    'core\src\cognitive\impact',
    'core\src\cognitive\association',
    'core\src\cognitive\scope',
    'core\src\cognitive\lock',
    'core\src\cognitive\uncertainty',
    'core\src\cognitive\routing',
    'core\src\memory',
    'core\src\memory\vmb',
    'core\src\memory\vsp',
    'core\src\memory\vcc',
    'core\src\memory\tiering',
    'core\src\memory\candidate',
    'core\src\memory\canonical',
    'core\src\plasticity',
    'core\src\plasticity\strengthen',
    'core\src\plasticity\decay',
    'core\src\plasticity\suppress',
    'core\src\plasticity\protect',
    'core\src\plasticity\rehabilitate',
    'core\src\plasticity\forget',
    'core\src\runtime',
    'core\src\runtime\scheduler',
    'core\src\runtime\resource',
    'core\src\runtime\budget',
    'core\src\runtime\recovery',
    'core\src\runtime\state',
    'core\src\runtime\residency',
    'core\src\runtime\observability',
    'core\src\model',
    'core\src\model\adapter',
    'core\src\model\probe',
    'core\src\model\profile',
    'core\src\model\escalation',
    'core\src\model\direct_native',
    'core\src\interfaces',
    'core\src\interfaces\ard',
    'core\src\interfaces\vtc',
    'core\src\interfaces\vsa',
    'core\src\interfaces\git',
    'core\src\interfaces\db',
    'core\src\interfaces\powershell',
    'core\src\interfaces\llm',
    'core\src\lineage',
    'core\src\authority',
    'core\src\extension',
    'protocol',
    'protocol\schemas',
    'protocol\frames',
    'protocol\contracts',
    'protocol\dictionaries',
    'transport',
    'transport\shared_memory',
    'transport\mmap',
    'transport\pipe',
    'transport\socket',
    'transport\quic',
    'transport\remote',
    'adapters',
    'adapters\models',
    'adapters\languages',
    'adapters\formats',
    'adapters\tools',
    'adapters\runtimes',
    'adapters\models\3_8b',
    'adapters\models\8b',
    'adapters\models\20b',
    'adapters\models\cloud',
    'adapters\languages\javascript',
    'adapters\languages\typescript',
    'adapters\languages\rust',
    'adapters\languages\python',
    'adapters\languages\sql',
    'adapters\languages\powershell',
    'adapters\formats\json',
    'adapters\formats\xml',
    'adapters\formats\yaml',
    'adapters\formats\toml',
    'memory',
    'memory\vmb',
    'memory\vsp',
    'memory\vcc',
    'memory\impact',
    'memory\indexes',
    'memory\canonical',
    'memory\candidate',
    'runtime',
    'runtime\profiles',
    'runtime\policies',
    'runtime\budgets',
    'runtime\recovery',
    'runtime\residency',
    'runtime\snapshots',
    'runtime\degraded',
    'experiments',
    'experiments\mission_0',
    'experiments\mission_0\raw_3_8b',
    'experiments\mission_0\vxn_3_8b',
    'experiments\mission_0\metrics',
    'experiments\mission_0\traces',
    'experiments\mission_0\results',
    'tests',
    'tests\native',
    'tests\transport',
    'tests\cognitive',
    'tests\memory',
    'tests\adapters',
    'tests\runtime',
    'tests\vtc',
    'tests\failure',
    'tests\load',
    'tests\compatibility',
    'observability',
    'observability\traces',
    'observability\metrics',
    'observability\events',
    'observability\profiles',
    'docs',
    'docs\architecture',
    'docs\protocol',
    'docs\runtime',
    'docs\memory',
    'docs\model_adapters',
    'docs\experiments',
    'docs\decisions',
    'docs\failures',
    'extensions',
    'extensions\registry',
    'extensions\providers',
    'extensions\experimental',
    '_reports',
    '_reports\foundation',
    '_reports\experiments',
    '_reports\failures',
    '_reports\compatibility'
)

foreach ($d in $dirs) {
    Ensure-Dir (Join-Path $VxnRoot $d)
}

# ---------------------------------------------------------------------
# 1. ROOT MANIFEST
# ---------------------------------------------------------------------

$manifest = [ordered]@{
    schema = 'vertex.vxn.foundation.manifest.v1'
    version = '0.0.1-foundation'
    run_id = $runId
    generated_at = (Get-Date).ToString('o')
    root = $VxnRoot

    identity = [ordered]@{
        name = 'Vertex Native'
        acronym = 'VXN'
        architecture = 'Hybrid Machine Cognitive Fabric'
        strategy = 'Maximum Viable Architecture'
        origin = 'AI/Machine-native high-density representation independent of human readability'
    }

    invariants = @(
        'VXN SHALL NOT DESTROY EXISTING TECHNOLOGY',
        'VXN SHALL ABSORB CONNECT AND ACCELERATE EXISTING TECHNOLOGY',
        'IMPACT IS ATTENTION NOT TRUTH',
        'COGNITION AUTHORITY IS SEPARATE FROM EXECUTION AUTHORITY',
        'VXN SHALL NOT REQUIRE AN LLM TO ABANDON ITS NATIVE BEHAVIOR',
        'MODEL ADAPTERS SHALL TRANSLATE BETWEEN VXN AND MODEL-NATIVE DIALECTS',
        'CANONICAL TRUTH SHALL BE EVIDENCE DRIVEN',
        'HUMAN LOCKED STATE SHALL NOT BE REINTERPRETED BY DEFAULT',
        'VTC SHALL GOVERN REALITY MUTATION',
        'AUDIT AND EXECUTION SHALL SHARE IDENTITY AND LINEAGE'
    )

    layers = [ordered]@{
        native = @('IR','Typed Identity','Frames','Codec','Dictionary','Schema','Binary Representation')
        transport = @('SharedMemory','MMAP','Pipe','Socket','QUIC','Remote')
        cognitive = @('Identity','Impact','Association','IndexOutIndex','Scope','Lock','Uncertainty','Routing')
        memory = @('VMB','VSP','VCC','Tiering','Candidate','Canonical')
        plasticity = @('Strengthen','Decay','Suppress','Protect','Rehabilitate','Forget')
        runtime = @('Scheduler','ResourceGovernor','BudgetController','RecoverySupervisor','StateCoordinator','ModelResidency','Observability')
        model = @('CapabilityProbe','ModelProfile','DialectAdapter','Escalation','DirectNative')
        action = @('ARD Interface','VTC Interface','Tool Interfaces','Lineage','Authority')
        extension = @('CapabilityRegistry','ProviderRegistry','VersionedContracts','ExperimentalPorts')
    }

    existing_technology_policy = [ordered]@{
        preserve = @(
            'Rust','Tauri','JavaScript','TypeScript','Node.js','Python','SQL','PostgreSQL',
            'SQLite','PowerShell','Git','JSON','XML','YAML','TOML','Ollama','LM Studio',
            'Cloud LLM APIs','ARD','VTC','VCC','VSP','VMB'
        )
        approach = 'ENCODE_ADAPT_CONNECT_NOT_REPLACE'
    }

    safety = [ordered]@{
        phase = 'FOUNDATION'
        execution_authority = 'NONE'
        vtc_required_for_reality_mutation = $true
        project_scope_only = $true
    }
}

Write-JsonFile (Join-Path $VxnRoot 'VXN_MANIFEST.json') $manifest

# ---------------------------------------------------------------------
# 2. ARCHITECTURE PRINCIPLES
# ---------------------------------------------------------------------

$principles = @'
# VXN Architecture Principles

## Origin

VXN begins with one non-negotiable idea:

Human-readable representation is not a requirement for AI/Machine internal communication.

VXN therefore provides a typed, dense, machine-oriented representation and transport fabric
while preserving all existing technologies at system boundaries.

## Core Law

VXN SHALL NOT DESTROY EXISTING TECHNOLOGY.

VXN SHALL ABSORB, CONNECT, AND ACCELERATE IT.

## Truth and Attention

Impact is not truth.
Impact is attention probability / activation pressure.

Canonical truth must be resolved from evidence, identity, lineage, VSP/VCC state,
transaction receipts, or other authoritative sources.

## Model Compatibility

Existing LLMs are not required to understand raw VXN Native.

Each model may operate through:
1. Natural language adapter
2. Structured adapter
3. Compact VXN adapter
4. VXN native-compatible mode
5. Native VXN model

VXN adapts to the model before asking the model to adapt to VXN.

## Authority

VXN may observe, recall, route, infer, propose, and build candidate worlds.

VXN does not directly own canonical-world mutation.

Reality mutation must pass through VTC or another explicit authority boundary.

## Memory Roles

VCC = Why / History / Design DNA
VSP = What is true NOW
VMB = What is actively being considered NOW
Impact = What should attract attention NEXT

## Runtime Independence

VXN Runtime must remain alive even when:
- local LLM runtime fails
- cloud API is unavailable
- a model cannot be loaded
- PostgreSQL is temporarily unavailable
- individual agents crash

Capability may degrade.
The mother ship must not collapse.

## Plasticity

VXN changes its external cognitive pathways without requiring LLM weight updates.

Supported primitives:
- strengthen
- decay
- suppress
- protect
- rehabilitate
- forget

## Branching

Agents operate on candidate / working worlds.

Canonical state is immutable from agent perspective until merge/commit authority approves.

## Maximum Viable Architecture

The initial foundation intentionally contains more extension points than are immediately implemented.

Missing implementation is acceptable.
Missing architecture is not.
'@

Write-TextFile (Join-Path $VxnRoot 'docs\architecture\VXN_PRINCIPLES.md') $principles

# ---------------------------------------------------------------------
# 3. RUST WORKSPACE
# ---------------------------------------------------------------------

$cargoWorkspace = @'
[workspace]
resolver = "2"
members = [
    "core"
]

[workspace.package]
edition = "2021"
license = "UNLICENSED"
authors = ["Vertex"]

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync", "time"] }
tracing = "0.1"
uuid = { version = "1", features = ["v4", "serde"] }
bytes = "1"
dashmap = "6"
parking_lot = "0.12"
smallvec = "1"
bitflags = "2"
crc32fast = "1"
'@
Write-TextFile (Join-Path $VxnRoot 'Cargo.toml') $cargoWorkspace

$coreCargo = @'
[package]
name = "vxn-core"
version = "0.0.1"
edition = "2021"

[dependencies]
serde.workspace = true
serde_json.workspace = true
thiserror.workspace = true
tokio.workspace = true
tracing.workspace = true
uuid.workspace = true
bytes.workspace = true
dashmap.workspace = true
parking_lot.workspace = true
smallvec.workspace = true
bitflags.workspace = true
crc32fast.workspace = true

[features]
default = ["native", "fabric", "memory", "cognitive", "runtime", "model-adapters"]
native = []
fabric = []
memory = []
cognitive = []
runtime = []
model-adapters = []
direct-native-model = []
experimental = []
'@
Write-TextFile (Join-Path $VxnRoot 'core\Cargo.toml') $coreCargo

$libRs = @'
pub mod native;
pub mod fabric;
pub mod cognitive;
pub mod memory;
pub mod plasticity;
pub mod runtime;
pub mod model;
pub mod interfaces;
pub mod lineage;
pub mod authority;
pub mod extension;

pub const VXN_FOUNDATION_VERSION: &str = "0.0.1-foundation";
'@
Write-TextFile (Join-Path $VxnRoot 'core\src\lib.rs') $libRs

# ---------------------------------------------------------------------
# 4. RUST MODULE SKELETONS
# ---------------------------------------------------------------------

$moduleMap = @{
    'native\mod.rs' = @'
pub mod ir;
pub mod codec;
pub mod schema;
pub mod dictionary;
pub mod frame;
'@
    'native\ir\mod.rs' = @'
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct VxnId(pub Uuid);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum VxnValue {
    Null,
    Bool(bool),
    I64(i64),
    F64(f64),
    Utf8(String),
    Bytes(Vec<u8>),
    Ref(VxnId),
    List(Vec<VxnValue>),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnOperation {
    pub op_code: u32,
    pub target: VxnId,
    pub property_code: Option<u32>,
    pub old_value: Option<VxnValue>,
    pub new_value: Option<VxnValue>,
    pub flags: u64,
}
'@
    'native\frame\mod.rs' = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnFrameHeader {
    pub protocol_version: u16,
    pub frame_type: u16,
    pub priority: u8,
    pub flags: u32,
    pub sequence: u64,
    pub payload_len: u32,
    pub crc32: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnFrame {
    pub header: VxnFrameHeader,
    pub payload: Vec<u8>,
}
'@
    'native\codec\mod.rs' = @'
pub trait VxnEncode<T> {
    fn encode(&self, value: &T) -> Result<Vec<u8>, String>;
}

pub trait VxnDecode<T> {
    fn decode(&self, bytes: &[u8]) -> Result<T, String>;
}
'@
    'native\schema\mod.rs' = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnSchemaVersion {
    pub major: u16,
    pub minor: u16,
    pub patch: u16,
}

pub trait VersionNegotiation {
    fn compatible_with(&self, other: &VxnSchemaVersion) -> bool;
}
'@
    'native\dictionary\mod.rs' = @'
use std::collections::HashMap;

#[derive(Default)]
pub struct VxnDictionary {
    pub symbols: HashMap<String, u32>,
    pub reverse: HashMap<u32, String>,
}
'@
    'fabric\mod.rs' = @'
pub mod event;
pub mod signal;
pub mod relation;
pub mod transport;
pub mod backpressure;
'@
    'fabric\signal\mod.rs' = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SignalKind {
    Native,
    Impact,
    Memory,
    Lock,
    State,
    Failure,
    Model,
    Tool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnSignal {
    pub kind: SignalKind,
    pub source: String,
    pub target: Option<String>,
    pub priority: f32,
    pub payload_ref: Option<String>,
}
'@
    'fabric\event\mod.rs' = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnEvent {
    pub event_id: String,
    pub kind: String,
    pub at_unix_ms: u64,
    pub source: String,
    pub data_ref: Option<String>,
}
'@
    'fabric\relation\mod.rs' = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelationEdge {
    pub from: String,
    pub to: String,
    pub relation_type: String,
    pub weight: f32,
    pub confidence: f32,
}
'@
    'fabric\transport\mod.rs' = @'
#[derive(Debug, Clone)]
pub enum TransportKind {
    SharedMemory,
    MemoryMappedFile,
    NamedPipe,
    Socket,
    Quic,
    Remote,
}

pub trait VxnTransport: Send + Sync {
    fn name(&self) -> &'static str;
    fn send(&self, frame: &[u8]) -> Result<(), String>;
    fn receive(&self) -> Result<Vec<u8>, String>;
}
'@
    'fabric\backpressure\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct BackpressureBudget {
    pub max_hops: u32,
    pub max_branches: u32,
    pub max_events: u64,
    pub max_time_ms: u64,
    pub max_memory_bytes: u64,
}
'@
    'cognitive\mod.rs' = @'
pub mod identity;
pub mod impact;
pub mod association;
pub mod scope;
pub mod lock;
pub mod uncertainty;
pub mod routing;
'@
    'cognitive\identity\mod.rs' = @'
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct CognitiveIdentity {
    pub namespace: String,
    pub id: String,
}
'@
    'cognitive\impact\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct ImpactValue {
    pub value: f64,
    pub protected: bool,
}

impl ImpactValue {
    pub fn clamp(&mut self) {
        self.value = self.value.clamp(0.0, 1.0);
    }
}

// IMPORTANT: Impact is attention pressure, not truth confidence.
'@
    'cognitive\association\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct ActivationPolicy {
    pub threshold: f32,
    pub hop_limit: u32,
    pub branch_limit: u32,
    pub time_budget_ms: u64,
}
'@
    'cognitive\scope\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct Scope {
    pub read_allow: Vec<String>,
    pub write_allow: Vec<String>,
    pub deny: Vec<String>,
}
'@
    'cognitive\lock\mod.rs' = @'
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockKind {
    Hard,
    Structure,
    Layout,
    Style,
    Behavior,
    FreezeRegion,
}

#[derive(Debug, Clone)]
pub struct LockRule {
    pub target: String,
    pub kind: LockKind,
    pub owner: String,
}
'@
    'cognitive\uncertainty\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct Uncertainty {
    pub confidence: f32,
    pub ambiguity: f32,
    pub novelty: f32,
    pub risk: f32,
}
'@
    'cognitive\routing\mod.rs' = @'
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CognitiveTier {
    Deterministic,
    Tier38B,
    Tier8B,
    Tier20B,
    CloudLarge,
    Human,
}

#[derive(Debug, Clone)]
pub struct RoutingDecision {
    pub tier: CognitiveTier,
    pub reason: String,
    pub estimated_cost: f64,
    pub estimated_latency_ms: u64,
}
'@
    'memory\mod.rs' = @'
pub mod vmb;
pub mod vsp;
pub mod vcc;
pub mod tiering;
pub mod candidate;
pub mod canonical;
'@
    'memory\vmb\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct WorkingMemoryItem {
    pub key: String,
    pub value_ref: String,
    pub activation: f32,
}
'@
    'memory\vsp\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct SavePoint {
    pub save_point_id: String,
    pub canonical_revision: String,
    pub mission_id: Option<String>,
    pub created_at: String,
}
'@
    'memory\vcc\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct ContinuityRecord {
    pub record_id: String,
    pub why: String,
    pub decision: String,
    pub evidence_refs: Vec<String>,
}
'@
    'memory\tiering\mod.rs' = @'
#[derive(Debug, Clone, Copy)]
pub enum MemoryTier {
    HotRam,
    WarmRam,
    PersistentDb,
    Archive,
}
'@
    'memory\candidate\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct CandidateWorld {
    pub candidate_id: String,
    pub parent_canonical_id: String,
    pub mutation_refs: Vec<String>,
}
'@
    'memory\canonical\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct CanonicalWorld {
    pub canonical_id: String,
    pub evidence_refs: Vec<String>,
    pub lineage_ref: Option<String>,
}
'@
    'plasticity\mod.rs' = @'
pub mod strengthen;
pub mod decay;
pub mod suppress;
pub mod protect;
pub mod rehabilitate;
pub mod forget;

#[derive(Debug, Clone, Copy)]
pub enum PlasticityAction {
    Strengthen,
    Decay,
    Suppress,
    Protect,
    Rehabilitate,
    Forget,
}
'@
    'plasticity\strengthen\mod.rs' = 'pub fn apply(value: f64, delta: f64) -> f64 { (value + delta).clamp(0.0, 1.0) }'
    'plasticity\decay\mod.rs' = 'pub fn apply(value: f64, delta: f64) -> f64 { (value - delta).clamp(0.0, 1.0) }'
    'plasticity\suppress\mod.rs' = 'pub fn apply(value: f64, factor: f64) -> f64 { (value * factor).clamp(0.0, 1.0) }'
    'plasticity\protect\mod.rs' = 'pub fn protected() -> bool { true }'
    'plasticity\rehabilitate\mod.rs' = 'pub fn apply(value: f64, delta: f64) -> f64 { (value + delta).clamp(0.0, 1.0) }'
    'plasticity\forget\mod.rs' = 'pub fn should_forget(value: f64, threshold: f64) -> bool { value < threshold }'
    'runtime\mod.rs' = @'
pub mod scheduler;
pub mod resource;
pub mod budget;
pub mod recovery;
pub mod state;
pub mod residency;
pub mod observability;
'@
    'runtime\scheduler\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct SchedulerPolicy {
    pub max_parallel_agents: usize,
    pub max_parallel_models: usize,
    pub event_loop_budget_ms: u64,
}
'@
    'runtime\resource\mod.rs' = @'
#[derive(Debug, Clone, Default)]
pub struct ResourceState {
    pub cpu_percent: f32,
    pub ram_used_bytes: u64,
    pub ram_total_bytes: u64,
    pub vram_used_bytes: u64,
    pub vram_total_bytes: u64,
}
'@
    'runtime\budget\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct CognitiveBudget {
    pub token_budget: u64,
    pub time_budget_ms: u64,
    pub branch_budget: u32,
    pub recall_budget: u32,
}
'@
    'runtime\recovery\mod.rs' = @'
#[derive(Debug, Clone, Copy)]
pub enum RecoveryAction {
    Retry,
    EscalateModel,
    DegradeCapability,
    Rollback,
    Hold,
    HumanGate,
}
'@
    'runtime\state\mod.rs' = @'
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeMode {
    Healthy,
    Degraded,
    ReadOnly,
    Recovery,
    Halted,
}
'@
    'runtime\residency\mod.rs' = @'
#[derive(Debug, Clone, Copy)]
pub enum Residency {
    Hot,
    Warm,
    Cold,
    Remote,
}

#[derive(Debug, Clone)]
pub struct ModelResidency {
    pub model_id: String,
    pub residency: Residency,
    pub vram_estimate_bytes: u64,
}
'@
    'runtime\observability\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct TracePoint {
    pub stage: String,
    pub latency_ms: u64,
    pub token_count: Option<u64>,
    pub model_id: Option<String>,
    pub impact_nodes: usize,
}
'@
    'model\mod.rs' = @'
pub mod adapter;
pub mod probe;
pub mod profile;
pub mod escalation;
pub mod direct_native;
'@
    'model\adapter\mod.rs' = @'
pub trait ModelAdapter: Send + Sync {
    fn model_id(&self) -> &str;
    fn encode_for_model(&self, vxn_payload: &[u8]) -> Result<String, String>;
    fn decode_from_model(&self, model_output: &str) -> Result<Vec<u8>, String>;
}
'@
    'model\probe\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct CapabilityProbeResult {
    pub typed_structure: f32,
    pub id_preservation: f32,
    pub schema_following: f32,
    pub compact_notation: f32,
    pub tool_contract: f32,
    pub unknown_syntax_tolerance: f32,
}
'@
    'model\profile\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct ModelDialectProfile {
    pub model_id: String,
    pub natural_language: f32,
    pub structured_text: f32,
    pub json: f32,
    pub compact_vxn: f32,
    pub native_vxn: f32,
}
'@
    'model\escalation\mod.rs' = @'
#[derive(Debug, Clone)]
pub struct EscalationPolicy {
    pub max_retries_per_tier: u32,
    pub allow_cloud: bool,
    pub require_human_for_high_risk: bool,
}
'@
    'model\direct_native\mod.rs' = @'
pub trait DirectNativeModel {
    fn accepts_vxn_native(&self) -> bool;
    fn protocol_version(&self) -> Option<String>;
}
'@
    'interfaces\mod.rs' = @'
pub mod ard;
pub mod vtc;
pub mod vsa;
pub mod git;
pub mod db;
pub mod powershell;
pub mod llm;
'@
    'interfaces\ard\mod.rs' = @'
pub trait ArdInterface {
    fn submit_mission(&self, mission_ref: &str) -> Result<String, String>;
}
'@
    'interfaces\vtc\mod.rs' = @'
pub trait VtcInterface {
    fn submit_candidate_transaction(&self, candidate_ref: &str) -> Result<String, String>;
    fn query_transaction_state(&self, transaction_id: &str) -> Result<String, String>;
}
'@
    'interfaces\vsa\mod.rs' = @'
pub trait VsaInterface {
    fn emit_observation(&self, observation_ref: &str) -> Result<(), String>;
    fn request_human_gate(&self, gate_ref: &str) -> Result<(), String>;
}
'@
    'interfaces\git\mod.rs' = 'pub trait GitInterface { fn diff(&self) -> Result<String, String>; }'
    'interfaces\db\mod.rs' = 'pub trait DbInterface { fn query(&self, request: &str) -> Result<String, String>; }'
    'interfaces\powershell\mod.rs' = 'pub trait PowerShellInterface { fn invoke_candidate(&self, ref_id: &str) -> Result<String, String>; }'
    'interfaces\llm\mod.rs' = 'pub trait LlmInterface { fn infer(&self, payload: &str) -> Result<String, String>; }'
    'lineage\mod.rs' = @'
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineageState {
    ActiveNonTerminal,
    CanonicalCommitted,
    SupersededByCommittedExecution,
    Rejected,
    RolledBack,
}
'@
    'authority\mod.rs' = @'
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Authority {
    Observe,
    Propose,
    CandidateWrite,
    HumanApprove,
    Execute,
    Commit,
}

pub const VXN_DEFAULT_AUTHORITY: Authority = Authority::Propose;
'@
    'extension\mod.rs' = @'
use std::collections::HashMap;

#[derive(Default)]
pub struct CapabilityRegistry {
    pub capabilities: HashMap<String, String>,
}

#[derive(Default)]
pub struct ProviderRegistry {
    pub providers: HashMap<String, String>,
}
'@
}

foreach ($rel in $moduleMap.Keys) {
    Write-TextFile (Join-Path $VxnRoot "core\src\$rel") $moduleMap[$rel]
}

# ---------------------------------------------------------------------
# 5. PROTOCOL SCHEMAS / CONTRACTS
# ---------------------------------------------------------------------

$frameSchema = [ordered]@{
    '$schema' = 'https://json-schema.org/draft/2020-12/schema'
    '$id' = 'vertex.vxn.frame.v1'
    title = 'VXN Frame'
    type = 'object'
    required = @('protocol_version','frame_type','sequence','payload')
    properties = [ordered]@{
        protocol_version = @{ type='string' }
        frame_type = @{ type='string' }
        priority = @{ type='number'; minimum=0; maximum=1 }
        flags = @{ type='array'; items=@{type='string'} }
        sequence = @{ type='integer'; minimum=0 }
        identity_refs = @{ type='array'; items=@{type='string'} }
        relation_refs = @{ type='array'; items=@{type='string'} }
        impact_refs = @{ type='array'; items=@{type='string'} }
        state_refs = @{ type='array'; items=@{type='string'} }
        payload = @{}
        checksum = @{ type=@('string','null') }
    }
}
Write-JsonFile (Join-Path $VxnRoot 'protocol\schemas\vxn-frame.schema.json') $frameSchema

$modelProfileSchema = [ordered]@{
    '$schema'='https://json-schema.org/draft/2020-12/schema'
    '$id'='vertex.vxn.model-profile.v1'
    title='VXN Model Dialect Profile'
    type='object'
    required=@('model_id','dialect_scores','capabilities')
    properties=[ordered]@{
        model_id=@{type='string'}
        dialect_scores=@{
            type='object'
            properties=[ordered]@{
                natural_language=@{type='number';minimum=0;maximum=1}
                structured_text=@{type='number';minimum=0;maximum=1}
                json=@{type='number';minimum=0;maximum=1}
                compact_vxn=@{type='number';minimum=0;maximum=1}
                native_vxn=@{type='number';minimum=0;maximum=1}
            }
        }
        capabilities=@{type='object'}
        runtime=@{type='object'}
    }
}
Write-JsonFile (Join-Path $VxnRoot 'protocol\schemas\model-profile.schema.json') $modelProfileSchema

$impactSchema = [ordered]@{
    '$schema'='https://json-schema.org/draft/2020-12/schema'
    '$id'='vertex.vxn.impact-node.v1'
    title='VXN Impact Node'
    type='object'
    required=@('id','impact','truth_authority')
    properties=[ordered]@{
        id=@{type='string'}
        impact=@{type='number';minimum=0;maximum=1}
        truth_authority=@{enum=@('NONE','EVIDENCE','CANONICAL','HUMAN','VTC')}
        protected=@{type='boolean'}
        suppressed=@{type='boolean'}
        last_activated_at=@{type=@('string','null')}
        relation_refs=@{type='array';items=@{type='string'}}
    }
}
Write-JsonFile (Join-Path $VxnRoot 'protocol\schemas\impact-node.schema.json') $impactSchema

$contracts = [ordered]@{
    schema='vertex.vxn.contract-registry.v1'
    contracts=@(
        @{
            id='VXN-NATIVE-FRAME'
            version='1'
            producer='ANY'
            consumer='ANY'
            guarantee='Typed machine-native transport envelope'
        },
        @{
            id='VXN-MODEL-ADAPTER'
            version='1'
            producer='VXN'
            consumer='MODEL'
            guarantee='Model-native dialect adaptation; raw native not mandatory'
        },
        @{
            id='VXN-CANDIDATE-WORLD'
            version='1'
            producer='VXN/ARD/LLM'
            consumer='VTC'
            guarantee='No canonical mutation before authority gate'
        },
        @{
            id='VXN-VTC-HANDOFF'
            version='1'
            producer='VXN'
            consumer='VTC'
            guarantee='Reality mutation delegated to transaction authority'
        },
        @{
            id='VXN-MEMORY-ROLES'
            version='1'
            guarantee='VCC=WHY; VSP=NOW; VMB=ACTIVE; Impact=NEXT_ATTENTION'
        }
    )
}
Write-JsonFile (Join-Path $VxnRoot 'protocol\contracts\VXN_CONTRACT_REGISTRY.json') $contracts

# ---------------------------------------------------------------------
# 6. DEFAULT RUNTIME POLICY
# ---------------------------------------------------------------------

$runtimePolicy = [ordered]@{
    schema='vertex.vxn.runtime-policy.v1'
    version='0.0.1'
    mode='EXPERIMENTAL_SIDECAR'
    execution_authority='NONE'

    cognition=[ordered]@{
        deterministic_first=$true
        allow_model_escalation=$true
        tiers=@('DETERMINISTIC','3.8B','8B','20B','CLOUD_LARGE','HUMAN')
        avoid_llm_when_known_transform=$true
    }

    association=[ordered]@{
        activation_threshold=0.35
        hop_limit=5
        branch_limit=16
        time_budget_ms=250
        recall_budget=64
        suppress_overactivation=$true
    }

    memory=[ordered]@{
        hot=@('ACTIVE_VMB','ACTIVE_VSP','HOT_IMPACT_INDEX')
        warm=@('VCC_CACHE','RECENT_CANONICAL')
        persistent=@('POSTGRESQL','SQLITE')
        archive=@('COLD_HISTORY')
    }

    model_residency=[ordered]@{
        strategy='RESOURCE_AWARE'
        preferred=@(
            @{ tier='3.8B'; residency='HOT_OPTIONAL' },
            @{ tier='8B'; residency='WARM' },
            @{ tier='20B'; residency='COLD_ON_DEMAND' },
            @{ tier='CLOUD_LARGE'; residency='REMOTE' }
        )
    }

    authority=[ordered]@{
        vxn=@('OBSERVE','RECALL','ROUTE','PROPOSE','CANDIDATE')
        vtc=@('SNAPSHOT','EXECUTE','VERIFY','COMMIT','ROLLBACK')
        human=@('LOCK','APPROVE','REJECT','OVERRIDE')
    }

    failure=[ordered]@{
        model_timeout='ESCALATE_OR_HOLD'
        model_freeze='CANCEL_AND_RETRY'
        adapter_failure='FALLBACK_DIALECT'
        db_unavailable='DEGRADED_MEMORY_MODE'
        vram_pressure='RESIDENCY_EVICTION'
        cloud_unavailable='LOCAL_FALLBACK'
        conflicting_candidate='BRANCH_AND_REVIEW'
        lock_violation='REJECT_CANDIDATE'
        uncertain_high_risk='HUMAN_GATE'
    }
}
Write-JsonFile (Join-Path $VxnRoot 'runtime\policies\VXN_RUNTIME_POLICY.json') $runtimePolicy

# ---------------------------------------------------------------------
# 7. MODEL PROBE / DIALECT PROFILES
# ---------------------------------------------------------------------

$probePlan = [ordered]@{
    schema='vertex.vxn.model-capability-probe-plan.v1'
    probes=@(
        'natural_language_following',
        'structured_text_following',
        'json_schema_following',
        'typed_id_preservation',
        'unknown_syntax_behavior',
        'compact_notation_tolerance',
        'tool_contract_following',
        'candidate_world_discipline',
        'lock_respect',
        'scope_respect',
        'self_report_vs_observed_behavior',
        'timeout_behavior',
        'retry_behavior'
    )
    outputs=@(
        'dialect_profile',
        'compatibility_level',
        'recommended_adapter',
        'risk_flags'
    )
}
Write-JsonFile (Join-Path $VxnRoot 'adapters\models\MODEL_CAPABILITY_PROBE_PLAN.json') $probePlan

$profiles = @{
    '3_8b' = @{ model_id='3.8B-UNRESOLVED'; level='PROBE_REQUIRED'; preferred_adapter='STRUCTURED_TEXT'; native_vxn='UNKNOWN' }
    '8b'   = @{ model_id='8B-UNRESOLVED'; level='PROBE_REQUIRED'; preferred_adapter='STRUCTURED_TEXT'; native_vxn='UNKNOWN' }
    '20b'  = @{ model_id='20B-UNRESOLVED'; level='PROBE_REQUIRED'; preferred_adapter='JSON_OR_STRUCTURED'; native_vxn='UNKNOWN' }
    'cloud'= @{ model_id='CLOUD-UNRESOLVED'; level='PROBE_REQUIRED'; preferred_adapter='PROVIDER_SPECIFIC'; native_vxn='UNKNOWN' }
}
foreach ($k in $profiles.Keys) {
    Write-JsonFile (Join-Path $VxnRoot "adapters\models\$k\profile.placeholder.json") $profiles[$k]
}

# ---------------------------------------------------------------------
# 8. LANGUAGE / FORMAT ADAPTER REGISTRY
# ---------------------------------------------------------------------

$adapterRegistry = [ordered]@{
    schema='vertex.vxn.adapter-registry.v1'
    languages=@(
        @{id='javascript'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='typescript'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='rust'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='python'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='sql'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='powershell'; direction='BIDIRECTIONAL'; status='PLANNED'}
    )
    formats=@(
        @{id='json'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='xml'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='yaml'; direction='BIDIRECTIONAL'; status='PLANNED'},
        @{id='toml'; direction='BIDIRECTIONAL'; status='PLANNED'}
    )
    model_levels=@(
        @{level=0; name='NATURAL_LANGUAGE_ADAPTER'},
        @{level=1; name='STRUCTURED_ADAPTER'},
        @{level=2; name='COMPACT_VXN_ADAPTER'},
        @{level=3; name='VXN_NATIVE_COMPATIBLE'},
        @{level=4; name='VXN_NATIVE_MODEL'}
    )
}
Write-JsonFile (Join-Path $VxnRoot 'adapters\ADAPTER_REGISTRY.json') $adapterRegistry

# ---------------------------------------------------------------------
# 9. EXPERIMENT MISSION 0
# ---------------------------------------------------------------------

$mission0 = [ordered]@{
    schema='vertex.vxn.experiment.mission0.v1'
    name='VXN Cognitive Amplification Experiment'
    objective='Measure whether external VXN cognition improves the effective capability of the same small model without weight changes.'
    model='3.8B'
    variants=@(
        'A_RAW_3_8B',
        'B_3_8B_PLUS_RAG',
        'C_3_8B_PLUS_VCC_VSP',
        'D_3_8B_PLUS_IMPACT_ASSOCIATION',
        'E_3_8B_PLUS_LOCK_SCOPE',
        'F_3_8B_PLUS_CANDIDATE_VTC',
        'G_3_8B_PLUS_FULL_VXN'
    )
    metrics=@(
        'mission_success',
        'human_interventions',
        'wrong_path_branches',
        'lock_violations',
        'scope_violations',
        'rollback_count',
        'llm_call_count',
        'input_tokens',
        'output_tokens',
        'relevant_context_ratio',
        'latency_ms',
        'vram_peak_bytes',
        'ram_peak_bytes',
        'recall_nodes',
        'impact_activations',
        'candidate_rejections',
        'canonical_commits'
    )
    rules=@(
        'SAME_MODEL_WEIGHTS',
        'SAME_MISSION',
        'SAME_BASE_REPOSITORY_STATE',
        'NO_DIRECT_EXECUTION_AUTHORITY_FOR_VXN',
        'ALL_MUTATIONS_CANDIDATE_ONLY'
    )
}
Write-JsonFile (Join-Path $VxnRoot 'experiments\mission_0\MISSION_0.json') $mission0

# ---------------------------------------------------------------------
# 10. FAILURE MATRIX
# ---------------------------------------------------------------------

$failureMatrix = [ordered]@{
    schema='vertex.vxn.failure-matrix.v1'
    scenarios=@(
        @{id='MODEL_TIMEOUT'; expected='ESCALATE_OR_HOLD'},
        @{id='MODEL_FREEZE'; expected='CANCEL_RETRY_OR_ESCALATE'},
        @{id='MODEL_OUTPUT_SCHEMA_DRIFT'; expected='ADAPTER_REPAIR_OR_REJECT'},
        @{id='MODEL_REFUSES_COMPACT_DIALECT'; expected='FALLBACK_TO_STRUCTURED'},
        @{id='MODEL_HALLUCINATES_IDENTITY'; expected='IDENTITY_GATE_REJECT'},
        @{id='VXN_NATIVE_VERSION_MISMATCH'; expected='NEGOTIATE_OR_FALLBACK'},
        @{id='IMPACT_OVERACTIVATION'; expected='SUPPRESS_AND_BUDGET_LIMIT'},
        @{id='IMPACT_WRONG_ASSOCIATION'; expected='CANONICAL_EVIDENCE_OVERRIDE'},
        @{id='POSTGRESQL_OUTAGE'; expected='DEGRADED_MEMORY_MODE'},
        @{id='VMB_STALE_STATE'; expected='VSP_CANONICAL_REVALIDATION'},
        @{id='VRAM_PRESSURE'; expected='MODEL_RESIDENCY_EVICTION'},
        @{id='AGENT_WRITE_CONFLICT'; expected='BRANCH_AND_REVIEW'},
        @{id='LOCK_VIOLATION'; expected='CANDIDATE_REJECT'},
        @{id='VTC_REJECT'; expected='NO_REALITY_MUTATION'},
        @{id='POWERSHELL_ERROR'; expected='VTC_ROLLBACK_AND_RECEIPT'},
        @{id='CLOUD_API_TIMEOUT'; expected='LOCAL_FALLBACK_OR_HOLD'},
        @{id='NETWORK_PARTITION'; expected='LOCAL_FIRST_DEGRADED_MODE'},
        @{id='PROCESS_CRASH'; expected='RECOVERY_FROM_SNAPSHOT'},
        @{id='PARTIAL_FRAME'; expected='REASSEMBLY_OR_REJECT'},
        @{id='CRC_FAILURE'; expected='DROP_FRAME'},
        @{id='BACKPRESSURE_OVERFLOW'; expected='THROTTLE_OR_DROP_LOW_PRIORITY'}
    )
}
Write-JsonFile (Join-Path $VxnRoot 'tests\failure\FAILURE_MATRIX.json') $failureMatrix

# ---------------------------------------------------------------------
# 11. OBSERVABILITY METRICS
# ---------------------------------------------------------------------

$metrics = [ordered]@{
    schema='vertex.vxn.observability.metrics.v1'
    counters=@(
        'vxn.frames.total',
        'vxn.frames.rejected',
        'vxn.signals.total',
        'vxn.activation.total',
        'vxn.activation.suppressed',
        'vxn.recall.total',
        'vxn.model.calls',
        'vxn.model.escalations',
        'vxn.model.fallbacks',
        'vxn.adapter.failures',
        'vxn.lock.violations',
        'vxn.scope.violations',
        'vxn.candidate.created',
        'vxn.candidate.rejected',
        'vxn.vtc.submitted',
        'vxn.vtc.committed',
        'vxn.vtc.rolled_back'
    )
    gauges=@(
        'vxn.vmb.active_items',
        'vxn.impact.hot_nodes',
        'vxn.runtime.ram_bytes',
        'vxn.runtime.vram_bytes',
        'vxn.runtime.cpu_percent',
        'vxn.context.relevant_ratio',
        'vxn.reasoning.avoidance_ratio'
    )
    histograms=@(
        'vxn.latency.encode_ms',
        'vxn.latency.route_ms',
        'vxn.latency.recall_ms',
        'vxn.latency.model_ms',
        'vxn.latency.total_ms'
    )
}
Write-JsonFile (Join-Path $VxnRoot 'observability\metrics\METRICS_REGISTRY.json') $metrics

# ---------------------------------------------------------------------
# 12. EXTENSION REGISTRY
# ---------------------------------------------------------------------

$extensionRegistry = [ordered]@{
    schema='vertex.vxn.extension-registry.v1'
    capability_ports=@(
        'NATIVE_CODEC',
        'TRANSPORT',
        'MODEL_ADAPTER',
        'MEMORY_PROVIDER',
        'IMPACT_ENGINE',
        'ASSOCIATION_ENGINE',
        'RUNTIME_SCHEDULER',
        'RESOURCE_PROVIDER',
        'VTC_PROVIDER',
        'ARD_PROVIDER',
        'OBSERVABILITY_SINK',
        'LANGUAGE_ADAPTER',
        'FORMAT_ADAPTER',
        'VXN_NATIVE_MODEL',
        'EXPERIMENTAL'
    )
    version_policy='VERSIONED_CONTRACT_REQUIRED'
    unknown_future_organs='ALLOWED_BY_DESIGN'
}
Write-JsonFile (Join-Path $VxnRoot 'extensions\registry\EXTENSION_REGISTRY.json') $extensionRegistry

# ---------------------------------------------------------------------
# 13. README
# ---------------------------------------------------------------------

$readme = @'
# Vertex Native (VXN)

This directory is the experimental VXN sidecar.

It is intentionally large.

It does not replace VSA.
It does not replace Rust, PowerShell, Git, SQL, JSON, local LLMs, or cloud LLMs.

VXN is the machine-native fabric connecting them.

## Current phase

Foundation only.

Execution authority: NONE.

The first experiment is Mission 0:
same 3.8B model, same mission, compare RAW vs progressively augmented VXN paths.

## Core concept

VXN Native is the internal machine-oriented representation.

VXN Fabric carries typed signals, relations, memory references, state references,
impact references, and candidate actions.

VXN Runtime schedules cognition and resources.

Model adapters preserve model individuality.

VTC remains the reality-mutation authority.

## First operational rule

Do not grant VXN direct mutation authority during early experiments.

Observe first.
Encode.
Recall.
Scope.
Route.
Generate candidate context.
Compare.
Measure.
Then expand.
'@
Write-TextFile (Join-Path $VxnRoot 'README.md') $readme

# ---------------------------------------------------------------------
# 14. FOUNDATION RECEIPT
# ---------------------------------------------------------------------

$receipt = [ordered]@{
    schema='vertex.vxn.foundation.receipt.v1'
    run_id=$runId
    generated_at=(Get-Date).ToString('o')
    mode=$Mode
    root=$VxnRoot
    force=[bool]$Force
    architecture='MAXIMUM_VIABLE_ARCHITECTURE'
    execution_authority='NONE'
    project_mutation_only=$true
    os_mutation=$false
    next_recommended=@(
        'cargo check',
        'validate JSON schemas',
        'run model capability probe',
        'implement Mission 0 harness',
        'connect VXN sidecar to VSA observation stream',
        'keep VTC as exclusive reality mutation gate'
    )
}

$receiptPath = Join-Path $VxnRoot "_reports\foundation\VXN_FOUNDATION_RECEIPT.$stamp.json"
Write-JsonFile $receiptPath $receipt

Write-Banner 'VXN MAXIMUM ARCHITECTURE FOUNDATION COMPLETE'
Write-Host "Root    : $VxnRoot"
Write-Host "Receipt : $receiptPath"
Write-Host "Mode    : $Mode"
Write-Host ''
Write-Host 'VXN EXECUTION AUTHORITY : NONE'
Write-Host 'VTC REALITY GATE        : REQUIRED'
Write-Host 'EXISTING VSA            : PRESERVED'
Write-Host 'EXISTING TECHNOLOGY     : PRESERVED'
Write-Host ''
Write-Host 'NEXT'
Write-Host "  cd `"$VxnRoot`""
Write-Host '  cargo check'
Write-Host ''
Write-Host '轟。' -ForegroundColor Green
