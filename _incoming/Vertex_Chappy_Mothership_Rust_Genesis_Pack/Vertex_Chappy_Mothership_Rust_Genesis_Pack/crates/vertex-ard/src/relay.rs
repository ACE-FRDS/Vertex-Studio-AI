use crate::model::{
    ArdActivity, ArdAssignment, ArdDocument, ArdIntervention, ArdSession, ArdSessionId,
    ArdSessionState, ArdTeam, ArdTeamId, ArdTeamMember, ArdWorkflow, ArdWorkflowId,
    ArdWorkflowStage, CompleteArdStage, CreateArdTeam, HandoffDecision, ModelRotationRecord,
    RolePolicy, StructuredHandoff,
};
use anyhow::{anyhow, bail, Result};
use chrono::Utc;
use std::collections::BTreeMap;
use uuid::Uuid;

pub struct RelayEngine<'a> {
    document: &'a mut ArdDocument,
}

impl<'a> RelayEngine<'a> {
    pub fn new(document: &'a mut ArdDocument) -> Self {
        Self { document }
    }

    pub fn create_team(&mut self, input: CreateArdTeam) -> Result<ArdTeam> {
        validate_text("team name", &input.name)?;

        if input.members.is_empty() {
            bail!("ARD team requires at least one member");
        }

        let now = Utc::now();
        let mut members = Vec::with_capacity(input.members.len());

        for member in input.members {
            validate_text("member name", &member.name)?;
            validate_text("member role", &member.role)?;

            members.push(ArdTeamMember {
                id: Uuid::new_v4(),
                name: member.name,
                role: member.role,
                brain: member.brain,
                permission: member.permission,
                policy: RolePolicy {
                    responsibilities: member.responsibilities,
                    forbidden_actions: member.forbidden_actions,
                    escalation_rules: Vec::new(),
                },
                workspace_id: input.workspace_id.clone(),
                reports_to: None,
                handoff_to: None,
                enabled: true,
            });
        }

        let leader = members.first().map(|member| member.id);

        for index in 0..members.len() {
            members[index].handoff_to = members.get(index + 1).map(|member| member.id);

            if index > 0 {
                members[index].reports_to = leader;
            }
        }

        let team = ArdTeam {
            id: Uuid::new_v4(),
            name: input.name,
            workspace_id: input.workspace_id,
            members,
            created_at: now,
            updated_at: now,
        };

        self.document.relay.teams.insert(team.id, team.clone());

        self.document.updated_at = Utc::now();

        Ok(team)
    }

    pub fn create_relay_workflow(
        &mut self,
        team_id: ArdTeamId,
        name: impl Into<String>,
    ) -> Result<ArdWorkflow> {
        let name = name.into();
        validate_text("workflow name", &name)?;

        let team = self
            .document
            .relay
            .teams
            .get(&team_id)
            .cloned()
            .ok_or_else(|| anyhow!("ARD team not found: {team_id}"))?;

        let enabled = team
            .members
            .iter()
            .filter(|member| member.enabled)
            .cloned()
            .collect::<Vec<_>>();

        if enabled.is_empty() {
            bail!("ARD team has no enabled members");
        }

        let ids = (0..enabled.len())
            .map(|_| Uuid::new_v4())
            .collect::<Vec<_>>();

        let developer_stage = enabled.iter().position(|member| {
            let role = member.role.to_ascii_lowercase();
            role.contains("develop") || role.contains("engineer") || member.role.contains("開発")
        });

        let stages = enabled
            .iter()
            .enumerate()
            .map(|(index, member)| {
                let role = member.role.to_ascii_lowercase();

                ArdWorkflowStage {
                    id: ids[index],
                    member_id: member.id,
                    objective: format!(
                        "{}として担当範囲を実行し、Structured Handoffを作成する",
                        member.role
                    ),
                    on_success: ids.get(index + 1).copied(),
                    on_rework: if role.contains("review") || member.role.contains("レビュー") {
                        developer_stage.map(|position| ids[position])
                    } else {
                        None
                    },
                    max_attempts: 3,
                }
            })
            .collect();

        let workflow = ArdWorkflow {
            id: Uuid::new_v4(),
            team_id,
            name,
            entry_stage_id: ids[0],
            stages,
            created_at: Utc::now(),
        };

        self.document
            .relay
            .workflows
            .insert(workflow.id, workflow.clone());

        self.document.updated_at = Utc::now();

        Ok(workflow)
    }

    pub fn start_session(
        &mut self,
        workflow_id: ArdWorkflowId,
        goal: impl Into<String>,
    ) -> Result<ArdSession> {
        let goal = goal.into();
        validate_text("session goal", &goal)?;

        let workflow = self
            .document
            .relay
            .workflows
            .get(&workflow_id)
            .cloned()
            .ok_or_else(|| anyhow!("ARD workflow not found: {workflow_id}"))?;

        let team = self
            .document
            .relay
            .teams
            .get(&workflow.team_id)
            .cloned()
            .ok_or_else(|| anyhow!("ARD team not found: {}", workflow.team_id))?;

        let now = Utc::now();

        let mut session = ArdSession {
            id: Uuid::new_v4(),
            team_id: workflow.team_id,
            workflow_id,
            workspace_id: team.workspace_id,
            goal,
            state: ArdSessionState::Running,
            current_stage_id: Some(workflow.entry_stage_id),
            stage_attempts: BTreeMap::new(),
            handoffs: Vec::new(),
            interventions: Vec::new(),
            activity: Vec::new(),
            model_rotations: Vec::new(),
            active_model: None,
            created_at: now,
            updated_at: now,
            completed_at: None,
        };

        increment_attempt(&mut session, workflow.entry_stage_id);

        push_activity(&mut session, None, "session_started", "ARD session started");

        self.document
            .relay
            .sessions
            .insert(session.id, session.clone());

        self.document.updated_at = Utc::now();

        Ok(session)
    }

    pub fn current_assignment(&self, session_id: ArdSessionId) -> Result<ArdAssignment> {
        let session = self
            .document
            .relay
            .sessions
            .get(&session_id)
            .cloned()
            .ok_or_else(|| anyhow!("ARD session not found: {session_id}"))?;

        if session.state != ArdSessionState::Running {
            bail!("ARD session is not running: {:?}", session.state);
        }

        let stage_id = session
            .current_stage_id
            .ok_or_else(|| anyhow!("session has no current stage"))?;

        let workflow = self
            .document
            .relay
            .workflows
            .get(&session.workflow_id)
            .ok_or_else(|| anyhow!("ARD workflow not found: {}", session.workflow_id))?;

        let stage = workflow
            .stages
            .iter()
            .find(|stage| stage.id == stage_id)
            .cloned()
            .ok_or_else(|| anyhow!("ARD stage not found: {stage_id}"))?;

        let team = self
            .document
            .relay
            .teams
            .get(&session.team_id)
            .ok_or_else(|| anyhow!("ARD team not found: {}", session.team_id))?;

        let member = team
            .members
            .iter()
            .find(|member| member.id == stage.member_id)
            .cloned()
            .ok_or_else(|| anyhow!("ARD member not found: {}", stage.member_id))?;

        let relevant_handoffs = session
            .handoffs
            .iter()
            .filter(|handoff| {
                handoff.to_member_id == Some(member.id) || handoff.from_member_id == member.id
            })
            .cloned()
            .collect();

        let interventions = session
            .interventions
            .iter()
            .filter(|intervention| {
                intervention.delivered_to.is_empty()
                    || intervention.delivered_to.contains(&member.id)
            })
            .cloned()
            .collect();

        Ok(ArdAssignment {
            session_id,
            stage,
            role_policy: member.system_policy(),
            member,
            goal: session.goal,
            relevant_handoffs,
            interventions,
        })
    }

    pub fn complete_stage(
        &mut self,
        session_id: ArdSessionId,
        completion: CompleteArdStage,
    ) -> Result<ArdSession> {
        if !(0.0..=1.0).contains(&completion.confidence) {
            bail!("confidence must be between 0.0 and 1.0");
        }

        let session_snapshot = self
            .document
            .relay
            .sessions
            .get(&session_id)
            .cloned()
            .ok_or_else(|| anyhow!("ARD session not found: {session_id}"))?;

        if session_snapshot.state != ArdSessionState::Running {
            bail!("ARD session is not running: {:?}", session_snapshot.state);
        }

        let current_stage_id = session_snapshot
            .current_stage_id
            .ok_or_else(|| anyhow!("session has no current stage"))?;

        let workflow = self
            .document
            .relay
            .workflows
            .get(&session_snapshot.workflow_id)
            .cloned()
            .ok_or_else(|| anyhow!("workflow not found: {}", session_snapshot.workflow_id))?;

        let stage = workflow
            .stages
            .iter()
            .find(|stage| stage.id == current_stage_id)
            .cloned()
            .ok_or_else(|| anyhow!("stage not found: {current_stage_id}"))?;

        let next_stage_id = match completion.decision {
            HandoffDecision::Accepted => stage.on_success,
            HandoffDecision::Rework => stage.on_rework,
            HandoffDecision::Blocked => None,
        };

        let to_member_id = next_stage_id.and_then(|id| {
            workflow
                .stages
                .iter()
                .find(|candidate| candidate.id == id)
                .map(|candidate| candidate.member_id)
        });

        let handoff = StructuredHandoff {
            id: Uuid::new_v4(),
            from_member_id: stage.member_id,
            to_member_id,
            decision: completion.decision,
            task_result: completion.task_result,
            decisions: completion.decisions,
            files_read: completion.files_read,
            files_changed: completion.files_changed,
            tests_run: completion.tests_run,
            test_results: completion.test_results,
            known_issues: completion.known_issues,
            unresolved_questions: completion.unresolved_questions,
            next_action: completion.next_action,
            confidence: completion.confidence,
            created_at: Utc::now(),
        };

        let session = self
            .document
            .relay
            .sessions
            .get_mut(&session_id)
            .expect("session checked above");

        session.handoffs.push(handoff);

        push_activity(
            session,
            Some(stage.member_id),
            "handoff",
            &format!("Stage completed: {:?}", completion.decision),
        );

        match completion.decision {
            HandoffDecision::Accepted => {
                if let Some(next_id) = stage.on_success {
                    session.current_stage_id = Some(next_id);
                    increment_attempt(session, next_id);
                    enforce_attempt_limit(session, &workflow, next_id)?;
                } else {
                    session.state = ArdSessionState::Completed;
                    session.current_stage_id = None;
                    session.completed_at = Some(Utc::now());
                }
            }

            HandoffDecision::Rework => {
                if let Some(rework_id) = stage.on_rework {
                    session.current_stage_id = Some(rework_id);
                    increment_attempt(session, rework_id);
                    enforce_attempt_limit(session, &workflow, rework_id)?;
                } else {
                    session.state = ArdSessionState::Failed;
                    session.current_stage_id = None;
                }
            }

            HandoffDecision::Blocked => {
                session.state = ArdSessionState::WaitingApproval;
            }
        }

        session.updated_at = Utc::now();
        let result = session.clone();

        self.document.updated_at = Utc::now();

        Ok(result)
    }

    pub fn pause(&mut self, session_id: ArdSessionId) -> Result<ArdSession> {
        let session = self.session_mut(session_id)?;

        if session.state != ArdSessionState::Running {
            bail!("only a running session can be paused");
        }

        session.state = ArdSessionState::Paused;
        session.updated_at = Utc::now();

        push_activity(session, None, "pause", "ARD session paused");

        let result = session.clone();

        self.document.updated_at = Utc::now();

        Ok(result)
    }

    pub fn resume(&mut self, session_id: ArdSessionId) -> Result<ArdSession> {
        let session = self.session_mut(session_id)?;

        if !matches!(
            session.state,
            ArdSessionState::Paused | ArdSessionState::WaitingApproval
        ) {
            bail!("session cannot be resumed from current state");
        }

        session.state = ArdSessionState::Running;
        session.updated_at = Utc::now();

        push_activity(session, None, "resume", "ARD session resumed");

        let result = session.clone();

        self.document.updated_at = Utc::now();

        Ok(result)
    }

    pub fn cancel(&mut self, session_id: ArdSessionId) -> Result<ArdSession> {
        let session = self.session_mut(session_id)?;

        if matches!(
            session.state,
            ArdSessionState::Completed | ArdSessionState::Cancelled
        ) {
            bail!("session is already terminal");
        }

        session.state = ArdSessionState::Cancelled;
        session.current_stage_id = None;
        session.updated_at = Utc::now();
        session.completed_at = Some(Utc::now());

        push_activity(session, None, "cancel", "ARD session cancelled");

        let result = session.clone();

        self.document.updated_at = Utc::now();

        Ok(result)
    }

    pub fn intervene(
        &mut self,
        session_id: ArdSessionId,
        instruction: impl Into<String>,
        delivered_to: Vec<Uuid>,
    ) -> Result<ArdSession> {
        let instruction = instruction.into();
        validate_text("intervention", &instruction)?;

        let session = self.session_mut(session_id)?;

        session.interventions.push(ArdIntervention {
            instruction: instruction.clone(),
            created_at: Utc::now(),
            delivered_to,
        });

        push_activity(session, None, "human_intervention", &instruction);

        session.updated_at = Utc::now();
        let result = session.clone();

        self.document.updated_at = Utc::now();

        Ok(result)
    }

    pub fn record_model_rotation(
        &mut self,
        session_id: ArdSessionId,
        to: Option<String>,
        reused_loaded_model: bool,
        router_required: bool,
    ) -> Result<ArdSession> {
        let result = {
            let session = self.session_mut(session_id)?;

            let from = session.active_model.clone();

            session.model_rotations.push(ModelRotationRecord {
                from,
                to: to.clone(),
                reused_loaded_model,
                router_required,
                occurred_at: Utc::now(),
            });

            session.active_model = to;
            session.updated_at = Utc::now();

            push_activity(
                session,
                None,
                "model_rotation",
                "ARD model rotation recorded",
            );

            session.clone()
        };

        self.document.updated_at = Utc::now();

        Ok(result)
    }

    fn session_mut(&mut self, session_id: ArdSessionId) -> Result<&mut ArdSession> {
        self.document
            .relay
            .sessions
            .get_mut(&session_id)
            .ok_or_else(|| anyhow!("ARD session not found: {session_id}"))
    }
}

pub fn recover_interrupted_sessions(document: &mut ArdDocument) -> usize {
    let mut recovered = 0usize;

    for session in document.relay.sessions.values_mut() {
        if session.state == ArdSessionState::Running {
            session.state = ArdSessionState::Paused;
            session.updated_at = Utc::now();

            push_activity(
                session,
                None,
                "recovery",
                "アプリ終了で中断したARD Sessionを一時停止状態で復元しました",
            );

            recovered += 1;
        }
    }

    if recovered > 0 {
        document.updated_at = Utc::now();
    }

    recovered
}

fn validate_text(name: &str, value: &str) -> Result<()> {
    if value.trim().is_empty() {
        bail!("{name} may not be empty");
    }

    Ok(())
}

fn increment_attempt(session: &mut ArdSession, stage_id: Uuid) {
    *session.stage_attempts.entry(stage_id).or_insert(0) += 1;
}

fn enforce_attempt_limit(
    session: &mut ArdSession,
    workflow: &ArdWorkflow,
    stage_id: Uuid,
) -> Result<()> {
    let stage = workflow
        .stages
        .iter()
        .find(|stage| stage.id == stage_id)
        .ok_or_else(|| anyhow!("stage not found: {stage_id}"))?;

    let attempts = session.stage_attempts.get(&stage_id).copied().unwrap_or(0);

    if attempts > stage.max_attempts {
        session.state = ArdSessionState::Failed;
        session.current_stage_id = None;

        bail!(
            "stage retry limit exceeded: {stage_id} ({attempts}/{})",
            stage.max_attempts
        );
    }

    Ok(())
}

fn push_activity(session: &mut ArdSession, member_id: Option<Uuid>, kind: &str, message: &str) {
    let sequence = session
        .activity
        .last()
        .map_or(1, |activity| activity.sequence.saturating_add(1));

    session.activity.push(ArdActivity {
        sequence,
        occurred_at: Utc::now(),
        member_id,
        kind: kind.to_owned(),
        message: message.to_owned(),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{BrainAssignment, CreateArdMember, HardPermission};

    fn team_input() -> CreateArdTeam {
        CreateArdTeam {
            name: "Genesis Team".to_owned(),
            workspace_id: "project://vertex/mothership".to_owned(),
            members: vec![
                CreateArdMember {
                    name: "Architect".to_owned(),
                    role: "Architect".to_owned(),
                    brain: BrainAssignment::Auto,
                    permission: HardPermission::read_only(),
                    responsibilities: vec!["Analyze impact".to_owned()],
                    forbidden_actions: vec!["Direct repository write".to_owned()],
                },
                CreateArdMember {
                    name: "Developer".to_owned(),
                    role: "Developer".to_owned(),
                    brain: BrainAssignment::Auto,
                    permission: HardPermission::developer_vve(),
                    responsibilities: vec!["Implement in VVE".to_owned()],
                    forbidden_actions: vec!["Bypass Human Gate".to_owned()],
                },
                CreateArdMember {
                    name: "Reviewer".to_owned(),
                    role: "Reviewer".to_owned(),
                    brain: BrainAssignment::Auto,
                    permission: HardPermission::reviewer(),
                    responsibilities: vec!["Review and test".to_owned()],
                    forbidden_actions: vec!["Promote without approval".to_owned()],
                },
            ],
        }
    }

    #[test]
    fn relay_builds_team_workflow_and_session() {
        let mut document = ArdDocument::default();
        let mut relay = RelayEngine::new(&mut document);

        let team = relay.create_team(team_input()).unwrap();

        let workflow = relay
            .create_relay_workflow(team.id, "Genesis Relay")
            .unwrap();

        let session = relay
            .start_session(workflow.id, "Build ARD v2 safely")
            .unwrap();

        assert_eq!(session.state, ArdSessionState::Running);

        let assignment = relay.current_assignment(session.id).unwrap();

        assert_eq!(assignment.member.role, "Architect");
    }

    #[test]
    fn reviewer_can_rework_to_developer() {
        let mut document = ArdDocument::default();
        let mut relay = RelayEngine::new(&mut document);

        let team = relay.create_team(team_input()).unwrap();

        let workflow = relay.create_relay_workflow(team.id, "Relay").unwrap();

        let mut session = relay.start_session(workflow.id, "Goal").unwrap();

        session = relay
            .complete_stage(
                session.id,
                CompleteArdStage {
                    decision: HandoffDecision::Accepted,
                    task_result: "architecture done".to_owned(),
                    decisions: vec![],
                    files_read: vec![],
                    files_changed: vec![],
                    tests_run: vec![],
                    test_results: vec![],
                    known_issues: vec![],
                    unresolved_questions: vec![],
                    next_action: "develop".to_owned(),
                    confidence: 0.9,
                },
            )
            .unwrap();

        let developer = relay.current_assignment(session.id).unwrap();

        assert_eq!(developer.member.role, "Developer");

        session = relay
            .complete_stage(
                session.id,
                CompleteArdStage {
                    decision: HandoffDecision::Accepted,
                    task_result: "implementation done".to_owned(),
                    decisions: vec![],
                    files_read: vec![],
                    files_changed: vec!["src/lib.rs".to_owned()],
                    tests_run: vec!["cargo test".to_owned()],
                    test_results: vec!["ok".to_owned()],
                    known_issues: vec![],
                    unresolved_questions: vec![],
                    next_action: "review".to_owned(),
                    confidence: 0.8,
                },
            )
            .unwrap();

        let reviewer = relay.current_assignment(session.id).unwrap();

        assert_eq!(reviewer.member.role, "Reviewer");

        session = relay
            .complete_stage(
                session.id,
                CompleteArdStage {
                    decision: HandoffDecision::Rework,
                    task_result: "needs changes".to_owned(),
                    decisions: vec![],
                    files_read: vec![],
                    files_changed: vec![],
                    tests_run: vec![],
                    test_results: vec![],
                    known_issues: vec!["issue".to_owned()],
                    unresolved_questions: vec![],
                    next_action: "rework".to_owned(),
                    confidence: 0.7,
                },
            )
            .unwrap();

        let developer_again = relay.current_assignment(session.id).unwrap();

        assert_eq!(developer_again.member.role, "Developer");
    }
}
