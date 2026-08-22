param([Parameter(Mandatory=$true)][string]$ProgramSource)
Push-Location $ProgramSource
try{cargo fmt --all;cargo check -p vertex-ai-impact;cargo check -p vsa-impact-front-lab;cargo run -p vsa-impact-front-lab;git status --short}finally{Pop-Location}
