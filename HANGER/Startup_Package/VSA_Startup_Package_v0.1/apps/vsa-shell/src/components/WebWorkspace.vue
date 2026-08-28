<script setup lang="ts">
import {ref} from "vue";
const mode=ref("Static Website");
const modes=["Static Website","Dynamic Website","Web App"];
</script>
<template>
 <div class="web">
  <aside class="panel"><h3>Project Type</h3><button v-for="m in modes" @click="mode=m">{{m}}</button>
  <h3>Structure</h3><p>index</p><p>assets</p><p>components</p><p>routes</p></aside>
  <main class="preview"><div class="browser"><div class="url">localhost / {{mode}}</div><h1>Live Visual Web Workspace</h1><p>Canvas ↔ Definition ↔ Code ↔ Runtime Placement</p><button>Human editable button</button></div></main>
  <aside class="panel"><h3>Responsive</h3><p>Desktop</p><p>Tablet</p><p>Mobile</p><h3>Publish</h3><p>Static</p><p>Server</p><p>Edge</p></aside>
 </div>
</template>
