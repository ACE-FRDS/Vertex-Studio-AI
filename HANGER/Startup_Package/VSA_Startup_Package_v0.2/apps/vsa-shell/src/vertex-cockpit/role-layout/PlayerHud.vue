<script setup lang="ts">
import type { CockpitTelemetry } from '../cockpitTelemetry'

defineProps<{
  telemetry: CockpitTelemetry
}>()
</script>

<template>
  <footer class="player-hud">
    <section class="hud-player">
      <div class="player-sigil">
        <span>V</span>
      </div>
      <div>
        <small>PLAYER</small>
        <strong>CAPTAIN</strong>
      </div>
    </section>

    <section class="hud-stat">
      <small>LEVEL</small>
      <strong>UNBOUND</strong>
      <div class="xp-track">
        <span />
      </div>
      <em>XP LINK UNBOUND</em>
    </section>

    <section class="hud-stat vx">
      <small>VX</small>
      <strong>UNBOUND</strong>
      <em>GAME CURRENCY LINK</em>
    </section>

    <section class="hud-stat">
      <small>RANK</small>
      <strong>UNBOUND</strong>
      <em>RPG PROFILE LINK</em>
    </section>

    <section class="hud-stat quest">
      <small>QUEST</small>
      <strong>NO ACTIVE QUEST</strong>
      <em>QUEST SYSTEM UNBOUND</em>
    </section>

    <section class="hud-stat world">
      <small>WORLD STATUS</small>
      <strong :class="{ online: telemetry.runtimeOnline }">
        {{ telemetry.runtimeOnline ? 'RUNTIME ONLINE' : 'NO SIGNAL' }}
      </strong>
      <em>{{ telemetry.projectLabel }}</em>
    </section>

    <section class="hud-stat drone">
      <small>DRONE HOST</small>
      <strong>UNBOUND</strong>
      <em>HOST CONTRACT RESERVED</em>
    </section>
  </footer>
</template>

<style scoped>
.player-hud {
  display: grid;
  min-width: 0;
  height: 72px;
  grid-template-columns:
    220px
    190px
    170px
    170px
    minmax(240px,1fr)
    minmax(220px,.9fr)
    210px;
  align-items: stretch;
  border-top: 1px solid rgba(111,88,196,.72);
  background:
    radial-gradient(circle at 14% -90%, rgba(124,92,255,.22), transparent 42%),
    linear-gradient(90deg, #0c0d1e, #080a16 42%, #0c0d1e);
  box-shadow:
    0 -1px 0 rgba(169,140,255,.08),
    0 -12px 30px rgba(0,0,0,.18);
}

.player-hud > section {
  min-width: 0;
  padding: 11px 14px;
  border-right: 1px solid rgba(52,60,99,.72);
}

.player-hud > section:last-child {
  border-right: 0;
}

.hud-player {
  display: flex;
  align-items: center;
  gap: 12px;
}

.player-sigil {
  display: grid;
  width: 42px;
  height: 42px;
  flex: none;
  place-items: center;
  border: 1px solid rgba(169,140,255,.52);
  transform: rotate(45deg);
  background:
    radial-gradient(circle, rgba(124,92,255,.27), rgba(15,15,37,.92) 65%);
  box-shadow: 0 0 18px rgba(124,92,255,.10);
}

.player-sigil span {
  transform: rotate(-45deg);
  color: var(--vertex-blue-bright);
  font-size: 18px;
  font-weight: 850;
}

.player-hud small,
.player-hud strong,
.player-hud em {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.player-hud small {
  color: #667392;
  font: 750 9px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .08em;
}

.player-hud strong {
  margin-top: 6px;
  color: #c9d1e5;
  font: 750 13px/1 ui-monospace, Consolas, monospace;
}

.player-hud em {
  margin-top: 6px;
  color: #596581;
  font: 650 8px/1 ui-monospace, Consolas, monospace;
  font-style: normal;
}

.hud-player strong {
  color: #e2e5f2;
  font-size: 15px;
}

.vx strong {
  color: var(--vertex-blue-bright);
}

.world strong.online {
  color: var(--vertex-green);
}

.xp-track {
  height: 4px;
  margin-top: 8px;
  overflow: hidden;
  border-radius: 6px;
  background: #171b30;
}

.xp-track span {
  display: block;
  width: 0;
  height: 100%;
  background: linear-gradient(90deg, var(--vertex-blue), var(--vertex-cyan, #62d8ff));
}

@media (max-width: 1600px) {
  .player-hud {
    grid-template-columns:
      180px
      150px
      130px
      130px
      minmax(190px,1fr)
      minmax(180px,.9fr);
  }

  .drone {
    display: none;
  }
}

@media (max-width: 1200px) {
  .player-hud {
    grid-template-columns: 160px 130px 110px minmax(180px,1fr);
  }

  .hud-stat:nth-of-type(4),
  .world,
  .drone {
    display: none;
  }
}
</style>