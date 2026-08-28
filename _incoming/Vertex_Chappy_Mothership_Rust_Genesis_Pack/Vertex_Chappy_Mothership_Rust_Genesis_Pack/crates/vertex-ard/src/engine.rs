use crate::{
    graph::{ImportReport, RelationGraph},
    model::{
        ArdAssignment, ArdDocument, ArdImpact, ArdSession, ArdSessionId, ArdTeam, ArdTeamId,
        ArdWorkflow, ArdWorkflowId, CompleteArdStage, CreateArdTeam,
    },
    relay::RelayEngine,
    store::ArdStore,
};
use anyhow::Result;
use std::path::Path;
use uuid::Uuid;

pub struct ArdEngine {
    store: ArdStore,
    document: ArdDocument,
}

impl ArdEngine {
    pub fn open(path: impl Into<std::path::PathBuf>) -> Result<Self> {
        let store = ArdStore::new(path);
        let document = store.load_with_recovery()?;

        Ok(Self { store, document })
    }

    pub fn document(&self) -> &ArdDocument {
        &self.document
    }

    pub fn save(&self) -> Result<()> {
        self.store.save(&self.document)
    }

    pub fn import_mothership_state(&mut self, path: &Path) -> Result<ImportReport> {
        let mut graph = RelationGraph::new(self.document.graph.clone());

        let report = graph.import_mothership_state(path)?;

        self.document.graph = graph.document;
        self.save()?;

        Ok(report)
    }

    pub fn import_vur_registry(&mut self, path: &Path) -> Result<ImportReport> {
        let mut graph = RelationGraph::new(self.document.graph.clone());

        let report = graph.import_vur_registry(path)?;

        self.document.graph = graph.document;
        self.save()?;

        Ok(report)
    }

    pub fn impact(&self, root: &str, max_depth: usize) -> ArdImpact {
        RelationGraph::new(self.document.graph.clone()).impact(root, max_depth)
    }

    pub fn create_team(&mut self, input: CreateArdTeam) -> Result<ArdTeam> {
        let team = RelayEngine::new(&mut self.document).create_team(input)?;

        self.save()?;
        Ok(team)
    }

    pub fn create_relay_workflow(
        &mut self,
        team_id: ArdTeamId,
        name: impl Into<String>,
    ) -> Result<ArdWorkflow> {
        let workflow = RelayEngine::new(&mut self.document).create_relay_workflow(team_id, name)?;

        self.save()?;
        Ok(workflow)
    }

    pub fn start_session(
        &mut self,
        workflow_id: ArdWorkflowId,
        goal: impl Into<String>,
    ) -> Result<ArdSession> {
        let session = RelayEngine::new(&mut self.document).start_session(workflow_id, goal)?;

        self.save()?;
        Ok(session)
    }

    pub fn current_assignment(&mut self, session_id: ArdSessionId) -> Result<ArdAssignment> {
        RelayEngine::new(&mut self.document).current_assignment(session_id)
    }

    pub fn complete_stage(
        &mut self,
        session_id: ArdSessionId,
        completion: CompleteArdStage,
    ) -> Result<ArdSession> {
        let session =
            RelayEngine::new(&mut self.document).complete_stage(session_id, completion)?;

        self.save()?;
        Ok(session)
    }

    pub fn pause(&mut self, session_id: ArdSessionId) -> Result<ArdSession> {
        let session = RelayEngine::new(&mut self.document).pause(session_id)?;

        self.save()?;
        Ok(session)
    }

    pub fn resume(&mut self, session_id: ArdSessionId) -> Result<ArdSession> {
        let session = RelayEngine::new(&mut self.document).resume(session_id)?;

        self.save()?;
        Ok(session)
    }

    pub fn cancel(&mut self, session_id: ArdSessionId) -> Result<ArdSession> {
        let session = RelayEngine::new(&mut self.document).cancel(session_id)?;

        self.save()?;
        Ok(session)
    }

    pub fn intervene(
        &mut self,
        session_id: ArdSessionId,
        instruction: impl Into<String>,
        delivered_to: Vec<Uuid>,
    ) -> Result<ArdSession> {
        let session = RelayEngine::new(&mut self.document).intervene(
            session_id,
            instruction,
            delivered_to,
        )?;

        self.save()?;
        Ok(session)
    }
}
