<template>
  <section class="bootstrap-panel">
    <header><strong>Git</strong><span>BOOTSTRAP</span></header>
    <div class="body">
      <p>V7R1 Self-Bootstrap により生成された互換パネルです。</p>
      <p>既存のV6実装が存在する場合はそちらを優先して保持します。</p>
    </div>
  </section>
</template>

<style scoped>
.bootstrap-panel{
  display:grid;height:100%;grid-template-rows:40px minmax(0,1fr);
  background:#080a16
}
header{
  display:flex;align-items:center;justify-content:space-between;
  padding:0 8px;border-bottom:1px solid #29304d;background:#0d1020
}
header strong{color:#cbd3e6;font-size:10px}
header span{color:#8b78d0;font-size:7px}
.body{padding:10px;overflow:auto;color:#6f7a98;font-size:9px;line-height:1.5}
</style>