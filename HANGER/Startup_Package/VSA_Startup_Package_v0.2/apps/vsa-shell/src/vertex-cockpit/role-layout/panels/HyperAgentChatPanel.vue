<script setup lang="ts">
import { computed, ref } from 'vue'
import type { CockpitTelemetry } from '../../cockpitTelemetry'
import CockpitPanelFrame from '../../panels/CockpitPanelFrame.vue'

const props = defineProps<{
  telemetry: CockpitTelemetry
}>()

const draft = ref('')

const liveLabel = computed(() =>
  props.telemetry.liveOnline ? 'LIVE CONTEXT' : 'LINK UNBOUND',
)

const canTransmit = computed(() => false)
</script>

<template>
  <CockpitPanelFrame
    title="HYPERAGENT // CHAT"
    subtitle="HUMAN INTENT GATEWAY"
    panel-id="hyperagent-chat"
    dockable
    :status="liveLabel"
    :status-tone="telemetry.liveOnline ? 'green' : 'muted'"
  >
    <div class="chat-panel">
      <section class="agent-identity">
        <div class="agent-sigil" aria-hidden="true">
          <span class="sigil-core" />
          <span class="sigil-ring ring-a" />
          <span class="sigil-ring ring-b" />
        </div>

        <div class="agent-copy">
          <span class="eyebrow">HYPER AGENT</span>
          <strong>INTENT INTERFACE</strong>
          <small>
            {{
              telemetry.liveOnline
                ? 'Mothership live context observed'
                : 'Conversation transport is not wired yet'
            }}
          </small>
        </div>
      </section>

      <section class="chat-history">
        <div class="system-note">
          <span>HUMAN → HYPERAGENT</span>
          <p>
            This panel is the primary entry point for human intent,
            correction, priority and direction.
          </p>
        </div>

        <div class="context-card">
          <div>
            <span>SESSION</span>
            <strong>{{ telemetry.sessionId || 'NO LIVE SESSION' }}</strong>
          </div>
          <div>
            <span>WAVE</span>
            <strong>{{ telemetry.waveId || '—' }}</strong>
          </div>
          <div>
            <span>DISPATCH</span>
            <strong>{{ telemetry.dispatchId || '—' }}</strong>
          </div>
        </div>

        <div class="empty-history">
          <span>CONVERSATION HISTORY</span>
          <strong>TRANSPORT UNBOUND</strong>
          <p>
            No synthetic conversation is generated.
          </p>
        </div>
      </section>

      <section class="intent-composer">
        <textarea
          v-model="draft"
          rows="4"
          placeholder="Tell HyperAgent what you want to build, change, inspect, or prioritize..."
        />

        <div class="composer-actions">
          <span class="intent-state">
            {{ draft.length }} chars
          </span>

          <button
            type="button"
            :disabled="!canTransmit"
            title="HyperAgent conversation transport is not wired yet"
          >
            TRANSMIT
          </button>
        </div>

        <div class="transport-note">
          HYPERAGENT MESSAGE TRANSPORT: UNBOUND — INPUT IS NOT SENT OR FAKED
        </div>
      </section>
    </div>
  </CockpitPanelFrame>
</template>

<style scoped>
.chat-panel {
  display: grid;
  min-height: 520px;
  height: 100%;
  grid-template-rows: auto minmax(0, 1fr) auto;
  background:
    radial-gradient(circle at 45% 0%, rgba(124,92,255,.08), transparent 28%),
    rgba(6,8,17,.72);
}

.agent-identity {
  display: grid;
  grid-template-columns: 74px minmax(0, 1fr);
  align-items: center;
  gap: 14px;
  padding: 16px;
  border-bottom: 1px solid var(--vertex-line);
}

.agent-sigil {
  position: relative;
  width: 60px;
  height: 60px;
  border: 1px solid rgba(169,140,255,.35);
  border-radius: 14px;
  background:
    radial-gradient(circle, rgba(124,92,255,.22), rgba(10,12,27,.86) 62%);
  box-shadow: inset 0 0 24px rgba(98,216,255,.04);
}

.sigil-core,
.sigil-ring {
  position: absolute;
  top: 50%;
  left: 50%;
}

.sigil-core {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  transform: translate(-50%, -50%);
  background: var(--vertex-blue-bright);
  box-shadow:
    0 0 10px rgba(169,140,255,.8),
    0 0 26px rgba(124,92,255,.38);
}

.sigil-ring {
  width: 34px;
  height: 34px;
  border: 1px solid rgba(98,216,255,.26);
  border-radius: 50%;
}

.ring-a {
  transform: translate(-50%, -50%) rotate(35deg) scaleY(.44);
}

.ring-b {
  transform: translate(-50%, -50%) rotate(-42deg) scaleX(.44);
}

.agent-copy {
  min-width: 0;
}

.agent-copy span,
.agent-copy strong,
.agent-copy small {
  display: block;
}

.eyebrow {
  color: var(--vertex-cyan, #62d8ff);
  font: 750 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .08em;
}

.agent-copy strong {
  margin-top: 6px;
  color: #dce3f4;
  font-size: 16px;
}

.agent-copy small {
  margin-top: 7px;
  color: var(--vertex-muted);
  font-size: 11px;
}

.chat-history {
  min-height: 0;
  padding: 14px;
  overflow: auto;
}

.system-note,
.empty-history,
.context-card {
  border: 1px solid rgba(58,66,108,.72);
  border-radius: 6px;
  background:
    linear-gradient(180deg, rgba(18,22,43,.74), rgba(9,11,23,.78));
}

.system-note {
  padding: 13px;
}

.system-note span,
.empty-history span {
  color: var(--vertex-blue-bright);
  font: 750 10px/1 ui-monospace, Consolas, monospace;
  letter-spacing: .06em;
}

.system-note p,
.empty-history p {
  margin: 8px 0 0;
  color: #8995b2;
  font-size: 12px;
  line-height: 1.5;
}

.context-card {
  display: grid;
  margin-top: 10px;
  grid-template-columns: 1fr;
}

.context-card > div {
  min-width: 0;
  padding: 10px 12px;
  border-bottom: 1px solid rgba(52,61,98,.58);
}

.context-card > div:last-child {
  border-bottom: 0;
}

.context-card span,
.context-card strong {
  display: block;
}

.context-card span {
  color: #687593;
  font: 720 9px/1 ui-monospace, Consolas, monospace;
}

.context-card strong {
  margin-top: 5px;
  overflow: hidden;
  color: #aab5cd;
  text-overflow: ellipsis;
  white-space: nowrap;
  font: 700 11px/1.2 ui-monospace, Consolas, monospace;
}

.empty-history {
  margin-top: 10px;
  padding: 18px 13px;
}

.empty-history strong {
  display: block;
  margin-top: 8px;
  color: #c3cae0;
  font: 760 13px/1.2 ui-monospace, Consolas, monospace;
}

.intent-composer {
  padding: 12px;
  border-top: 1px solid var(--vertex-line);
  background: rgba(7,9,18,.88);
}

.intent-composer textarea {
  box-sizing: border-box;
  width: 100%;
  min-height: 92px;
  resize: vertical;
  padding: 12px;
  border: 1px solid #343c62;
  border-radius: 6px;
  outline: none;
  background: #090c19;
  color: #dbe2f2;
  font: 500 13px/1.45 "Segoe UI", sans-serif;
}

.intent-composer textarea:focus {
  border-color: rgba(169,140,255,.72);
  box-shadow: 0 0 0 3px rgba(124,92,255,.08);
}

.composer-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 9px;
}

.intent-state {
  color: #66718f;
  font: 700 10px/1 ui-monospace, Consolas, monospace;
}

.composer-actions button {
  height: 34px;
  padding: 0 15px;
  border: 1px solid #4c427b;
  border-radius: 4px;
  background: linear-gradient(180deg, #241d4d, #171630);
  color: #bcb3d8;
  font: 800 10px/1 ui-monospace, Consolas, monospace;
}

.composer-actions button:disabled {
  cursor: not-allowed;
  opacity: .46;
}

.transport-note {
  margin-top: 9px;
  color: #6a708a;
  font: 700 9px/1.35 ui-monospace, Consolas, monospace;
}
</style>