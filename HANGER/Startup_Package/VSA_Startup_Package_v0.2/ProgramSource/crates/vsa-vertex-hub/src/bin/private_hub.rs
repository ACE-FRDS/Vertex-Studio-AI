use std::env;
use std::fs;
use std::path::Path;

use vsa_vertex_hub::private_control::{
    HumanApproval, PrivatePatchReceipt, apply_staged_private_patch, read_private_source_snapshot,
    rollback_private_patch,
};
use vsa_vertex_hub::private_transport::{PrivateTextPatchRequest, stage_private_text_patch};

fn usage() -> ! {
    eprintln!(
        "Private VertexHub CLI v0.2\n\
         \n\
         Commands:\n\
         snapshot <workspace_root> <relative_path>\n\
         stage-text <workspace_root> <control_root> <request.json>\n\
         apply <workspace_root> <control_root> <request_id> <approved_by>\n\
         rollback <workspace_root> <control_root> <receipt.json> <approved_by>"
    );
    std::process::exit(2);
}

fn print_json<T: serde::Serialize>(value: &T) -> Result<(), String> {
    let json = serde_json::to_string_pretty(value)
        .map_err(|error| format!("cannot serialize CLI output: {error}"))?;
    println!("{json}");
    Ok(())
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();

    let Some(command) = args.get(1).map(String::as_str) else {
        usage();
    };

    match command {
        "snapshot" => {
            if args.len() != 4 {
                usage();
            }

            let snapshot = read_private_source_snapshot(Path::new(&args[2]), &args[3])?;
            print_json(&snapshot)
        }
        "stage-text" => {
            if args.len() != 5 {
                usage();
            }

            let bytes = fs::read(&args[4])
                .map_err(|error| format!("cannot read patch request {}: {error}", args[4]))?;

            let request: PrivateTextPatchRequest = serde_json::from_slice(&bytes)
                .map_err(|error| format!("invalid Private VertexHub text-patch JSON: {error}"))?;

            let preview =
                stage_private_text_patch(Path::new(&args[2]), Path::new(&args[3]), &request)?;

            print_json(&preview)
        }
        "apply" => {
            if args.len() != 6 {
                usage();
            }

            let approval = HumanApproval {
                request_id: args[4].clone(),
                approved: true,
                approved_by: args[5].clone(),
            };

            let receipt = apply_staged_private_patch(
                Path::new(&args[2]),
                Path::new(&args[3]),
                &args[4],
                &approval,
            )?;

            print_json(&receipt)
        }
        "rollback" => {
            if args.len() != 6 {
                usage();
            }

            let bytes = fs::read(&args[4])
                .map_err(|error| format!("cannot read receipt {}: {error}", args[4]))?;

            let receipt: PrivatePatchReceipt = serde_json::from_slice(&bytes)
                .map_err(|error| format!("invalid Private VertexHub receipt JSON: {error}"))?;

            let snapshot = rollback_private_patch(
                Path::new(&args[2]),
                Path::new(&args[3]),
                &receipt,
                &args[5],
            )?;

            print_json(&snapshot)
        }
        _ => usage(),
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("PRIVATE_VERTEXHUB_ERROR: {error}");
        std::process::exit(1);
    }
}
