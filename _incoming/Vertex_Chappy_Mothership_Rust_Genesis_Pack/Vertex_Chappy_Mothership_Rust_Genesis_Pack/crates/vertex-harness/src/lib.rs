use anyhow::Result;
use serde_json::{json, Value};
use std::{path::PathBuf, sync::Arc};
use vertex_audit::AuditLog;
use vertex_core::{Capability, MissionEnvelope, MissionRequest, MissionState, VertexError};
use vertex_policy::{require_capability, Config};

#[derive(Clone)]
pub struct Harness {
    pub config: Arc<Config>,
    pub audit: AuditLog,
}
impl Harness {
    pub fn new(config: Config) -> Self {
        let audit = AuditLog::new(config.paths.audit_file.clone());
        Self {
            config: Arc::new(config),
            audit,
        }
    }
    pub async fn execute(&self, req: MissionRequest) -> MissionEnvelope {
        let mut m = MissionEnvelope::new(req);
        if let Err(e) = require_capability(&self.config, &m.capability) {
            m.state = MissionState::Denied;
            m.result = Some(json!({"error":e.to_string()}));
            let _ = self.audit.append("MISSION_DENIED", &m);
            return m;
        }
        let _ = self.audit.append("MISSION_ACCEPTED", &m);
        let result: Result<Value, VertexError> =
            async {
                match m.capability {
            Capability::ReadMothershipState => {
                vertex_state::read_mothership_state(&self.config.paths.state_file)
                    .map_err(|e| VertexError::Io(e.to_string()))
            }
            Capability::ReadVur => vertex_state::read_vur_registry(&self.config.paths.vur_registry)
                .map_err(|e| VertexError::Io(e.to_string())),
            Capability::QueryArd => {
                let root = m
                    .payload
                    .get("asset_id")
                    .and_then(Value::as_str)
                    .unwrap_or("project://vertex-studio/mothership");
                let depth = m
                    .payload
                    .get("max_depth")
                    .and_then(Value::as_u64)
                    .unwrap_or(8) as usize;
                vertex_relations::edges_from_mothership_state(&self.config.paths.state_file)
                    .map(|edges| {
                        serde_json::to_value(vertex_relations::impact(root, depth, &edges)).unwrap()
                    })
                    .map_err(|e| VertexError::Io(e.to_string()))
            }
            Capability::GitInspect => {
                let root = m
                    .payload
                    .get("root")
                    .and_then(Value::as_str)
                    .map(PathBuf::from)
                    .unwrap_or_else(|| self.config.paths.real_repository.clone());
                vertex_git::inspect(&root)
                    .await
                    .map(|x| serde_json::to_value(x).unwrap())
                    .map_err(|e| VertexError::Execution(e.to_string()))
            }
            Capability::RunBuild | Capability::RunTest => {
                let spec: vertex_runtime::RunSpec = serde_json::from_value(m.payload.clone())
                    .map_err(|e| VertexError::InvalidRequest(e.to_string()))?;
                vertex_runtime::run(&self.config, spec)
                    .await
                    .map(|x| serde_json::to_value(x).unwrap())
            }
            Capability::RunPowershellSafe => {
                let spec: vertex_runtime::PowerShellSafeSpec =
                    serde_json::from_value(m.payload.clone())
                        .map_err(|e| VertexError::InvalidRequest(e.to_string()))?;

                vertex_runtime::run_powershell_safe(&self.config, spec)
                    .await
                    .map(|x| serde_json::to_value(x).unwrap())
            }
            Capability::CreateVveChangeset => vertex_vve::create(&self.config.paths.vve_root)
                .map(|x| serde_json::to_value(x).unwrap())
                .map_err(|e| VertexError::Io(e.to_string())),
            Capability::WriteVveFile => {
                let manifest = m
                    .payload
                    .get("manifest")
                    .and_then(Value::as_str)
                    .ok_or_else(|| VertexError::InvalidRequest("manifest required".into()))?;
                let path = m
                    .payload
                    .get("path")
                    .and_then(Value::as_str)
                    .ok_or_else(|| VertexError::InvalidRequest("path required".into()))?;
                let content = m
                    .payload
                    .get("content")
                    .and_then(Value::as_str)
                    .ok_or_else(|| VertexError::InvalidRequest("content required".into()))?;
                let cs = vertex_vve::load(&PathBuf::from(manifest))
                    .map_err(|e| VertexError::Io(e.to_string()))?;
                vertex_vve::write_file(cs, &PathBuf::from(path), content.as_bytes())
                    .map(|x| serde_json::to_value(x).unwrap())
            }
            Capability::PromoteVve => Err(VertexError::HumanGateRequired(
                "PROMOTE_VVE must be approved by owner and implemented by promotion adapter".into(),
            )),
        }
            }
            .await;
        match result {
            Ok(v) => {
                m.state = MissionState::Completed;
                m.result = Some(v);
            }
            Err(VertexError::HumanGateRequired(e)) => {
                m.state = MissionState::HumanGateRequired;
                m.result = Some(json!({"error":e}));
            }
            Err(e) => {
                m.state = MissionState::Failed;
                m.result = Some(json!({"error":e.to_string()}));
            }
        }
        let _ = self.audit.append("MISSION_FINISHED", &m);
        m
    }
}
