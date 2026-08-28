use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use vsa_vertex_hub::{
    hub_runtime_install, hub_runtime_set_enabled, hub_runtime_uninstall, load_hub_runtime_state,
};

#[test]
fn hub_runtime_install_enable_disable_uninstall_cycle_is_verified() {
    let workspace = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..");

    let hub = workspace.join("vertex-hub");

    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();

    let runtime = std::env::temp_dir().join(format!("vertex-hub-runtime-{stamp}"));

    let installed =
        hub_runtime_install(&hub, &runtime, "vertex.live-flight-panel", "1.0.0").expect("install");

    assert!(installed.installed);
    assert!(!installed.enabled);

    let enabled = hub_runtime_set_enabled(&runtime, "vertex.live-flight-panel", "1.0.0", true)
        .expect("enable");

    assert!(enabled.installed);
    assert!(enabled.enabled);

    let disabled = hub_runtime_set_enabled(&runtime, "vertex.live-flight-panel", "1.0.0", false)
        .expect("disable");

    assert!(disabled.installed);
    assert!(!disabled.enabled);

    let uninstalled =
        hub_runtime_uninstall(&runtime, "vertex.live-flight-panel", "1.0.0").expect("uninstall");

    assert!(!uninstalled.installed);
    assert!(!uninstalled.enabled);

    let state = load_hub_runtime_state(&runtime).expect("state");
    assert!(state.packages.is_empty());

    let _ = std::fs::remove_dir_all(runtime);
}
