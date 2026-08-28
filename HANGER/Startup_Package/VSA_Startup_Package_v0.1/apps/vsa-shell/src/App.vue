<script setup lang="ts">
import {ref,computed} from "vue";
import {workspaces,type WorkspaceId} from "./domain";
import DesignerCanvas from "./components/DesignerCanvas.vue";
import WebWorkspace from "./components/WebWorkspace.vue";
import Mothership from "./components/Mothership.vue";
const active=ref<WorkspaceId>("mothership");
const current=computed(()=>workspaces.find(w=>w.id===active.value)!);
</script>

<template>
  <div class="shell">
    <aside class="rail">
      <div class="brand">VSA</div>
      <button v-for="w in workspaces" :key="w.id" :class="{active:active===w.id}" @click="active=w.id">{{w.label}}</button>
    </aside>
    <section class="main">
      <header><b>{{current.label}}</b><span>{{current.description}}</span><em>LOCAL / HUMAN FINAL AUTHORITY</em></header>
      <Mothership v-if="active==='mothership'"/>
      <DesignerCanvas v-else-if="active==='designer'"/>
      <WebWorkspace v-else-if="active==='web'"/>
      <div v-else class="placeholder">
        <h1>{{current.label}} Workspace</h1>
        <p>This startup package includes the source contract for this workspace. Replace this placeholder with project-specific panels without changing the sibling workspace boundary.</p>
        <div class="cards">
          <article><h3>Presentation</h3><p>Human editable</p></article>
          <article><h3>Data</h3><p>Typed definition</p></article>
          <article><h3>Behavior</h3><p>Actions and scripts</p></article>
          <article><h3>Capability</h3><p>Runtime placement</p></article>
        </div>
      </div>
      <footer>RPG presentation: ON · Architecture truth: observable · No Fake Completion</footer>
    </section>
  </div>
</template>
