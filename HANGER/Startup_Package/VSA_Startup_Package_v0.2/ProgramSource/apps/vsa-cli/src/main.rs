use std::path::PathBuf;
use vsa_ard::ultra_fine_decompose;
use vsa_mnl::{HumanPrompt, normalize};
use vsa_mothership::default_mothership;
use vsa_rcc::{HardwareProfile, recommend};
use vsa_studio::{ProjectKind, VertexDefinition};
use vsa_web::{WebMode, WebProject, WebRoute, render_static_site};

fn main() {
    let arg = std::env::args().nth(1).unwrap_or_else(|| "demo".into());
    if arg != "demo" {
        eprintln!("usage: vsa-cli demo");
        std::process::exit(2)
    }
    let def = VertexDefinition::new("VSA Demo", ProjectKind::StaticWebsite);
    let mut web = WebProject::new(WebMode::Static);
    web.routes.push(WebRoute {
        path: "/".into(),
        title: "Home".into(),
        component: "home".into(),
    });
    let out = PathBuf::from("target/vsa-demo-site");
    render_static_site(&def, &web, &out).expect("static render");
    let mission = normalize(&HumanPrompt {
        language: "ja".into(),
        original: "静的ホームページを作る".into(),
    });
    let units = ultra_fine_decompose(
        "Static Website",
        &["definition", "layout", "render", "verify"],
    );
    let rcc = recommend(&HardwareProfile {
        cpu_threads: 16,
        ram_gb: 128,
        vram_gb: 12,
        gpu_name: "Local GPU".into(),
    });
    println!("VSA LIFE SIGN");
    println!("site={}", out.display());
    println!("mnl_action={}", mission.action);
    println!("work_units={}", units.len());
    println!("rcc={}", rcc.name);
    println!("facilities={}", default_mothership().len());
}
