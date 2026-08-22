use anyhow::Result;
use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};
use std::{env, net::SocketAddr, path::PathBuf};
use tower_http::trace::TraceLayer;
use vertex_core::MissionRequest;
use vertex_harness::Harness;
use vertex_policy::Config;

#[derive(Clone)]
struct AppState {
    harness: Harness,
    token: Option<String>,
}
fn authorized(headers: &HeaderMap, state: &AppState) -> bool {
    match &state.token {
        None => true,
        Some(t) => headers
            .get("x-vertex-owner-token")
            .and_then(|v| v.to_str().ok())
            .map(|v| v == t)
            .unwrap_or(false),
    }
}
async fn health() -> Json<Value> {
    Json(json!({"ok":true,"service":"VERTEX_CHAPPY_HARNESS","version":env!("CARGO_PKG_VERSION")}))
}
async fn capabilities(State(s): State<AppState>, headers: HeaderMap) -> impl IntoResponse {
    if !authorized(&headers, &s) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({"error":"unauthorized"})),
        );
    }
    let p = s.harness.config.profile().ok();
    (
        StatusCode::OK,
        Json(
            json!({"profile":s.harness.config.policy.active_profile,"allowed":p.map(|x|x.allowed_capabilities.clone()).unwrap_or_default(),"direct_real_repository_write":s.harness.config.policy.direct_real_repository_write,"human_gate_required":s.harness.config.policy.human_gate_required}),
        ),
    )
}
async fn mission(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<MissionRequest>,
) -> impl IntoResponse {
    if !authorized(&headers, &s) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({"error":"unauthorized"})),
        );
    }
    let m = s.harness.execute(req).await;
    (StatusCode::OK, Json(serde_json::to_value(m).unwrap()))
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let config_path = env::args()
        .skip_while(|x| x != "--config")
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("config/vertex-harness.toml"));
    let cfg = Config::load(config_path)?;
    let addr: SocketAddr = format!("{}:{}", cfg.server.bind_host, cfg.server.bind_port).parse()?;
    let token = env::var(&cfg.server.token_env).ok();
    let state = AppState {
        harness: Harness::new(cfg),
        token,
    };
    let app = Router::new()
        .route("/health", get(health))
        .route("/capabilities", get(capabilities))
        .route("/mission", post(mission))
        .layer(TraceLayer::new_for_http())
        .with_state(state);
    tracing::info!(%addr,"Vertex Chappy Harness online");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
