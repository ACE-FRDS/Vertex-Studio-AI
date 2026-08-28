<script setup lang="ts">
import VertexCockpitShell from '../vertex-cockpit/VertexCockpitShell.vue'
import VertexMainEditor from '../vertex-cockpit/workspace/VertexMainEditor.vue'
import VertexHubDock from '../vertex-hub/VertexHubDock.vue'
import VertexLivePreview from '../vertex-preview/VertexLivePreview.vue'
</script>

<template>
  <main class="vsa-desktop-root">
    <VertexCockpitShell>
      <VertexMainEditor />
    </VertexCockpitShell>
    <VertexHubDock />
    <VertexLivePreview />
  </main>
</template>

<style scoped>
.vsa-desktop-root{
  position:fixed;
  inset:0;
  width:100vw;
  height:100vh;
  min-width:0;
  min-height:0;
  margin:0;
  padding:0;
  overflow:hidden;
  border:0;
  border-radius:0;
  background:#070812;
  box-shadow:none;
}
</style>