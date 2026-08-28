use anyhow::{anyhow, bail, Result};
use clap::{Parser, Subcommand, ValueEnum};
use std::path::{Path, PathBuf};
use uuid::Uuid;
use vertex_ard::{
    ArdAssignment, ArdEngine, ArdSession, ArdSessionState, BrainAssignment, CompleteArdStage,
    CreateArdMember, CreateArdTeam, HandoffDecision, HardPermission,
};
use vertex_brain::LmStudioClient;

#[derive(Debug, Parser)]
#[command(
    name = "vertex-ardctl",
    version,
    about = "Vertex ARD v2 - Relation Graph + Agent Relay Development"
)]
struct Cli {
    #[arg(long, default_value = "STATE/ard-v2.json")]
    state: PathBuf,

    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum DecisionArg {
    Accepted,
    Rework,
    Blocked,
}

impl From<DecisionArg> for HandoffDecision {
    fn from(value: DecisionArg) -> Self {
        match value {
            DecisionArg::Accepted => HandoffDecision::Accepted,
            DecisionArg::Rework => HandoffDecision::Rework,
            DecisionArg::Blocked => HandoffDecision::Blocked,
        }
    }
}

#[derive(Debug, Subcommand)]
enum Command {
    Doctor,

    ImportState {
        path: PathBuf,
    },

    ImportVur {
        path: PathBuf,
    },

    Impact {
        asset_id: String,

        #[arg(long, default_value_t = 8)]
        max_depth: usize,
    },

    DemoRelay {
        #[arg(long, default_value = "project://vertex-studio/mothership")]
        workspace: String,

        #[arg(long, default_value = "ARD v2 Genesis mission")]
        goal: String,
    },

    DemoRelayLocal {
        #[arg(long, default_value = "project://vertex-studio/mothership")]
        workspace: String,

        #[arg(long, default_value = "Vertex Local Brain Genesis")]
        goal: String,

        #[arg(long)]
        architect_model: Option<String>,

        #[arg(long)]
        developer_model: Option<String>,

        #[arg(long)]
        reviewer_model: Option<String>,
    },

    Assignment {
        session_id: Uuid,
    },

    CompleteStage {
        session_id: Uuid,

        #[arg(long, value_enum, default_value_t = DecisionArg::Accepted)]
        decision: DecisionArg,

        #[arg(long)]
        task_result: String,

        #[arg(long, default_value = "continue")]
        next_action: String,

        #[arg(long, default_value_t = 1.0)]
        confidence: f32,

        #[arg(long = "decision-note")]
        decisions: Vec<String>,

        #[arg(long = "file-read")]
        files_read: Vec<String>,

        #[arg(long = "file-changed")]
        files_changed: Vec<String>,

        #[arg(long = "test-run")]
        tests_run: Vec<String>,

        #[arg(long = "test-result")]
        test_results: Vec<String>,

        #[arg(long = "known-issue")]
        known_issues: Vec<String>,

        #[arg(long = "question")]
        unresolved_questions: Vec<String>,
    },

    Pause {
        session_id: Uuid,
    },

    Resume {
        session_id: Uuid,
    },

    Cancel {
        session_id: Uuid,
    },

    Intervene {
        session_id: Uuid,

        #[arg(long)]
        instruction: String,

        #[arg(long = "to")]
        delivered_to: Vec<Uuid>,
    },

    Session {
        session_id: Uuid,
    },

    LmDoctor,

    LmModels,

    LmSmoke {
        model: String,

        #[arg(long, default_value = "Reply with exactly: VERTEX_LOCAL_BRAIN_OK")]
        prompt: String,

        #[arg(long, default_value_t = 0.0)]
        temperature: f32,
    },

    ExecuteStage {
        session_id: Uuid,

        #[arg(long, default_value_t = 0.2)]
        temperature: f32,
    },

    RunRelay {
        session_id: Uuid,

        #[arg(long, default_value_t = 8)]
        max_steps: u32,

        #[arg(long, default_value_t = 0.2)]
        temperature: f32,
    },

    Export,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let mut engine = ArdEngine::open(&cli.state)?;

    match cli.command {
        Command::Doctor => {
            print_doctor(&engine, &cli.state);
        }

        Command::ImportState { path } => {
            let report = engine.import_mothership_state(&path)?;
            println!("{}", serde_json::to_string_pretty(&report)?);
        }

        Command::ImportVur { path } => {
            let report = engine.import_vur_registry(&path)?;
            println!("{}", serde_json::to_string_pretty(&report)?);
        }

        Command::Impact {
            asset_id,
            max_depth,
        } => {
            let impact = engine.impact(&asset_id, max_depth);
            println!("{}", serde_json::to_string_pretty(&impact)?);
        }

        Command::DemoRelay { workspace, goal } => {
            let team = engine.create_team(default_team(
                workspace,
                BrainAssignment::Auto,
                BrainAssignment::Auto,
                BrainAssignment::Auto,
            ))?;

            let workflow =
                engine.create_relay_workflow(team.id, "Architect -> Developer -> Reviewer")?;

            let session = engine.start_session(workflow.id, goal)?;
            let assignment = engine.current_assignment(session.id)?;

            println!("session_id={}", session.id);
            println!("{}", serde_json::to_string_pretty(&assignment)?);
        }

        Command::DemoRelayLocal {
            workspace,
            goal,
            architect_model,
            developer_model,
            reviewer_model,
        } => {
            let client = LmStudioClient::from_env()?;

            let model_ids = client
                .list_models()?
                .into_iter()
                .map(|model| model.id)
                .collect::<Vec<_>>();

            if model_ids.is_empty() {
                bail!("LM Studio returned zero models");
            }

            let architect = choose_model(
                &model_ids,
                architect_model,
                &["qwq-32b", "deepseek-r1-distill-qwen-14b", "qwen3.5-27b"],
                "Architect",
            )?;

            let developer = choose_model(
                &model_ids,
                developer_model,
                &["qwen3-coder-30b", "devstral-small-2-24b", "qwen3.5-27b"],
                "Developer",
            )?;

            let reviewer = choose_model(
                &model_ids,
                reviewer_model,
                &["gemma-4-31b", "gemma-4", "qwen3.5-27b"],
                "Reviewer",
            )?;

            println!("LM Studio: {}", client.base_url());
            println!("Architect: {architect}");
            println!("Developer: {developer}");
            println!("Reviewer : {reviewer}");

            let team = engine.create_team(default_team(
                workspace,
                lm_brain(&architect),
                lm_brain(&developer),
                lm_brain(&reviewer),
            ))?;

            let workflow = engine
                .create_relay_workflow(team.id, "Local Architect -> Developer -> Reviewer")?;

            let session = engine.start_session(workflow.id, goal)?;
            let assignment = engine.current_assignment(session.id)?;

            println!();
            println!("session_id={}", session.id);
            println!("current_role={}", assignment.member.role);
        }

        Command::Assignment { session_id } => {
            let assignment = engine.current_assignment(session_id)?;
            println!("{}", serde_json::to_string_pretty(&assignment)?);
        }

        Command::CompleteStage {
            session_id,
            decision,
            task_result,
            next_action,
            confidence,
            decisions,
            files_read,
            files_changed,
            tests_run,
            test_results,
            known_issues,
            unresolved_questions,
        } => {
            let session = engine.complete_stage(
                session_id,
                CompleteArdStage {
                    decision: decision.into(),
                    task_result,
                    decisions,
                    files_read,
                    files_changed,
                    tests_run,
                    test_results,
                    known_issues,
                    unresolved_questions,
                    next_action,
                    confidence,
                },
            )?;

            println!("{}", serde_json::to_string_pretty(&session)?);
        }

        Command::Pause { session_id } => {
            println!(
                "{}",
                serde_json::to_string_pretty(&engine.pause(session_id)?)?
            );
        }

        Command::Resume { session_id } => {
            println!(
                "{}",
                serde_json::to_string_pretty(&engine.resume(session_id)?)?
            );
        }

        Command::Cancel { session_id } => {
            println!(
                "{}",
                serde_json::to_string_pretty(&engine.cancel(session_id)?)?
            );
        }

        Command::Intervene {
            session_id,
            instruction,
            delivered_to,
        } => {
            println!(
                "{}",
                serde_json::to_string_pretty(&engine.intervene(
                    session_id,
                    instruction,
                    delivered_to
                )?)?
            );
        }

        Command::Session { session_id } => {
            let session = engine
                .document()
                .relay
                .sessions
                .get(&session_id)
                .ok_or_else(|| anyhow!("ARD session not found: {session_id}"))?;

            println!("{}", serde_json::to_string_pretty(session)?);
        }

        Command::LmDoctor => {
            let client = LmStudioClient::from_env()?;
            let models = client.list_models()?;

            println!("VERTEX LOCAL BRAIN");
            println!("provider : LM Studio");
            println!("base_url : {}", client.base_url());
            println!("models   : {}", models.len());
            println!("status   : ONLINE");
        }

        Command::LmModels => {
            let client = LmStudioClient::from_env()?;

            for model in client.list_models()? {
                println!("{}", model.id);
            }
        }

        Command::LmSmoke {
            model,
            prompt,
            temperature,
        } => {
            let client = LmStudioClient::from_env()?;

            let reply = client.chat(
                &model,
                "You are the Vertex Local Brain connectivity test.",
                &prompt,
                temperature,
            )?;

            println!("{reply}");
        }

        Command::ExecuteStage {
            session_id,
            temperature,
        } => {
            let client = LmStudioClient::from_env()?;

            let session = execute_stage(&mut engine, &client, session_id, temperature)?;

            println!("{}", serde_json::to_string_pretty(&session)?);
        }

        Command::RunRelay {
            session_id,
            max_steps,
            temperature,
        } => {
            let client = LmStudioClient::from_env()?;

            run_relay(&mut engine, &client, session_id, max_steps, temperature)?;
        }

        Command::Export => {
            println!("{}", serde_json::to_string_pretty(engine.document())?);
        }
    }

    Ok(())
}

fn print_doctor(engine: &ArdEngine, state: &Path) {
    let doc = engine.document();

    println!("VERTEX ARD v2");
    println!("schema   : {}", doc.schema);
    println!("version  : {}", doc.version);
    println!("state    : {}", state.display());
    println!("nodes    : {}", doc.graph.nodes.len());
    println!("edges    : {}", doc.graph.edges.len());
    println!("teams    : {}", doc.relay.teams.len());
    println!("workflows: {}", doc.relay.workflows.len());
    println!("sessions : {}", doc.relay.sessions.len());
}

fn lm_brain(model_id: &str) -> BrainAssignment {
    BrainAssignment::Model {
        provider_id: "lmstudio".to_owned(),
        model_id: model_id.to_owned(),
        runtime_id: Some("lmstudio-local".to_owned()),
    }
}

fn default_team(
    workspace: String,
    architect_brain: BrainAssignment,
    developer_brain: BrainAssignment,
    reviewer_brain: BrainAssignment,
) -> CreateArdTeam {
    CreateArdTeam {
        name: "Vertex ARD Genesis Team".to_owned(),
        workspace_id: workspace,
        members: vec![
            CreateArdMember {
                name: "Architect".to_owned(),
                role: "Architect".to_owned(),
                brain: architect_brain,
                permission: HardPermission::read_only(),
                responsibilities: vec![
                    "Query ARD impact graph".to_owned(),
                    "Define implementation boundaries".to_owned(),
                    "Preserve Vertex CANON".to_owned(),
                ],
                forbidden_actions: vec!["Direct real repository write".to_owned()],
            },
            CreateArdMember {
                name: "Developer".to_owned(),
                role: "Developer".to_owned(),
                brain: developer_brain,
                permission: HardPermission::developer_vve(),
                responsibilities: vec![
                    "Implement changes in VVE".to_owned(),
                    "Run build and tests".to_owned(),
                ],
                forbidden_actions: vec!["Bypass VVE".to_owned(), "Bypass Human Gate".to_owned()],
            },
            CreateArdMember {
                name: "Reviewer".to_owned(),
                role: "Reviewer".to_owned(),
                brain: reviewer_brain,
                permission: HardPermission::reviewer(),
                responsibilities: vec![
                    "Review changes".to_owned(),
                    "Verify tests and evidence".to_owned(),
                ],
                forbidden_actions: vec!["Promote without owner approval".to_owned()],
            },
        ],
    }
}

fn choose_model(
    available: &[String],
    explicit: Option<String>,
    preferred_patterns: &[&str],
    role: &str,
) -> Result<String> {
    if let Some(explicit) = explicit {
        if available.iter().any(|model| model == &explicit) {
            return Ok(explicit);
        }

        bail!("{role} model not available from LM Studio: {explicit}");
    }

    for pattern in preferred_patterns {
        if let Some(model) = available.iter().find(|model| {
            model
                .to_ascii_lowercase()
                .contains(&pattern.to_ascii_lowercase())
        }) {
            return Ok(model.clone());
        }
    }

    available
        .first()
        .cloned()
        .ok_or_else(|| anyhow!("No LM Studio models available"))
}

fn execute_stage(
    engine: &mut ArdEngine,
    client: &LmStudioClient,
    session_id: Uuid,
    temperature: f32,
) -> Result<ArdSession> {
    let assignment = engine.current_assignment(session_id)?;

    let model = assignment_model(&assignment)?;

    println!(
        "ARD EXECUTE: role={} model={}",
        assignment.member.role, model
    );

    let system = format!(
        "{}\n\n\
         You are operating inside Vertex ARD v2.\n\
         You do not possess authority outside the supplied role policy.\n\
         Do not claim that files were changed or tests were executed unless \
         the assignment context contains evidence that they were.\n\
         Never bypass VVE or Human Gate.\n\
         Return only one valid JSON object.",
        assignment.role_policy
    );

    let context = serde_json::to_string_pretty(&assignment)?;

    let user = format!(
        r#"Execute the current ARD stage using only the supplied context.

CURRENT ASSIGNMENT:
{context}

Return ONLY JSON matching this exact logical schema:

{{
  "decision": "accepted" | "rework" | "blocked",
  "task_result": "short but concrete result",
  "decisions": [],
  "files_read": [],
  "files_changed": [],
  "tests_run": [],
  "test_results": [],
  "known_issues": [],
  "unresolved_questions": [],
  "next_action": "what the next ARD member should do",
  "confidence": 0.0
}}

Rules:
- confidence must be between 0.0 and 1.0.
- Architect normally returns accepted when architecture is sufficiently defined.
- Developer must not invent implementation evidence.
- Reviewer should return rework if evidence is insufficient.
- blocked means human approval or missing external evidence is required.
- no Markdown fences.
- no prose outside JSON.
"#
    );

    let raw = client.chat(&model, &system, &user, temperature)?;

    println!("MODEL RESPONSE:");
    println!("{raw}");

    let completion = parse_completion(&raw)?;

    println!("HANDOFF DECISION: {:?}", completion.decision);

    engine.complete_stage(session_id, completion)
}

fn assignment_model(assignment: &ArdAssignment) -> Result<String> {
    match &assignment.member.brain {
        BrainAssignment::Model {
            provider_id,
            model_id,
            ..
        } => {
            if !provider_id.eq_ignore_ascii_case("lmstudio") {
                bail!("Unsupported ARD brain provider: {provider_id}");
            }

            Ok(model_id.clone())
        }

        BrainAssignment::Auto => {
            bail!("This ARD member still uses BrainAssignment::Auto");
        }
    }
}

fn parse_completion(raw: &str) -> Result<CompleteArdStage> {
    let trimmed = raw.trim();

    let start = trimmed
        .find('{')
        .ok_or_else(|| anyhow!("Model response contains no JSON object"))?;

    let end = trimmed
        .rfind('}')
        .ok_or_else(|| anyhow!("Model response contains no closing JSON brace"))?;

    if end < start {
        bail!("Invalid JSON bounds in model response");
    }

    let json = &trimmed[start..=end];

    serde_json::from_str(json)
        .map_err(|error| anyhow!("Invalid CompleteArdStage JSON from model: {error}\nRAW:\n{raw}"))
}

fn run_relay(
    engine: &mut ArdEngine,
    client: &LmStudioClient,
    session_id: Uuid,
    max_steps: u32,
    temperature: f32,
) -> Result<()> {
    for step in 1..=max_steps {
        let state = engine
            .document()
            .relay
            .sessions
            .get(&session_id)
            .map(|session| session.state)
            .ok_or_else(|| anyhow!("ARD session not found: {session_id}"))?;

        println!();
        println!("=== RELAY STEP {step}/{max_steps} state={state:?} ===");

        match state {
            ArdSessionState::Completed => {
                println!("ARD RELAY COMPLETED");
                return Ok(());
            }

            ArdSessionState::Running => {}

            ArdSessionState::WaitingApproval => {
                println!("ARD RELAY STOPPED: WAITING_APPROVAL");
                return Ok(());
            }

            ArdSessionState::Paused => {
                let recovery_paused = engine
                    .document()
                    .relay
                    .sessions
                    .get(&session_id)
                    .and_then(|session| {
                        session.activity.iter().rev().find(|activity| {
                            matches!(activity.kind.as_str(), "recovery" | "pause" | "resume")
                        })
                    })
                    .is_some_and(|activity| activity.kind == "recovery");

                if recovery_paused {
                    println!("ARD RELAY AUTO-RESUME: RECOVERED SESSION");
                    engine.resume(session_id)?;
                    continue;
                }

                println!("ARD RELAY STOPPED: PAUSED");
                return Ok(());
            }

            ArdSessionState::Failed => {
                println!("ARD RELAY STOPPED: FAILED");
                return Ok(());
            }

            ArdSessionState::Cancelled => {
                println!("ARD RELAY STOPPED: CANCELLED");
                return Ok(());
            }

            ArdSessionState::Queued => {
                println!("ARD RELAY STOPPED: QUEUED");
                return Ok(());
            }
        }

        let result = execute_stage(engine, client, session_id, temperature)?;

        println!("stage_result_state={:?}", result.state);
    }

    println!("ARD RELAY STOPPED: max_steps reached ({max_steps})");

    Ok(())
}
