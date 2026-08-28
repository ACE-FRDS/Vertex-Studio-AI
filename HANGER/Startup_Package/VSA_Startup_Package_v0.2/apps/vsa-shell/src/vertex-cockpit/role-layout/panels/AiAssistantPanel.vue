<script setup lang="ts">
import CockpitPanelFrame from '../../panels/CockpitPanelFrame.vue'
</script>

<template>
  <CockpitPanelFrame
    title="AI ASSISTANT"
    subtitle="SUGGESTION SURFACE"
    panel-id="ai-assistant"
    dockable
    status="UNBOUND"
    status-tone="muted"
  >
    <div class="unbound-panel">
      <span>ASSISTANT SUGGESTION STREAM</span>
      <strong>NO CURRENT SUGGESTION</strong>
      <p>No synthetic output is generated.</p>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.unbound-panel {
  min-height: 180px;
  padding: 16px;
  background:
    radial-gradient(circle at 50% 0%, rgba(124,92,255,.04), transparent 38%),
    rgba(8,10,20,.92);
}
.unbound-panel span {
  color: var(--vertex-blue-bright);
  font: 750 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .06em;
}
.unbound-panel strong {
  display: block;
  margin-top: 12px;
  color: #c2cbe0;
  font: 760 14px/1.2 ui-monospace, Consolas, monospace;
}
.unbound-panel p {
  margin: 10px 0 0;
  color: #707c99;
  font-size: 11px;
  line-height: 1.45;
}
</style>