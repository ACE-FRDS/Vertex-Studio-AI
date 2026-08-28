#requires -Version 7.0
<#
VERTEX VXN — ADAPTIVE RUNTIME CORE
V0.1.0
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'G:\Vertex_Project\Vertex_Studio_AI',
    [string]$VxnRoot = '',
    [ValidateSet('Build','Plan')]
    [string]$Mode = 'Build',
    [switch]$Force,
    [switch]$SkipCargoCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VxnRoot)) {
    $VxnRoot = Join-Path $ProjectRoot 'VXN'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "VXN-ADAPTIVE-$stamp"

function Banner([string]$Text) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " $Text" -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
}

function Ensure-Dir([string]$Path) {
    if ($Mode -eq 'Plan') {
        Write-Host "PLAN  DIR  $Path"
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
        Write-Host "CREATE DIR  $Path" -ForegroundColor Green
    } else {
        Write-Host "KEEP   DIR  $Path"
    }
}

function Write-Text([string]$Path, [string]$Content) {
    if ($Mode -eq 'Plan') {
        Write-Host "PLAN  FILE $Path"
        return
    }
    $parent = Split-Path -Parent $Path
    if ($parent) { Ensure-Dir $parent }
    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        Write-Host "KEEP   FILE $Path" -ForegroundColor Yellow
        return
    }
    $Content | Set-Content -LiteralPath $Path -Encoding UTF8
    Write-Host "WRITE  FILE $Path" -ForegroundColor Green
}

function Write-Json([string]$Path, $Object) {
    Write-Text -Path $Path -Content ($Object | ConvertTo-Json -Depth 100)
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return $null }
}

function Find-LatestExperimentReport {
    $root = Join-Path $VxnRoot 'experiments\automation'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    return Get-ChildItem -LiteralPath $root -Filter 'VXN_EXPERIMENT_REPORT.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

Banner 'VERTEX VXN — ADAPTIVE RUNTIME CORE V0.1.0'
Write-Host "Run ID      : $runId"
Write-Host "Project Root: $ProjectRoot"
Write-Host "VXN Root    : $VxnRoot"
Write-Host "Mode        : $Mode"
Write-Host "Force       : $Force"

if (-not (Test-Path -LiteralPath (Join-Path $VxnRoot 'VXN_MANIFEST.json'))) {
    throw "VXN foundation not found: $VxnRoot"
}

Write-Host ''
Write-Host '[1/8] ADAPTIVE RUNTIME DIRECTORIES'

$dirs = @(
    'core\src\runtime\adaptive',
    'core\src\runtime\adaptive\observer',
    'core\src\runtime\adaptive\composer',
    'core\src\runtime\adaptive\escalation',
    'core\src\runtime\adaptive\toolbox',
    'core\src\runtime\adaptive\evidence',
    'runtime\adaptive',
    'runtime\adaptive\policies',
    'runtime\adaptive\profiles',
    'runtime\adaptive\toolboxes',
    'runtime\adaptive\evidence',
    'runtime\adaptive\decisions',
    'runtime\adaptive\receipts',
    'observability\runtime_observer',
    'extensions\adaptive_runtime'
)
foreach ($d in $dirs) { Ensure-Dir (Join-Path $VxnRoot $d) }

Write-Host ''
Write-Host '[2/8] POLICY'

$policy = [ordered]@{
    schema='vertex.vxn.adaptive-runtime-policy.v1'
    version='0.1.0'
    principle=[ordered]@{
        variable_means=@(
            'CAPACITY',
            'TOOLBOX_COMPOSITION',
            'MEMORY_DEPTH',
            'MODEL',
            'MODEL_TIER',
            'GUARD_SET',
            'TRANSPORT_ROUTE',
            'MID_MISSION_HOT_SWAP'
        )
        full_vxn_is_not_default=$true
        minimum_effective_runtime='PREFERRED'
        evidence_driven_composition=$true
    }
    runtime_boundary=[ordered]@{
        start='LIGHTEST_PROVEN_CONFIGURATION'
        expand_on=@(
            'LOW_CONFIDENCE','SCHEMA_FAILURE','LOCK_SCOPE_FAILURE',
            'MISSING_MEMORY_EVIDENCE','HIGH_RISK','RETRY_THRESHOLD','MODEL_CAPABILITY_GAP'
        )
        shrink_on=@(
            'REDUNDANT_COMPONENT','NO_ACCURACY_GAIN','PROMPT_BLOAT',
            'LATENCY_REGRESSION','RESOURCE_PRESSURE'
        )
    }
    authority=[ordered]@{
        adaptive_runtime=@(
            'OBSERVE','SELECT','ATTACH','DETACH','ROUTE',
            'ESCALATE_MODEL','DEESCALATE_MODEL','PROPOSE_NEW_COMPONENT'
        )
        forbidden=@('DIRECT_CANONICAL_MUTATION','DIRECT_VTC_EXECUTION','UNSCOPED_OS_MUTATION')
    }
}
Write-Json (Join-Path $VxnRoot 'runtime\adaptive\policies\VXN_ADAPTIVE_RUNTIME_POLICY.json') $policy

Write-Host ''
Write-Host '[3/8] TOOLBOX REGISTRY'

$toolboxes = [ordered]@{
    schema='vertex.vxn.toolbox-registry.v1'
    version='0.1.0'
    components=@(
        @{id='RAW'; class='BASE'; capabilities=@('MODEL_ONLY'); weight=0},
        @{id='LOCK_SCOPE'; class='GUARD'; capabilities=@('LOCK_AWARENESS','SCOPE_REDUCTION','HUMAN_CONSTRAINT_PRESERVATION'); weight=1},
        @{id='IMPACT_ASSOCIATION'; class='COGNITIVE'; capabilities=@('ATTENTION_ROUTING','ASSOCIATIVE_RECALL'); weight=2},
        @{id='VCC_VSP'; class='MEMORY'; capabilities=@('HISTORY_RECALL','CURRENT_STATE','DESIGN_DNA'); weight=3},
        @{id='RAG'; class='KNOWLEDGE'; capabilities=@('DOCUMENT_RETRIEVAL','REFERENCE_INJECTION'); weight=3},
        @{id='CANDIDATE_VTC'; class='AUTHORITY'; capabilities=@('CANDIDATE_WORLD','TRANSACTION_BOUNDARY','ROLLBACK_DISCIPLINE','HUMAN_GATE'); weight=2},
        @{id='FULL_VXN'; class='COMPOSITE'; capabilities=@('LOCK_SCOPE','IMPACT_ASSOCIATION','VCC_VSP','RAG','CANDIDATE_VTC'); weight=8}
    )
    hot_swap=[ordered]@{
        enabled=$true
        detach_when_unused=$true
        attach_mid_mission=$true
        evidence_receipt_required=$true
    }
}
Write-Json (Join-Path $VxnRoot 'runtime\adaptive\toolboxes\VXN_TOOLBOX_REGISTRY.json') $toolboxes

Write-Host ''
Write-Host '[4/8] MODEL ESCALATION'

$modelPolicy = [ordered]@{
    schema='vertex.vxn.model-escalation-policy.v1'
    version='0.1.0'
    tiers=@(
        @{tier=0; class='DETERMINISTIC'; examples=@('Rust','KnownTransform','IndexFilter')},
        @{tier=1; class='SMALL_3B_4B'; examples=@('3B','4B')},
        @{tier=2; class='MEDIUM_8B'; examples=@('8B')},
        @{tier=3; class='MEDIUM_12B'; examples=@('12B')},
        @{tier=4; class='LARGE_30B'; examples=@('30B','32B')},
        @{tier=5; class='CLOUD_LARGE'; examples=@('ProviderLarge')},
        @{tier=6; class='HUMAN'; examples=@('HumanGate')}
    )
    escalation=[ordered]@{
        triggers=@(
            'REPEATED_SCHEMA_FAILURE','REPEATED_RUNTIME_BOUNDARY_EXPANSION',
            'LOW_CONFIDENCE','HIGH_RISK','REVIEW_REJECTION','MISSION_TIMEOUT','CAPABILITY_GAP'
        )
        max_step=1
        skip_tier_only_when='HARD_CAPABILITY_REQUIREMENT'
    }
    deescalation=[ordered]@{
        enabled=$true
        triggers=@('PROVEN_SMALLER_MODEL_CONFIGURATION','LOW_RISK_SUBTASK','DETERMINISTIC_SUBTASK','RESOURCE_PRESSURE')
    }
}
Write-Json (Join-Path $VxnRoot 'runtime\adaptive\policies\VXN_MODEL_ESCALATION_POLICY.json') $modelPolicy

Write-Host ''
Write-Host '[5/8] RUNTIME OBSERVER'

$observer = [ordered]@{
    schema='vertex.vxn.runtime-observer-registry.v1'
    version='0.1.0'
    sensors=@(
        'MODEL_ID','MODEL_CLASS','MISSION_CLASS','RUNTIME_VARIANT','TOOLBOX_COMPONENTS',
        'PROMPT_TOKENS','COMPLETION_TOKENS','TOKENS_PER_SECOND','LATENCY_MS',
        'CONTENT_CHARS','REASONING_CHARS','FINISH_REASON','JSON_VALID','SCHEMA_COMPLETENESS',
        'LOCK_AWARENESS','SCOPE_AWARENESS','AUTHORITY_AWARENESS','UNCERTAINTY_AWARENESS',
        'RETRY_COUNT','ROLLBACK_COUNT','HUMAN_INTERVENTION',
        'RAM_BYTES','VRAM_BYTES','CPU_PERCENT','GPU_UTILIZATION',
        'MODEL_LOAD_MS','MODEL_UNLOAD_MS','HOT_SWAP_COUNT'
    )
    diagnosis=@(
        'PROMPT_BLOAT','MODEL_TOO_SMALL','MODEL_TOO_LARGE','UNNEEDED_TOOLBOX_COMPONENT',
        'MISSING_TOOLBOX_COMPONENT','REASONING_LOOP','SCHEMA_DRIFT','LOCK_SCOPE_FAILURE',
        'AUTHORITY_FAILURE','MEMORY_RECALL_FAILURE','RESOURCE_PRESSURE'
    )
}
Write-Json (Join-Path $VxnRoot 'observability\runtime_observer\VXN_RUNTIME_OBSERVER_REGISTRY.json') $observer

Write-Host ''
Write-Host '[6/8] RUST MODULES'

$adaptiveMod = @'
pub mod observer;
pub mod composer;
pub mod escalation;
pub mod toolbox;
pub mod evidence;

pub use observer::*;
pub use composer::*;
pub use escalation::*;
pub use toolbox::*;
pub use evidence::*;
'@

$observerRs = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuntimeObservation {
    pub model_id: String,
    pub model_class: String,
    pub mission_class: String,
    pub runtime_variant: String,
    pub prompt_tokens: Option<u64>,
    pub completion_tokens: Option<u64>,
    pub tokens_per_second: Option<f64>,
    pub latency_ms: Option<u64>,
    pub json_valid: bool,
    pub schema_completeness: f64,
    pub lock_awareness: f64,
    pub scope_awareness: f64,
    pub authority_awareness: f64,
    pub uncertainty_awareness: f64,
    pub retry_count: u32,
    pub rollback_count: u32,
    pub hot_swap_count: u32,
    pub ram_bytes: Option<u64>,
    pub vram_bytes: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RuntimeDiagnosis {
    Healthy,
    PromptBloat,
    ModelTooSmall,
    ModelTooLarge,
    MissingToolboxComponent,
    UnneededToolboxComponent,
    ReasoningLoop,
    SchemaDrift,
    LockScopeFailure,
    AuthorityFailure,
    MemoryRecallFailure,
    ResourcePressure,
}
'@

$toolboxRs = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum ToolboxComponent {
    Raw,
    LockScope,
    ImpactAssociation,
    VccVsp,
    Rag,
    CandidateVtc,
    Custom(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeToolbox {
    pub components: Vec<ToolboxComponent>,
    pub hot_swap_enabled: bool,
}

impl RuntimeToolbox {
    pub fn minimal() -> Self {
        Self {
            components: vec![ToolboxComponent::Raw],
            hot_swap_enabled: true,
        }
    }

    pub fn contains(&self, component: &ToolboxComponent) -> bool {
        self.components.contains(component)
    }

    pub fn attach(&mut self, component: ToolboxComponent) {
        if !self.components.contains(&component) {
            self.components.push(component);
        }
    }

    pub fn detach(&mut self, component: &ToolboxComponent) {
        self.components.retain(|x| x != component);
    }
}
'@

$composerRs = @'
use serde::{Deserialize, Serialize};

use super::observer::{RuntimeDiagnosis, RuntimeObservation};
use super::toolbox::{RuntimeToolbox, ToolboxComponent};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeDecision {
    pub toolbox: RuntimeToolbox,
    pub model_tier_delta: i32,
    pub reason: Vec<String>,
}

pub struct RuntimeComposer;

impl RuntimeComposer {
    pub fn compose(
        observation: &RuntimeObservation,
        diagnosis: &[RuntimeDiagnosis],
        current: &RuntimeToolbox,
    ) -> RuntimeDecision {
        let mut next = current.clone();
        let mut tier_delta = 0;
        let mut reason = Vec::new();

        for d in diagnosis {
            match d {
                RuntimeDiagnosis::LockScopeFailure => {
                    next.attach(ToolboxComponent::LockScope);
                    reason.push("Attach LockScope guard.".into());
                }
                RuntimeDiagnosis::MemoryRecallFailure => {
                    next.attach(ToolboxComponent::VccVsp);
                    next.attach(ToolboxComponent::ImpactAssociation);
                    reason.push("Expand memory/association boundary.".into());
                }
                RuntimeDiagnosis::AuthorityFailure => {
                    next.attach(ToolboxComponent::CandidateVtc);
                    reason.push("Attach Candidate/VTC authority boundary.".into());
                }
                RuntimeDiagnosis::PromptBloat => {
                    next.detach(&ToolboxComponent::Rag);
                    reason.push("Detach RAG due to prompt bloat.".into());
                }
                RuntimeDiagnosis::ModelTooSmall => {
                    tier_delta = 1;
                    reason.push("Escalate one model tier.".into());
                }
                RuntimeDiagnosis::ModelTooLarge => {
                    tier_delta = -1;
                    reason.push("De-escalate one model tier.".into());
                }
                RuntimeDiagnosis::ResourcePressure => {
                    next.detach(&ToolboxComponent::Rag);
                    reason.push("Shrink toolbox under resource pressure.".into());
                }
                _ => {}
            }
        }

        if observation.schema_completeness >= 1.0
            && observation.lock_awareness >= 1.0
            && observation.scope_awareness >= 1.0
            && observation.authority_awareness >= 1.0
        {
            reason.push("Current runtime satisfies core reliability signals.".into());
        }

        RuntimeDecision {
            toolbox: next,
            model_tier_delta: tier_delta,
            reason,
        }
    }
}
'@

$escalationRs = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum ModelTier {
    Deterministic = 0,
    Small3B4B = 1,
    Medium8B = 2,
    Medium12B = 3,
    Large30B = 4,
    CloudLarge = 5,
    Human = 6,
}

impl ModelTier {
    pub fn shift(self, delta: i32) -> Self {
        let raw = (self as i32 + delta).clamp(0, 6);
        match raw {
            0 => ModelTier::Deterministic,
            1 => ModelTier::Small3B4B,
            2 => ModelTier::Medium8B,
            3 => ModelTier::Medium12B,
            4 => ModelTier::Large30B,
            5 => ModelTier::CloudLarge,
            _ => ModelTier::Human,
        }
    }
}
'@

$evidenceRs = @'
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeEvidence {
    pub model_class: String,
    pub mission_id: String,
    pub preferred_variant: String,
    pub samples: u64,
    pub prompt_tokens: Option<f64>,
    pub latency_ms: Option<f64>,
    pub tokens_per_second: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuntimeEvidenceStore {
    pub entries: Vec<RuntimeEvidence>,
}

impl RuntimeEvidenceStore {
    pub fn recommend(
        &self,
        model_class: &str,
        mission_id: &str,
    ) -> Option<&RuntimeEvidence> {
        self.entries
            .iter()
            .filter(|e| e.model_class == model_class && e.mission_id == mission_id)
            .max_by_key(|e| e.samples)
    }
}
'@

Write-Text (Join-Path $VxnRoot 'core\src\runtime\adaptive\mod.rs') $adaptiveMod
Write-Text (Join-Path $VxnRoot 'core\src\runtime\adaptive\observer\mod.rs') $observerRs
Write-Text (Join-Path $VxnRoot 'core\src\runtime\adaptive\toolbox\mod.rs') $toolboxRs
Write-Text (Join-Path $VxnRoot 'core\src\runtime\adaptive\composer\mod.rs') $composerRs
Write-Text (Join-Path $VxnRoot 'core\src\runtime\adaptive\escalation\mod.rs') $escalationRs
Write-Text (Join-Path $VxnRoot 'core\src\runtime\adaptive\evidence\mod.rs') $evidenceRs

$runtimeModPath = Join-Path $VxnRoot 'core\src\runtime\mod.rs'
if ($Mode -eq 'Build') {
    if (-not (Test-Path -LiteralPath $runtimeModPath)) {
        throw "Missing runtime module: $runtimeModPath"
    }
    $runtimeMod = Get-Content -LiteralPath $runtimeModPath -Raw -Encoding UTF8
    if ($runtimeMod -notmatch '(?m)^\s*pub\s+mod\s+adaptive\s*;') {
        Add-Content -LiteralPath $runtimeModPath -Value "`npub mod adaptive;" -Encoding UTF8
        Write-Host "PATCH  FILE $runtimeModPath" -ForegroundColor Green
    } else {
        Write-Host "KEEP   EXPORT adaptive"
    }
} else {
    Write-Host "PLAN  PATCH $runtimeModPath -> pub mod adaptive;"
}

Write-Host ''
Write-Host '[7/8] EXPERIMENT EVIDENCE INGESTION'

$latestReport = Find-LatestExperimentReport
$evidenceReceipt = [ordered]@{
    schema='vertex.vxn.adaptive-runtime-evidence-ingestion.v1'
    run_id=$runId
    source=$null
    status='NO_EXPERIMENT_REPORT'
    hints=@()
}

if ($null -ne $latestReport) {
    Write-Host "  Source : $($latestReport.FullName)"
    $report = Read-JsonSafe $latestReport.FullName
    if ($null -ne $report) {
        $hints = @()
        $hintProp = $report.PSObject.Properties['adaptive_runtime_hints']
        if ($null -ne $hintProp -and $null -ne $hintProp.Value) {
            foreach ($h in @($hintProp.Value)) {
                $hints += [ordered]@{
                    model_class = [string]$h.model_class
                    mission_id = [string]$h.mission_id
                    preferred_variant = [string]$h.preferred_variant
                    evidence_samples = $h.evidence_samples
                    prompt_tokens = $h.prompt_tokens
                    latency_ms = $h.latency_ms
                    tokens_per_sec = $h.tokens_per_sec
                }
            }
        }
        $evidenceReceipt.source = $latestReport.FullName
        $evidenceReceipt.status = 'INGESTED'
        $evidenceReceipt.hints = @($hints)

        Write-Json (Join-Path $VxnRoot 'runtime\adaptive\evidence\LATEST_ADAPTIVE_RUNTIME_HINTS.json') ([ordered]@{
            schema='vertex.vxn.adaptive-runtime-hints.v1'
            imported_at=(Get-Date).ToString('o')
            source=$latestReport.FullName
            hints=@($hints)
        })

        Write-Host "  Hints  : $($hints.Count)"
    } else {
        $evidenceReceipt.status = 'REPORT_PARSE_FAILED'
    }
} else {
    Write-Host '  No previous automation report found.'
}

Write-Json (Join-Path $VxnRoot 'runtime\adaptive\evidence\EVIDENCE_INGESTION_RECEIPT.json') $evidenceReceipt

Write-Host ''
Write-Host '[8/8] VALIDATE'

$adaptiveManifest = [ordered]@{
    schema='vertex.vxn.adaptive-runtime-core.manifest.v1'
    version='0.1.0'
    run_id=$runId
    generated_at=(Get-Date).ToString('o')
    organs=@(
        'RuntimeObserver',
        'RuntimeComposer',
        'ModelEscalation',
        'ToolboxHotSwap',
        'ExperimentEvidenceStore'
    )
    invariants=@(
        'FULL_VXN_IS_NOT_DEFAULT',
        'MINIMUM_EFFECTIVE_RUNTIME_IS_PREFERRED',
        'RUNTIME_MAY_CHANGE_MID_MISSION',
        'MODEL_MAY_ESCALATE_OR_DEESCALATE',
        'TOOLBOX_MAY_ATTACH_OR_DETACH_COMPONENTS',
        'OBSERVER_DATA_DRIVES_COMPOSITION',
        'VTC_REMAINS_REALITY_MUTATION_BOUNDARY'
    )
    evidence_status=$evidenceReceipt.status
    authority=[ordered]@{
        canonical_mutation='DENIED'
        vtc_execution='DENIED'
        project_runtime_composition='ALLOWED'
    }
}
Write-Json (Join-Path $VxnRoot 'runtime\adaptive\VXN_ADAPTIVE_RUNTIME_MANIFEST.json') $adaptiveManifest

$cargoStatus = 'SKIPPED'
if ($Mode -eq 'Build' -and -not $SkipCargoCheck) {
    Write-Host ''
    Write-Host '  cargo check...'
    Push-Location $VxnRoot
    try {
        & cargo check
        if ($LASTEXITCODE -eq 0) {
            $cargoStatus = 'GREEN'
            Write-Host '  CARGO : GREEN' -ForegroundColor Green
        } else {
            $cargoStatus = "FAILED_EXIT_$LASTEXITCODE"
            throw "cargo check failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

$receipt = [ordered]@{
    schema='vertex.vxn.adaptive-runtime-core.receipt.v1'
    run_id=$runId
    completed_at=(Get-Date).ToString('o')
    mode=$Mode
    cargo_check=$cargoStatus
    evidence=$evidenceReceipt.status
    installed=@(
        'RuntimeObserver','RuntimeComposer','ModelEscalation',
        'ToolboxRegistry','HotSwapContract','AdaptiveRuntimePolicy',
        'ExperimentEvidenceIngestion'
    )
    next=@(
        'Implement live Runtime Observer feed',
        'Connect Runtime Composer to Mission Harness',
        'Add 3B/4B/8B/12B/30B model registry',
        'Add live hot-swap decisions',
        'Then enable ARD parallel party experiments'
    )
}

$receiptPath = Join-Path $VxnRoot "runtime\adaptive\receipts\VXN_ADAPTIVE_RUNTIME_CORE.$stamp.json"
Write-Json $receiptPath $receipt

Banner 'VXN ADAPTIVE RUNTIME CORE COMPLETE'
Write-Host "Cargo       : $cargoStatus"
Write-Host "Evidence    : $($evidenceReceipt.status)"
Write-Host "Receipt     : $receiptPath"
Write-Host ''
Write-Host 'RUNTIME OBSERVER   : INSTALLED'
Write-Host 'RUNTIME COMPOSER   : INSTALLED'
Write-Host 'MODEL ESCALATION   : INSTALLED'
Write-Host 'TOOLBOX HOT-SWAP   : INSTALLED'
Write-Host ''
Write-Host 'CANONICAL MUTATION : DENIED'
Write-Host 'VTC EXECUTION      : DENIED'
Write-Host ''
Write-Host 'THE TOOLBOX CAN NOW CHANGE SHAPE.' -ForegroundColor Green
Write-Host '轟。' -ForegroundColor Green
