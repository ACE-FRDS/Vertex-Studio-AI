use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use vsa_vertex_hub::install_registered_package;

#[test]
fn registered_live_flight_package_installs_with_integrity() {
    let workspace = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..");

    let hub = workspace.join("vertex-hub");

    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();

    let destination = std::env::temp_dir()
        .join(format!("vertex-hub-install-{stamp}"))
        .join("vertex.live-flight-panel")
        .join("1.0.0");

    let result =
        install_registered_package(&hub, &destination, "vertex.live-flight-panel", "1.0.0")
            .expect("registered package must install");

    assert_eq!(result.package_id, "vertex.live-flight-panel");
    assert_eq!(result.version, "1.0.0");
    assert_eq!(result.file_count, 4);

    let _ = std::fs::remove_dir_all(
        destination
            .ancestors()
            .nth(2)
            .expect("temporary install root"),
    );
}
