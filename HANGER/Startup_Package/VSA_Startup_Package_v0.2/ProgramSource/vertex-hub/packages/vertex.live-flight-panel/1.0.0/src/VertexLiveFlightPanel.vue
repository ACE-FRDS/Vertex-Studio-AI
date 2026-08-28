<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import {
  desktop,
  liveSessionLatest,
  liveSessionTail,
  type LiveSessionSnapshot,
} from './hub-transport'

const latest = ref<LiveSessionSnapshot | null>(null)
const timeline = ref<LiveSessionSnapshot[]>([])
const expanded = ref(false)
const error = ref('')
let timer: number | undefined
let working = false

const online = computed(() => desktop())
const executions = computed(() => {
  if (latest.value?.dispatch?.executions?.length) {
    return latest.value.dispatch.executions
  }

  const dispatchId = latest.value?.dispatch?.dispatch_id
  const previous = [...timeline.value]
    .reverse()
    .find((item) =>
      item.dispatch?.dispatch_id === dispatchId
      && item.dispatch?.executions?.length,
    )

  return previous?.dispatch?.executions ?? []
})

const scheduledMissions = computed(() => {
  if (latest.value?.dispatch?.mission_set?.length) {
    return latest.value.dispatch.mission_set
  }

  if (latest.value?.wave?.ready?.length) {
    return latest.value.wave.ready
  }

  if (latest.value?.dispatch?.confirmed_missions?.length) {
    return latest.value.dispatch.confirmed_missions
  }

  return latest.value?.wave?.missions ?? []
})

const processResultCount = computed(
  () => latest.value?.dispatch?.process_result_count ?? 0,
)

function compact(value: string | undefined, max = 34) {
  if (!value) return '-'
  if (value.length <= max) return value
  return `${value.slice(0, max - 3)}...`
}

async function refresh() {
  if (!online.value || working) return
  working = true
  try {
    const [next, history] = await Promise.all([
      liveSessionLatest(),
      liveSessionTail(24),
    ])
    latest.value = next
    timeline.value = history
    error.value = ''
  } catch (reason) {
    error.value = String(reason)
  } finally {
    working = false
  }
}

onMounted(() => {
  void refresh()
  timer = window.setInterval(() => void refresh(), 350)
})

onUnmounted(() => {
  if (timer !== undefined) window.clearInterval(timer)
})
</script>

<template>
  <section class="flight" :class="{ expanded }">
    <button class="toggle" @click="expanded = !expanded">
      <span class="pulse" :class="{ on: Boolean(latest) }"></span>
      LIVE FLIGHT
    </button>

    <div class="cell">
      <small>SESSION</small>
      <strong>{{ compact(latest?.session?.session_id) }}</strong>
    </div>

    <div class="cell">
      <small>STATUS</small>
      <strong>{{ latest?.session?.status || '-' }}</strong>
    </div>

    <div class="cell">
      <small>WAVE</small>
      <strong>{{ compact(latest?.wave?.wave_id) }}</strong>
    </div>

    <div class="cell">
      <small>DISPATCH</small>
      <strong>{{ compact(latest?.dispatch?.dispatch_id) }}</strong>
    </div>

    <div class="cell">
      <small>EXECUTION IDs</small>
      <strong>{{ executions.length }}</strong>
    </div>

    <div class="cell">
      <small>GENESIS</small>
      <strong>{{ latest?.genesis?.event_count ?? 0 }}</strong>
    </div>

    <div class="cell">
      <small>VSP</small>
      <strong>{{ latest?.vsp ? 'BOUND' : '-' }}</strong>
    </div>

    <div class="cell">
      <small>EVENT</small>
      <strong>{{ latest?.kind || 'WAITING' }}</strong>
    </div>

    <span v-if="error" class="error">{{ error }}</span>

    <div v-if="expanded" class="detail">
      <section>
        <h4>Scheduled Missions</h4>
        <article
          v-for="mission in scheduledMissions"
          :key="mission"
        >
          <strong>{{ mission }}</strong>
          <span>SCHEDULED</span>
          <small>
            Wave mission set. No inferred Mission-to-Execution mapping.
          </small>
        </article>

        <h4>Execution IDs</h4>
        <article
          v-for="(execution, index) in executions"
          :key="index"
        >
          <strong>{{ execution.execution_id || '-' }}</strong>
          <span>DISPATCHED</span>
          <small>
            Agent/Mission ownership is not inferred from this thin dispatch contract.
          </small>
        </article>

        <article v-if="processResultCount > 0">
          <strong>Completed process results</strong>
          <span>{{ processResultCount }}</span>
          <small>
            Confirmed completed mission evidence is shown in the Mission set.
          </small>
        </article>
      </section>

      <section>
        <h4>Genesis</h4>
        <pre>Genesis event count: {{ latest?.genesis?.event_count ?? 0 }}</pre>
      </section>

      <section>
        <h4>VSP Checkpoint</h4>
        <pre>{{ latest?.vsp?.checkpoint_debug || 'No completed-wave checkpoint yet.' }}</pre>
      </section>

      <section class="timeline">
        <h4>Live Timeline</h4>
        <article
          v-for="(item, index) in [...timeline].reverse()"
          :key="`${item.timestamp_ms}:${index}`"
        >
          <strong>{{ item.kind }}</strong>
          <span>{{ item.session?.status || '-' }}</span>
          <small>
            {{ compact(item.wave?.wave_id, 22) }}
            / {{ compact(item.dispatch?.dispatch_id, 22) }}
          </small>
        </article>
      </section>
    </div>
  </section>
</template>

<style scoped>
.flight {
  display: grid;
  grid-template-columns: 96px repeat(8, minmax(80px, 1fr));
  min-height: 46px;
  border-bottom: 1px solid #283346;
  background: #0d131d;
  color: #e9eef8;
  font-family: Inter, ui-sans-serif, system-ui, sans-serif;
}
.toggle {
  border: 0;
  border-right: 1px solid #283346;
  background: #121b28;
  color: #dfe8f7;
  font-size: 10px;
  font-weight: 800;
  cursor: pointer;
}
.pulse {
  display: inline-block;
  width: 7px;
  height: 7px;
  margin-right: 5px;
  border-radius: 50%;
  background: #707c90;
}
.pulse.on {
  background: #42d99f;
  box-shadow: 0 0 9px rgba(66, 217, 159, .8);
}
.cell {
  min-width: 0;
  padding: 7px 8px;
  border-right: 1px solid #202a3b;
}
.cell small,
.cell strong {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.cell small {
  color: #7f8ca2;
  font-size: 8px;
  letter-spacing: .08em;
}
.cell strong {
  margin-top: 3px;
  font: 10px ui-monospace, SFMono-Regular, Consolas, monospace;
}
.error {
  grid-column: 1 / -1;
  padding: 5px 8px;
  color: #ff8a98;
  font: 10px Consolas, monospace;
}
.detail {
  grid-column: 1 / -1;
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  max-height: 270px;
  overflow: auto;
  border-top: 1px solid #283346;
  background: #090d14;
}
.detail > section {
  min-width: 0;
  padding: 8px;
  border-right: 1px solid #202a3b;
}
.detail h4 {
  margin: 0 0 7px;
  color: #9eacc2;
  font-size: 10px;
}
.detail article {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 3px 8px;
  margin-bottom: 5px;
  padding: 5px;
  border: 1px solid #263147;
  border-radius: 5px;
  background: #0e1520;
  font: 9px Consolas, monospace;
}
.detail article small {
  grid-column: 1 / -1;
  color: #8491a6;
}
.detail pre {
  max-height: 190px;
  margin: 0;
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-word;
  color: #b8c5d8;
  font: 9px/1.4 Consolas, monospace;
}
@media (max-width: 1280px) {
  .flight {
    grid-template-columns: 90px repeat(4, 1fr);
  }
  .cell:nth-of-type(n+6) {
    display: none;
  }
  .detail {
    grid-template-columns: 1fr 1fr;
  }
}
</style>