<template>
  <svg class="knowledge-brain-icon" viewBox="0 0 32 32" aria-hidden="true" focusable="false">
    <path
      class="head-silhouette"
      d="M17.15 1.7C9.55 1.7 4.2 6.88 4.2 13.75v1.16L1.08 18.7a1.18 1.18 0 0 0 .91 1.93h2.45v9.67h13.72v-5.27c6.36-.5 11.3-5.55 11.3-11.68C29.46 6.78 24.36 1.7 17.15 1.7Z"
    />
    <path
      class="ai-window"
      d="M17.2 4.05c-6.12 0-10.43 4.03-10.43 9.7v1.23h20.1v-1.23c0-5.53-4.12-9.7-9.67-9.7Z"
    />
    <path class="circuit" d="M7.05 10.25h3.15V7.3h2.1m9.55 0h2.08v2.95h2.74M7.05 13.25h3.45m12.9 0h3.27M10.2 10.25v2.95m13.73-2.95v2.95" />
    <circle class="node" cx="7.05" cy="10.25" r=".9" />
    <circle class="node" cx="12.3" cy="7.3" r=".9" />
    <circle class="node" cx="21.85" cy="7.3" r=".9" />
    <circle class="node" cx="26.67" cy="10.25" r=".9" />
    <circle class="node" cx="7.05" cy="13.25" r=".9" />
    <circle class="node" cx="26.67" cy="13.25" r=".9" />
    <text class="ai-label" x="17" y="13.25" text-anchor="middle">AI</text>
  </svg>
</template>

<style scoped>
.knowledge-brain-icon { display: block; overflow: visible; }
.head-silhouette { fill: currentColor; stroke: currentColor; stroke-width: 1.1; stroke-linejoin: round; }
.ai-window { fill: var(--bg-panel, #0c121a); stroke: currentColor; stroke-width: .95; }
.circuit { fill: none; stroke: currentColor; stroke-width: .9; stroke-linecap: round; stroke-linejoin: round; }
.node { fill: currentColor; }
.ai-label { fill: currentColor; font-family: Inter, "Segoe UI", sans-serif; font-size: 7.4px; font-weight: 900; letter-spacing: -.35px; }
</style>
