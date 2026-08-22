from pathlib import Path
import os
p = Path(os.environ["VERTEX_AGENT_RS"])
s = p.read_text(encoding="utf-8")
old = """        let vertex_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .nth(3)
            .expect("Vertex AI project root");
        assert!(vertex_root.join("ProgramSource/Cargo.toml").is_file());"""
new = """        let vertex_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .find(|path| {
                path.join("Cargo.toml").is_file()
                    && path.join("crates/vertex-ai-runtime/src/lib.rs").is_file()
            })
            .expect("Vertex AI Cargo workspace root");"""
assert old in s, "root block not found"
s = s.replace(old, new, 1)
s = s.replace('directory: Some("ProgramSource/crates/vertex-ai-runtime".to_owned())', 'directory: Some("crates/vertex-ai-runtime".to_owned())', 1)
s = s.replace('path: "ProgramSource/crates/vertex-ai-runtime/src/lib.rs".to_owned()', 'path: "crates/vertex-ai-runtime/src/lib.rs".to_owned()', 1)
p.write_text(s, encoding="utf-8")
print("PATCHED")
