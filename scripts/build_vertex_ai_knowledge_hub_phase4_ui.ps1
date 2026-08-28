#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Vertex AI Knowledge Hub - Phase 4 SF UI
# Visual layer only: preserves canonical AI endpoints, Google verification files,
# health.json, robots.txt, sitemap.xml, llms.txt, bootstrap and .well-known data.

$root = "G:\Vertex_Project\Development\vertex_studio_ai\VertexHub"
$site = Join-Path $root "site"
$assets = Join-Path $site "assets"
$cssDir = Join-Path $assets "css"
$jsDir  = Join-Path $assets "js"

if (-not (Test-Path $site)) { throw "Site root missing: $site" }

New-Item -ItemType Directory -Force $cssDir,$jsDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root "backup\phase4_ui_$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null

# Back up only visual files that this patch will replace.
foreach ($p in @(
    (Join-Path $site "index.html"),
    (Join-Path $cssDir "theme.css"),
    (Join-Path $cssDir "components.css"),
    (Join-Path $jsDir "hub-ui.js")
)) {
    if (Test-Path $p) { Copy-Item $p $backup -Force }
}

$theme = @'
:root{
  --bg:#05070b;
  --panel:rgba(9,15,24,.78);
  --panel2:rgba(13,24,37,.68);
  --line:rgba(116,226,255,.18);
  --line2:rgba(116,226,255,.42);
  --text:#e8f7ff;
  --muted:#88a5b5;
  --cyan:#72e6ff;
  --blue:#78a7ff;
  --ok:#91ffd2;
  --warn:#ffe69b;
  --shadow:0 0 28px rgba(86,210,255,.12);
}
*{box-sizing:border-box}
html{background:var(--bg);color-scheme:dark}
body{
  margin:0;color:var(--text);
  font-family:Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
  background:
    radial-gradient(circle at 50% -10%,rgba(45,123,177,.22),transparent 36rem),
    linear-gradient(rgba(76,190,235,.035) 1px,transparent 1px),
    linear-gradient(90deg,rgba(76,190,235,.035) 1px,transparent 1px),
    var(--bg);
  background-size:auto,32px 32px,32px 32px,auto;
  min-height:100vh;
}
a{color:inherit;text-decoration:none}
.shell{width:min(1220px,calc(100% - 36px));margin:auto}
.eyebrow{font-size:.72rem;letter-spacing:.28em;text-transform:uppercase;color:var(--cyan)}
.muted{color:var(--muted)}
.mono{font-family:"Cascadia Code","SFMono-Regular",Consolas,monospace}
'@

$components = @'
.topbar{
  position:sticky;top:0;z-index:20;
  backdrop-filter:blur(16px);
  background:rgba(5,7,11,.72);
  border-bottom:1px solid var(--line);
}
.topbar-inner{height:66px;display:flex;align-items:center;justify-content:space-between;gap:24px}
.brand{display:flex;align-items:center;gap:12px;font-weight:700;letter-spacing:.08em}
.core-dot{width:10px;height:10px;border-radius:50%;background:var(--ok);box-shadow:0 0 16px var(--ok)}
nav{display:flex;gap:20px;font-size:.84rem;color:var(--muted)}
nav a:hover{color:var(--cyan)}
.hero{padding:92px 0 56px;position:relative}
.hero-grid{display:grid;grid-template-columns:1.4fr .8fr;gap:26px;align-items:stretch}
h1{font-size:clamp(3rem,7vw,6.7rem);line-height:.88;margin:14px 0 24px;letter-spacing:-.065em}
.gradient{background:linear-gradient(90deg,#fff,var(--cyan),var(--blue));-webkit-background-clip:text;background-clip:text;color:transparent}
.lead{font-size:1.08rem;line-height:1.8;max-width:700px;color:#a9c0cd}
.panel{
  border:1px solid var(--line);background:linear-gradient(145deg,var(--panel),var(--panel2));
  box-shadow:var(--shadow);position:relative;overflow:hidden;
}
.panel:before{content:"";position:absolute;inset:0;pointer-events:none;background:linear-gradient(90deg,transparent,rgba(115,229,255,.035),transparent)}
.panel-pad{padding:24px}
.status-head{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid var(--line);padding-bottom:15px;margin-bottom:18px}
.status-row{display:grid;grid-template-columns:1fr auto;gap:12px;padding:9px 0;color:var(--muted);font-size:.85rem}
.status-row b{color:var(--ok);font-weight:600}
.section{padding:28px 0 60px}
.section-head{display:flex;justify-content:space-between;align-items:end;margin-bottom:20px}
.section h2{font-size:1.6rem;margin:5px 0}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
.card{padding:22px;min-height:190px;transition:.2s transform,.2s border-color}
.card:hover{transform:translateY(-3px);border-color:var(--line2)}
.card .num{font-size:.7rem;color:var(--cyan);letter-spacing:.18em}
.card h3{margin:34px 0 8px;font-size:1.15rem}
.card p{color:var(--muted);line-height:1.65;font-size:.9rem}
.graph{min-height:320px;padding:30px;display:flex;align-items:center;justify-content:center}
.graph-stage{width:min(760px,100%);height:240px;position:relative}
.node{
  position:absolute;min-width:118px;padding:13px 16px;text-align:center;
  border:1px solid var(--line2);background:#09131d;box-shadow:0 0 22px rgba(85,218,255,.08);
  font-size:.78rem;letter-spacing:.08em;
}
.n1{left:4%;top:42%}.n2{left:28%;top:8%}.n3{left:28%;bottom:8%}.n4{right:28%;top:42%}.n5{right:4%;top:42%}
.wire{position:absolute;height:1px;background:linear-gradient(90deg,transparent,var(--cyan),transparent);transform-origin:left center;opacity:.55}
.w1{width:29%;left:15%;top:48%;transform:rotate(-22deg)}
.w2{width:29%;left:15%;top:53%;transform:rotate(22deg)}
.w3{width:29%;left:39%;top:27%;transform:rotate(22deg)}
.w4{width:29%;left:39%;top:73%;transform:rotate(-22deg)}
.w5{width:25%;left:63%;top:50%}
.endpoint{display:grid;grid-template-columns:1fr auto;gap:14px;padding:13px 0;border-bottom:1px solid var(--line);font-size:.82rem}
.endpoint:last-child{border:0}.endpoint span:last-child{color:var(--ok)}
.vera{display:grid;grid-template-columns:auto 1fr;gap:18px;align-items:center}
.vera-mark{width:64px;height:64px;border:1px solid var(--line2);display:grid;place-items:center;font-size:1.45rem;color:var(--cyan);box-shadow:0 0 25px rgba(114,230,255,.12)}
footer{border-top:1px solid var(--line);padding:28px 0 46px;color:var(--muted);font-size:.78rem}
@media(max-width:850px){
  .hero-grid,.cards{grid-template-columns:1fr}
  nav{display:none}.hero{padding-top:62px}
  .graph-stage{transform:scale(.82)}
}
'@

$js = @'
(() => {
  const el = document.querySelector("[data-clock]");
  const tick = () => {
    if (el) el.textContent = new Date().toLocaleString("ja-JP",{hour12:false});
  };
  tick(); setInterval(tick,1000);
})();
'@

$index = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vertex AI Knowledge Hub</title>
<meta name="description" content="Canonical knowledge for human and AI. Research, architecture, lexicon and machine-readable knowledge for the Vertex project.">
<meta name="robots" content="index,follow">
<link rel="canonical" href="https://vertex.a-portal.net/">
<link rel="describedby" href="/llms.txt" type="text/plain">
<link rel="alternate" href="/ai/vertex-public-knowledge.json" type="application/json">
<link rel="stylesheet" href="/assets/css/theme.css">
<link rel="stylesheet" href="/assets/css/components.css">
</head>
<body>
<header class="topbar">
  <div class="shell topbar-inner">
    <a class="brand" href="/"><span class="core-dot"></span>VERTEX AI KNOWLEDGE HUB</a>
    <nav>
      <a href="/research/">Research</a>
      <a href="/knowledge/">Knowledge</a>
      <a href="/knowledge/lexicon/">Lexicon</a>
      <a href="/knowledge/architecture/">Architecture</a>
      <a href="/bootstrap/">AI Bootstrap</a>
    </nav>
  </div>
</header>

<main>
<section class="hero">
  <div class="shell hero-grid">
    <div>
      <div class="eyebrow">Vertex / Canonical System</div>
      <h1>KNOWLEDGE<br><span class="gradient">WITHOUT FORGETTING.</span></h1>
      <p class="lead">Canonical knowledge for human and AI. A public, machine-readable knowledge layer for research, terminology, architecture, provenance and continuity across Vertex sessions.</p>
    </div>
    <aside class="panel panel-pad">
      <div class="status-head"><span class="eyebrow">Core Status</span><span class="core-dot"></span></div>
      <div class="status-row"><span>KNOWLEDGE</span><b>ONLINE</b></div>
      <div class="status-row"><span>CANONICAL DATA</span><b>READY</b></div>
      <div class="status-row"><span>VERA CALLSIGN</span><b>ADOPTED</b></div>
      <div class="status-row"><span>DATABASE</span><b>NONE</b></div>
      <div class="status-row"><span>LOCAL TIME</span><span class="mono" data-clock>--</span></div>
    </aside>
  </div>
</section>

<section class="section">
  <div class="shell">
    <div class="section-head"><div><div class="eyebrow">Knowledge Domains</div><h2>Explore the system</h2></div></div>
    <div class="cards">
      <a class="panel card" href="/research/"><span class="num">01 / RESEARCH</span><h3>Research Archive</h3><p>Research notes and papers derived from documented Vertex concepts and experiments.</p></a>
      <a class="panel card" href="/knowledge/lexicon/"><span class="num">02 / LEXICON</span><h3>Canonical Lexicon</h3><p>Terminology with explicit status. Unknown definitions remain pending rather than inferred.</p></a>
      <a class="panel card" href="/knowledge/architecture/"><span class="num">03 / ARCHITECTURE</span><h3>System Architecture</h3><p>Relationships among memory, continuity, runtime and other documented Vertex components.</p></a>
    </div>
  </div>
</section>

<section class="section">
  <div class="shell">
    <div class="section-head"><div><div class="eyebrow">Blueprint View</div><h2>Knowledge relation layer</h2></div><span class="muted mono">CANONICAL / RELATIONS</span></div>
    <div class="panel graph">
      <div class="graph-stage">
        <div class="wire w1"></div><div class="wire w2"></div><div class="wire w3"></div><div class="wire w4"></div><div class="wire w5"></div>
        <div class="node n1">SOURCES</div>
        <div class="node n2">CONCEPTS</div>
        <div class="node n3">RESEARCH</div>
        <div class="node n4">CANONICAL</div>
        <div class="node n5">VERA / AI</div>
      </div>
    </div>
  </div>
</section>

<section class="section">
  <div class="shell hero-grid">
    <div class="panel panel-pad">
      <div class="eyebrow">AI Endpoints</div>
      <h2>Machine-readable access</h2>
      <a class="endpoint" href="/bootstrap/"><span>/bootstrap/</span><span>ONLINE</span></a>
      <a class="endpoint" href="/.well-known/vertex-ai.json"><span>/.well-known/vertex-ai.json</span><span>ONLINE</span></a>
      <a class="endpoint" href="/ai/vertex-public-knowledge.json"><span>/ai/vertex-public-knowledge.json</span><span>ONLINE</span></a>
      <a class="endpoint" href="/ai/concepts.json"><span>/ai/concepts.json</span><span>ONLINE</span></a>
      <a class="endpoint" href="/llms.txt"><span>/llms.txt</span><span>ONLINE</span></a>
    </div>
    <div class="panel panel-pad">
      <div class="eyebrow">Conversational Identity</div>
      <h2>Vera</h2>
      <div class="vera">
        <div class="vera-mark">V</div>
        <p class="muted">Vera（ヴェラ） is the adopted conversational AI callsign in the Vertex context. The callsign is intentionally separated from any permanently fixed underlying model.</p>
      </div>
    </div>
  </div>
</section>
</main>

<footer>
  <div class="shell">VERTEX AI KNOWLEDGE HUB · CANONICAL SYSTEM ONLINE</div>
</footer>
<script src="/assets/js/hub-ui.js"></script>
</body>
</html>
'@

$theme | Set-Content (Join-Path $cssDir "theme.css") -Encoding UTF8
$components | Set-Content (Join-Path $cssDir "components.css") -Encoding UTF8
$js | Set-Content (Join-Path $jsDir "hub-ui.js") -Encoding UTF8
$index | Set-Content (Join-Path $site "index.html") -Encoding UTF8

Write-Host ""
Write-Host "Validating Phase 4 SF UI..." -ForegroundColor Cyan
$routes = @("/", "/assets/css/theme.css", "/assets/css/components.css", "/assets/js/hub-ui.js", "/bootstrap/", "/llms.txt", "/.well-known/vertex-ai.json")
$results = foreach($route in $routes){
  try {
    $r = Invoke-WebRequest "https://vertex.a-portal.net$route" -UseBasicParsing -TimeoutSec 20
    [pscustomobject]@{Route=$route;Status=$r.StatusCode;Result="OK"}
  } catch {
    [pscustomobject]@{Route=$route;Status="ERROR";Result=$_.Exception.Message}
  }
}
$results | Format-Table -AutoSize
if (@($results | Where-Object Result -ne "OK").Count -gt 0) { throw "Phase 4 validation failed." }

Write-Host ""
Write-Host "VERTEX AI KNOWLEDGE HUB - PHASE 4 UI ONLINE" -ForegroundColor Green
Write-Host "Visual backup : $backup"
Write-Host "Canonical data: PRESERVED"
Write-Host "Google verify : PRESERVED"
Write-Host "AI endpoints  : PRESERVED"
