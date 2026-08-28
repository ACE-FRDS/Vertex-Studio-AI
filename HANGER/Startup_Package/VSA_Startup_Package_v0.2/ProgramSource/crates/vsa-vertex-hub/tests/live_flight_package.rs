use std::path::Path;
use vsa_vertex_hub::validate_registry;

#[test]
fn live_flight_package_is_registered_and_integrity_verified() {
    let workspace = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..");

    let hub = workspace.join("vertex-hub");
    let reports = validate_registry(&hub).expect("VertexHub registry must validate");

    let package = reports
        .iter()
        .find(|report| report.package_id == "vertex.live-flight-panel" && report.version == "1.0.0")
        .expect("Live Flight package must be registered");

    assert_eq!(package.file_count, 4);
}
