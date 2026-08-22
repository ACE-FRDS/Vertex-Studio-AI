use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use vertex_policy::Config;
#[derive(Parser)]
struct Cli {
    #[arg(long, default_value = "config/vertex-harness.toml")]
    config: PathBuf,
    #[command(subcommand)]
    command: Cmd,
}
#[derive(Subcommand)]
enum Cmd {
    Doctor,
    State,
    Vur,
}
fn main() -> Result<()> {
    let cli = Cli::parse();
    let cfg = Config::load(&cli.config)?;
    match cli.command {
        Cmd::Doctor => {
            println!("profile: {}", cfg.policy.active_profile);
            println!("mothership: {}", cfg.paths.mothership_root.display());
            println!("state exists: {}", cfg.paths.state_file.exists());
            println!("VUR registry exists: {}", cfg.paths.vur_registry.exists());
            println!("VVE root exists: {}", cfg.paths.vve_root.exists());
        }
        Cmd::State => println!(
            "{}",
            serde_json::to_string_pretty(&vertex_state::read_mothership_state(
                &cfg.paths.state_file
            )?)?
        ),
        Cmd::Vur => println!(
            "{}",
            serde_json::to_string_pretty(&vertex_state::read_vur_registry(
                &cfg.paths.vur_registry
            )?)?
        ),
    }
    Ok(())
}
