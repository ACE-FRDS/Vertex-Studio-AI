<script setup lang="ts">
const facilities=[
 ["司令室","ARD / Mission / Party / RCC"],["ドック","Build / Repair / Upgrade"],["倉庫","Model / Package / Asset / Theme"],
 ["格納庫","Agent / Drone / Portable"],["カタパルト","Mission Dispatch"],["観測所","Observatory / Benchmark"],
 ["工廠","Code / VXN / UI / Package"],["管制塔","Provider / Runtime / Job"],["補給所","Capability on Demand"],
 ["図書館","VCC / Knowledge / Genesis"],["演習場","LLM / RCC Test"],["隔離区画","Sandbox / Untrusted"]
];
</script>
<template><div class="mothership"><article v-for="f in facilities"><h2>{{f[0]}}</h2><p>{{f[1]}}</p></article></div></template>
