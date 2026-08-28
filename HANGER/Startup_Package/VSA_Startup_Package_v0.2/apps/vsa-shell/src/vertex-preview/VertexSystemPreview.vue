<template>
  <main class="surface">
    <header class="surface-header">
      <div class="brand">
        <div class="vertex-mark">
          <span>V</span>
        </div>
        <div>
          <p class="eyebrow">VERTEX // LIVE DEVELOPMENT SURFACE</p>
          <h1>Visual systems online.</h1>
          <p class="subtitle">
            Edit. Save. Observe. Correct. No more blind development.
          </p>
        </div>
      </div>

      <div class="status-cluster">
        <article>
          <span>PREVIEW</span>
          <strong>ONLINE</strong>
        </article>
        <article>
          <span>HMR</span>
          <strong>LINKED</strong>
        </article>
        <article>
          <span>TRUST</span>
          <strong>STATIC</strong>
        </article>
      </div>
    </header>

    <section class="command-strip">
      <span class="command-active">LIVE SURFACE</span>
      <span>COMPONENT REGISTRY</span>
      <span>VERTEXHUB</span>
      <span>VSP</span>
      <span>INSPECTOR</span>
    </section>

    <section class="surface-grid">
      <article class="primary-card">
        <div class="card-heading">
          <div>
            <p class="eyebrow">CURRENT MISSION</p>
            <h2>Remove the blindfold.</h2>
          </div>
          <span class="badge">GUI LIVE DEV</span>
        </div>

        <div class="flight-line">
          <div class="node completed">
            <span>01</span>
            <strong>EDIT</strong>
            <small>MONACO</small>
          </div>
          <i />
          <div class="node active">
            <span>02</span>
            <strong>SAVE</strong>
            <small>CTRL + S</small>
          </div>
          <i />
          <div class="node">
            <span>03</span>
            <strong>HMR</strong>
            <small>VITE</small>
          </div>
          <i />
          <div class="node">
            <span>04</span>
            <strong>SEE</strong>
            <small>PREVIEW</small>
          </div>
        </div>

        <div class="telemetry">
          <div>
            <span>VERTEX BLUE</span>
            <strong>#168CFF</strong>
          </div>
          <div>
            <span>BRIGHT BLUE</span>
            <strong>#3AB8FF</strong>
          </div>
          <div>
            <span>BACKGROUND</span>
            <strong>#070B10</strong>
          </div>
          <div>
            <span>STATUS</span>
            <strong class="green">GREEN</strong>
          </div>
        </div>
      </article>

      <article class="side-card">
        <p class="eyebrow">DOCK TELEMETRY</p>
        <h3>Development Vision</h3>

        <div class="metric">
          <span>Source visibility</span>
          <strong>ONLINE</strong>
        </div>
        <div class="metric">
          <span>GUI visibility</span>
          <strong>ONLINE</strong>
        </div>
        <div class="metric">
          <span>Hot reload</span>
          <strong>READY</strong>
        </div>
        <div class="metric">
          <span>Arbitrary eval</span>
          <strong class="red">DENIED</strong>
        </div>

        <div class="signal">
          <i />
          <span>VERTEX DEVELOPMENT NETWORK</span>
        </div>
      </article>

      <article class="lower-card">
        <div>
          <p class="eyebrow">VISUAL DOCTRINE</p>
          <h3>FME-derived. Vertex-native.</h3>
        </div>

        <div class="palette">
          <span style="--swatch:#070b10">DEEP</span>
          <span style="--swatch:#0c121a">PANEL</span>
          <span style="--swatch:#111923">RAISED</span>
          <span style="--swatch:#168cff">BLUE</span>
          <span style="--swatch:#3ab8ff">BRIGHT</span>
          <span style="--swatch:#55d69e">GREEN</span>
        </div>
      </article>
    </section>
  </main>
</template>

<style scoped>
.surface {
  --bg-deep: #070b10;
  --bg-panel: #0c121a;
  --bg-panel-raised: #111923;
  --bg-hover: #14202c;
  --line: #1c2935;
  --line-bright: #26394b;
  --text: #cbd5df;
  --muted: #718195;
  --faint: #455364;
  --blue: #168cff;
  --blue-bright: #3ab8ff;
  --green: #55d69e;
  --amber: #f1b85b;
  --red: #ff6f7c;

  min-height: 100%;
  padding: 24px;
  background:
    radial-gradient(circle at 65% -20%, rgba(20, 113, 180, .13), transparent 42%),
    linear-gradient(rgba(255,255,255,.012) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255,255,255,.012) 1px, transparent 1px),
    var(--bg-deep);
  background-size: auto, 34px 34px, 34px 34px, auto;
  color: var(--text);
  font-family: Inter, "Segoe UI", "Yu Gothic UI", system-ui, sans-serif;
}

.surface-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  min-height: 78px;
  padding: 0 18px;
  border: 1px solid var(--line-bright);
  background:
    linear-gradient(90deg, rgba(25, 135, 224, .08), transparent 28%),
    linear-gradient(180deg, #111923, #0b1118);
  box-shadow: 0 8px 26px rgba(0,0,0,.26);
}

.brand {
  display: flex;
  align-items: center;
  gap: 14px;
}

.vertex-mark {
  display: grid;
  width: 44px;
  height: 44px;
  place-items: center;
  border: 1px solid #24527a;
  transform: rotate(45deg);
  background: #0c2132;
  box-shadow: 0 0 18px rgba(22,140,255,.17);
}

.vertex-mark span {
  transform: rotate(-45deg);
  color: var(--blue-bright);
  font-size: 16px;
  font-weight: 800;
}

.eyebrow {
  margin: 0;
  color: #506275;
  font: 750 8px/1 ui-monospace, "Cascadia Code", Consolas, monospace;
  letter-spacing: .14em;
}

h1, h2, h3, p {
  margin-top: 0;
}

h1 {
  margin-bottom: 4px;
  color: #dbe7f1;
  font-size: 22px;
  font-weight: 650;
  letter-spacing: -.025em;
}

.subtitle {
  margin-bottom: 0;
  color: var(--muted);
  font-size: 10px;
}

.status-cluster {
  display: flex;
  gap: 8px;
}

.status-cluster article {
  min-width: 86px;
  padding: 9px 10px;
  border-left: 1px solid var(--line);
}

.status-cluster span,
.status-cluster strong {
  display: block;
}

.status-cluster span {
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.status-cluster strong {
  margin-top: 6px;
  color: var(--green);
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}

.command-strip {
  display: flex;
  height: 36px;
  align-items: center;
  margin-top: 8px;
  padding: 0 14px;
  gap: 20px;
  border: 1px solid var(--line);
  background: rgba(8, 13, 19, .94);
  color: var(--faint);
  font: 700 8px/1 ui-monospace, Consolas, monospace;
}

.command-active {
  position: relative;
  color: #65c5ff;
}

.command-active::after {
  position: absolute;
  right: 0;
  bottom: -12px;
  left: 0;
  height: 2px;
  background: linear-gradient(90deg, transparent, var(--blue), transparent);
  box-shadow: 0 -2px 8px rgba(22,140,255,.75);
  content: "";
}

.surface-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.6fr) minmax(240px, .6fr);
  gap: 12px;
  margin-top: 12px;
}

.primary-card,
.side-card,
.lower-card {
  border: 1px solid var(--line);
  border-radius: 6px;
  background:
    linear-gradient(155deg, rgba(17,25,35,.95), rgba(8,13,19,.97));
  box-shadow: inset 0 1px 0 rgba(255,255,255,.018);
}

.primary-card {
  padding: 18px;
}

.card-heading {
  display: flex;
  justify-content: space-between;
  align-items: start;
}

.card-heading h2 {
  margin: 5px 0 0;
  color: #dbe7f1;
  font-size: 20px;
  font-weight: 650;
}

.badge {
  padding: 5px 7px;
  border: 1px solid #28516c;
  border-radius: 4px;
  background: #0a1a25;
  color: #6fc9fb;
  font: 700 8px/1 ui-monospace, Consolas, monospace;
}

.flight-line {
  display: grid;
  grid-template-columns: auto 1fr auto 1fr auto 1fr auto;
  align-items: center;
  margin: 28px 0;
}

.flight-line > i {
  height: 1px;
  background: linear-gradient(90deg, var(--blue), var(--line-bright));
}

.node {
  display: grid;
  width: 66px;
  height: 66px;
  place-items: center;
  align-content: center;
  border: 1px solid var(--line-bright);
  border-radius: 50%;
  background: #09121a;
  text-align: center;
}

.node span {
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.node strong {
  margin-top: 5px;
  color: #9eb0c0;
  font-size: 9px;
}

.node small {
  margin-top: 3px;
  color: var(--faint);
  font: 700 6px/1 ui-monospace, Consolas, monospace;
}

.node.completed,
.node.active {
  border-color: #24658f;
}

.node.completed strong,
.node.active strong {
  color: var(--blue-bright);
}

.node.active {
  box-shadow:
    0 0 0 4px rgba(22,140,255,.05),
    0 0 18px rgba(22,140,255,.14);
}

.telemetry {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  border-top: 1px solid var(--line);
}

.telemetry > div {
  padding: 13px 10px 0;
  border-right: 1px solid var(--line);
}

.telemetry > div:last-child {
  border-right: 0;
}

.telemetry span,
.telemetry strong {
  display: block;
}

.telemetry span {
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.telemetry strong {
  margin-top: 6px;
  color: #9bacc0;
  font: 700 9px/1 ui-monospace, Consolas, monospace;
}

.green {
  color: var(--green) !important;
}

.side-card {
  padding: 18px;
}

.side-card h3 {
  margin: 6px 0 18px;
  color: #dbe7f1;
  font-size: 14px;
  font-weight: 650;
}

.metric {
  display: flex;
  justify-content: space-between;
  padding: 10px 0;
  border-top: 1px solid var(--line);
  color: var(--muted);
  font-size: 9px;
}

.metric strong {
  color: var(--green);
  font: 700 8px/1 ui-monospace, Consolas, monospace;
}

.metric strong.red {
  color: var(--red);
}

.signal {
  display: flex;
  align-items: center;
  margin-top: 18px;
  padding-top: 14px;
  gap: 8px;
  border-top: 1px solid var(--line);
  color: var(--faint);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
}

.signal i {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--green);
  box-shadow: 0 0 7px rgba(85,214,158,.6);
}

.lower-card {
  grid-column: 1 / -1;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14px 18px;
}

.lower-card h3 {
  margin: 5px 0 0;
  color: #b8c8d8;
  font-size: 12px;
}

.palette {
  display: flex;
  gap: 6px;
}

.palette span {
  position: relative;
  min-width: 60px;
  padding: 20px 8px 7px;
  border: 1px solid var(--line);
  background: #091018;
  color: var(--muted);
  font: 700 7px/1 ui-monospace, Consolas, monospace;
  text-align: center;
}

.palette span::before {
  position: absolute;
  top: 0;
  right: 0;
  left: 0;
  height: 14px;
  background: var(--swatch);
  content: "";
}

@media (max-width: 900px) {
  .surface-grid {
    grid-template-columns: 1fr;
  }

  .side-card,
  .lower-card {
    grid-column: 1;
  }

  .status-cluster {
    display: none;
  }

  .telemetry {
    grid-template-columns: 1fr 1fr;
  }
}
</style>