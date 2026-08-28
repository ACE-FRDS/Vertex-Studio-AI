<script setup lang="ts">
import {ref} from "vue";
const selected=ref(0);
const nodes=ref([
 {name:"Hero",x:72,y:64,w:460,h:160,type:"Frame"},
 {name:"Primary Button",x:104,y:248,w:180,h:52,type:"Button"},
 {name:"Customer Name",x:104,y:320,w:320,h:48,type:"Field"}
]);
</script>
<template>
 <div class="workspace-grid">
  <aside class="panel"><h3>Layers</h3><button v-for="(n,i) in nodes" @click="selected=i">{{n.type}} · {{n.name}}</button></aside>
  <main class="canvas">
    <div v-for="(n,i) in nodes" class="node" :class="{selected:selected===i}"
      :style="{left:n.x+'px',top:n.y+'px',width:n.w+'px',height:n.h+'px'}" @click="selected=i">
      {{n.name}}
    </div>
  </main>
  <aside class="panel"><h3>Inspector</h3>
    <p>Appearance</p><p>Data</p><p>Action</p><p>State</p><p>Permission</p><p>Validation</p><p>Runtime: AUTO</p>
    <small>Human edits are Ground Truth.</small>
  </aside>
 </div>
</template>
