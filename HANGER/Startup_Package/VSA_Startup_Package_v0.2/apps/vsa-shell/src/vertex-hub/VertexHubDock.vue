<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { vertexHubUiPackages } from './catalog'
import {
  hubRuntimeState,
  installHubPackage,
  setHubPackageEnabled,
  uninstallHubPackage,
  validatedHubRegistry,
  type HubRegistry,
  type HubRegistryEntry,
  type HubRuntimeState,
} from './runtime'

type Filter = 'ALL' | 'INSTALLED' | 'ENABLED' | 'AVAILABLE'

interface BrowserPackage {
  packageId: string
  version: string
  displayName: string
  summary: string
  publisher: string
  kind: string
  channel: string
  capabilities: string[]
  runtime: string[]
  manifestSha256: string
  bundled: boolean
  registered: boolean
  installed: boolean
  enabled: boolean
  compatible: boolean
  component?: unknown
}

const open = ref(false)
const registry = ref<HubRegistry | null>(null)
const state = ref<HubRuntimeState>({
  schema: 'vertex.hub.runtime-state.v1',
  packages: [],
})
const search = ref('')
const filter = ref<Filter>('ALL')
const busy = ref('')
const error = ref('')
const activity = ref<string[]>([])

function identity(packageId: string, version: string) {
  return `${packageId}@${version}`
}

function pushActivity(message: string) {
  activity.value = [
    `${new Date().toLocaleTimeString()}  ${message}`,
    ...activity.value,
  ].slice(0, 12)
}

function catalogPackage(packageId: string, version: string) {
  return vertexHubUiPackages.find(
    (pkg) => pkg.packageId === packageId && pkg.version === version,
  )
}

function runtimePackage(packageId: string, version: string) {
  return state.value.packages.find(
    (pkg) => pkg.package_id === packageId && pkg.version === version,
  )
}

function registryVerified(entry: HubRegistryEntry) {
  const catalog = catalogPackage(entry.package_id, entry.version)

  if (!catalog) {
    return entry.status === 'registered'
  }

  return (
    entry.status === 'registered'
    && entry.manifest_sha256 === catalog.manifestSha256
  )
}

const packages = computed<BrowserPackage[]>(() => {
  const registryPackages = registry.value?.packages ?? []

  return registryPackages.map((entry) => {
    const catalog = catalogPackage(entry.package_id, entry.version)
    const runtime = runtimePackage(entry.package_id, entry.version)

    return {
      packageId: entry.package_id,
      version: entry.version,
      displayName: catalog?.displayName ?? entry.package_id,
      summary:
        catalog?.summary
        ?? 'Verified VertexHub package. Runtime execution requires a trusted catalog binding.',
      publisher: catalog?.publisher ?? 'Unknown Publisher',
      kind: entry.kind,
      channel: catalog?.channel ?? 'stable',
      capabilities: catalog?.capabilities ?? ['PACKAGE'],
      runtime: catalog?.runtime ?? ['BUILD REQUIRED'],
      manifestSha256: entry.manifest_sha256,
      bundled: Boolean(catalog),
      registered: registryVerified(entry),
      installed: Boolean(runtime),
      enabled: Boolean(runtime?.enabled),
      compatible: Boolean(catalog),
      component: catalog?.component,
    }
  })
})

const visiblePackages = computed(() => {
  const query = search.value.trim().toLowerCase()

  return packages.value.filter((pkg) => {
    const matchesQuery =
      !query
      || pkg.displayName.toLowerCase().includes(query)
      || pkg.packageId.toLowerCase().includes(query)
      || pkg.publisher.toLowerCase().includes(query)
      || pkg.capabilities.some((item) => item.toLowerCase().includes(query))

    const matchesFilter =
      filter.value === 'ALL'
      || (filter.value === 'INSTALLED' && pkg.installed)
      || (filter.value === 'ENABLED' && pkg.enabled)
      || (filter.value === 'AVAILABLE' && !pkg.installed)

    return matchesQuery && matchesFilter
  })
})

const installedCount = computed(
  () => packages.value.filter((pkg) => pkg.installed).length,
)

const enabledCount = computed(
  () => packages.value.filter((pkg) => pkg.enabled).length,
)

const verifiedCount = computed(
  () => packages.value.filter((pkg) => pkg.registered).length,
)

const enabledComponents = computed(
  () => packages.value.filter(
    (pkg) => pkg.enabled && pkg.compatible && pkg.component,
  ),
)

const registryOnline = computed(
  () => registry.value?.schema === 'vertex.hub.registry.v1',
)

async function reload() {
  error.value = ''

  try {
    const [nextRegistry, nextState] = await Promise.all([
      validatedHubRegistry(),
      hubRuntimeState(),
    ])

    registry.value = nextRegistry
    state.value = nextState
  } catch (reason) {
    error.value = String(reason)
  }
}

async function perform(
  pkg: BrowserPackage,
  action: 'INSTALL' | 'ENABLE' | 'DISABLE' | 'UNINSTALL',
) {
  const key = identity(pkg.packageId, pkg.version)

  if (!pkg.registered) {
    error.value = `Package verification failed: ${key}`
    return
  }

  busy.value = `${key}:${action}`
  error.value = ''

  try {
    if (action === 'INSTALL') {
      await installHubPackage(pkg.packageId, pkg.version)
      pushActivity(`INSTALL  ${key}`)
    }

    if (action === 'ENABLE') {
      if (!pkg.compatible) {
        throw new Error(
          `${key} is verified and installed, but requires a trusted build/catalog binding before execution.`,
        )
      }

      await setHubPackageEnabled(pkg.packageId, pkg.version, true)
      pushActivity(`ENABLE   ${key}`)
    }

    if (action === 'DISABLE') {
      await setHubPackageEnabled(pkg.packageId, pkg.version, false)
      pushActivity(`DISABLE  ${key}`)
    }

    if (action === 'UNINSTALL') {
      if (pkg.enabled) {
        await setHubPackageEnabled(pkg.packageId, pkg.version, false)
      }

      await uninstallHubPackage(pkg.packageId, pkg.version)
      pushActivity(`UNINSTALL ${key}`)
    }

    await reload()
  } catch (reason) {
    error.value = String(reason)
    pushActivity(`RED      ${key} / ${action}`)
  } finally {
    busy.value = ''
  }
}

function isBusy(pkg: BrowserPackage) {
  return busy.value.startsWith(identity(pkg.packageId, pkg.version))
}

onMounted(async () => {
  await reload()
})
</script>

<template>
  <section class="vertex-hub-host">
    <button
      class="hub-launcher"
      :class="{ online: registryOnline }"
      title="Open VertexHub Equipment Dock"
      @click="open = true"
    >
      <span class="launcher-mark">
        <span />
        <span />
        <span />
      </span>

      <span class="launcher-copy">
        <strong>VERTEX HUB</strong>
        <small>{{ enabledCount }} ONLINE · {{ installedCount }} INSTALLED</small>
      </span>

      <span class="launcher-pulse" />
    </button>

    <Teleport to="body">
      <Transition name="hub-fade">
        <div
          v-if="open"
          class="hub-backdrop"
          @mousedown.self="open = false"
        >
          <section class="hub-shell">
            <div class="hub-grid-glow" />
            <div class="hub-noise" />

            <header class="hub-command">
              <div class="brand">
                <div class="brand-sigil">
                  <span class="sigil-core"><b>V</b></span>
                  <span class="sigil-ring" />
                </div>

                <div>
                  <div class="eyebrow">VERTEX // EQUIPMENT NETWORK</div>
                  <h1>VertexHub</h1>
                  <p>Verified packages. Controlled docking. Zero blind execution.</p>
                </div>
              </div>

              <div class="command-status">
                <div class="status-block">
                  <span>REGISTRY</span>
                  <strong :class="{ green: registryOnline }">
                    {{ registryOnline ? 'VALIDATED' : 'OFFLINE' }}
                  </strong>
                </div>

                <div class="status-block">
                  <span>TRUST GATE</span>
                  <strong class="green">ENFORCED</strong>
                </div>

                <button
                  class="icon-button"
                  title="Reload Hub"
                  @click="reload"
                >
                  ↻
                </button>

                <button
                  class="close-button"
                  title="Close VertexHub"
                  @click="open = false"
                >
                  ×
                </button>
              </div>
            </header>

            <div class="hub-body">
              <aside class="hub-rail">
                <div class="rail-section">
                  <span class="rail-label">EQUIPMENT</span>

                  <button
                    v-for="item in (['ALL', 'INSTALLED', 'ENABLED', 'AVAILABLE'] as Filter[])"
                    :key="item"
                    class="rail-button"
                    :class="{ active: filter === item }"
                    @click="filter = item"
                  >
                    <span class="rail-dot" />
                    {{ item }}
                    <em v-if="item === 'ALL'">{{ packages.length }}</em>
                    <em v-else-if="item === 'INSTALLED'">{{ installedCount }}</em>
                    <em v-else-if="item === 'ENABLED'">{{ enabledCount }}</em>
                    <em v-else>{{ packages.length - installedCount }}</em>
                  </button>
                </div>

                <div class="rail-section rail-bottom">
                  <span class="rail-label">SYSTEM</span>

                  <div class="rail-meter">
                    <span>VERIFIED</span>
                    <strong>{{ verifiedCount }}/{{ packages.length }}</strong>
                  </div>

                  <div class="rail-meter">
                    <span>EXECUTION</span>
                    <strong>STATIC GATE</strong>
                  </div>

                  <div class="rail-meter">
                    <span>REMOTE CODE</span>
                    <strong class="denied">DENIED</strong>
                  </div>
                </div>
              </aside>

              <main class="hub-main">
                <section class="hub-hero">
                  <div>
                    <div class="eyebrow">MOTHERSHIP EQUIPMENT DOCK</div>
                    <h2>Build your control deck.</h2>
                    <p>
                      Install verified capabilities without surrendering the runtime boundary.
                      Packages dock only after Registry + SHA-256 validation.
                    </p>
                  </div>

                  <div class="hero-stats">
                    <article>
                      <span>AVAILABLE</span>
                      <strong>{{ packages.length }}</strong>
                    </article>

                    <article>
                      <span>INSTALLED</span>
                      <strong>{{ installedCount }}</strong>
                    </article>

                    <article>
                      <span>ACTIVE</span>
                      <strong>{{ enabledCount }}</strong>
                    </article>
                  </div>
                </section>

                <section class="toolbar">
                  <label class="search-box">
                    <span>⌕</span>
                    <input
                      v-model="search"
                      autocomplete="off"
                      spellcheck="false"
                      placeholder="Search packages, capabilities, publisher..."
                    >
                    <kbd>HUB</kbd>
                  </label>

                  <div class="toolbar-copy">
                    <span>{{ visiblePackages.length }} EQUIPMENT UNITS</span>
                    <span class="separator">/</span>
                    <span>CHANNEL STABLE</span>
                  </div>
                </section>

                <section class="package-stage">
                  <article
                    v-for="pkg in visiblePackages"
                    :key="identity(pkg.packageId, pkg.version)"
                    class="package-card"
                    :class="{
                      active: pkg.enabled,
                      installed: pkg.installed,
                      incompatible: pkg.installed && !pkg.compatible,
                    }"
                  >
                    <div class="card-topline">
                      <div class="package-icon">
                        <div class="icon-orbit" />
                        <span>{{ pkg.displayName.slice(0, 1).toUpperCase() }}</span>
                      </div>

                      <div class="package-title">
                        <div class="package-state">
                          <span
                            class="verified"
                            :class="{ bad: !pkg.registered }"
                          >
                            {{ pkg.registered ? '◆ VERIFIED' : '◇ UNVERIFIED' }}
                          </span>

                          <span v-if="pkg.enabled" class="live-state">
                            ● ONLINE
                          </span>
                          <span v-else-if="pkg.installed" class="installed-state">
                            INSTALLED
                          </span>
                          <span v-else class="available-state">
                            AVAILABLE
                          </span>
                        </div>

                        <h3>{{ pkg.displayName }}</h3>
                        <p class="package-id">
                          {{ pkg.packageId }} <span>@{{ pkg.version }}</span>
                        </p>
                      </div>

                      <div class="package-channel">
                        {{ pkg.channel.toUpperCase() }}
                      </div>
                    </div>

                    <p class="summary">{{ pkg.summary }}</p>

                    <div class="capability-row">
                      <span
                        v-for="capability in pkg.capabilities"
                        :key="capability"
                      >
                        {{ capability }}
                      </span>
                    </div>

                    <div class="runtime-row">
                      <div>
                        <span>PUBLISHER</span>
                        <strong>{{ pkg.publisher }}</strong>
                      </div>

                      <div>
                        <span>RUNTIME</span>
                        <strong>{{ pkg.runtime.join(' / ') }}</strong>
                      </div>

                      <div>
                        <span>DELIVERY</span>
                        <strong>
                          {{ pkg.bundled ? 'BUNDLED HOT' : 'BUILD REQUIRED' }}
                        </strong>
                      </div>
                    </div>

                    <div class="trust-row">
                      <span>MANIFEST</span>
                      <code>{{ pkg.manifestSha256.slice(0, 16) }}…</code>
                      <span class="trust-copy">SHA-256 LOCKED</span>
                    </div>

                    <footer class="package-actions">
                      <div class="compatibility">
                        <span
                          class="compat-dot"
                          :class="{ online: pkg.compatible }"
                        />
                        {{
                          pkg.compatible
                            ? 'RUNTIME COMPATIBLE'
                            : 'INSTALLABLE · EXECUTION GATED'
                        }}
                      </div>

                      <div class="actions">
                        <button
                          v-if="!pkg.installed"
                          class="primary-action"
                          :disabled="isBusy(pkg) || !pkg.registered"
                          @click="perform(pkg, 'INSTALL')"
                        >
                          {{ isBusy(pkg) ? 'DOCKING…' : 'INSTALL' }}
                        </button>

                        <button
                          v-else-if="pkg.compatible && !pkg.enabled"
                          class="primary-action"
                          :disabled="isBusy(pkg)"
                          @click="perform(pkg, 'ENABLE')"
                        >
                          ENABLE
                        </button>

                        <button
                          v-else-if="pkg.enabled"
                          class="secondary-action"
                          :disabled="isBusy(pkg)"
                          @click="perform(pkg, 'DISABLE')"
                        >
                          DISABLE
                        </button>

                        <button
                          v-if="pkg.installed && !pkg.enabled"
                          class="ghost-action"
                          :disabled="isBusy(pkg)"
                          @click="perform(pkg, 'UNINSTALL')"
                        >
                          UNINSTALL
                        </button>
                      </div>
                    </footer>
                  </article>

                  <div
                    v-if="visiblePackages.length === 0"
                    class="empty-state"
                  >
                    <div class="empty-orbit">
                      <span>V</span>
                    </div>
                    <strong>No equipment matches this sector.</strong>
                    <p>Adjust the filter or search signature.</p>
                  </div>
                </section>
              </main>

              <aside class="hub-inspector">
                <div class="inspector-head">
                  <span class="rail-label">DOCK TELEMETRY</span>
                  <strong>{{ busy ? 'BUSY' : 'READY' }}</strong>
                </div>

                <div class="trust-stack">
                  <article>
                    <span>Registry integrity</span>
                    <strong>SHA-256</strong>
                    <em>LOCKED</em>
                  </article>

                  <article>
                    <span>Path traversal</span>
                    <strong>DENIED</strong>
                    <em>FAIL-CLOSED</em>
                  </article>

                  <article>
                    <span>Remote import</span>
                    <strong>DENIED</strong>
                    <em>STATIC GATE</em>
                  </article>

                  <article>
                    <span>Controller state</span>
                    <strong>READ ONLY</strong>
                    <em>BOUNDARY</em>
                  </article>
                </div>

                <div class="activity-panel">
                  <div class="activity-head">
                    <span>ACTIVITY</span>
                    <small>LOCAL AUDIT MIRROR</small>
                  </div>

                  <div class="activity-list">
                    <p v-if="activity.length === 0">
                      No docking actions this session.
                    </p>

                    <code
                      v-for="line in activity"
                      :key="line"
                    >
                      {{ line }}
                    </code>
                  </div>
                </div>

                <div v-if="error" class="error-panel">
                  <span>VERTEXHUB RED</span>
                  <pre>{{ error }}</pre>
                </div>

                <div class="inspector-footer">
                  <span class="signal" />
                  <div>
                    <strong>VERTEX EQUIPMENT NETWORK</strong>
                    <small>LOCAL / VERIFIED / CONTROLLED</small>
                  </div>
                </div>
              </aside>
            </div>
          </section>
        </div>
      </Transition>
    </Teleport>

    <component
      :is="pkg.component"
      v-for="pkg in enabledComponents"
      :key="identity(pkg.packageId, pkg.version)"
    />
  </section>
</template>

<style scoped>
.vertex-hub-host {
  position: relative;
  min-width: 0;

  /* VERTEX DESIGN TOKENS — inherited from Vertex FM Engine main.scss */
  --vertex-bg-deep: #070b10;
  --vertex-bg-panel: #0c121a;
  --vertex-bg-panel-raised: #111923;
  --vertex-bg-hover: #14202c;
  --vertex-line: #1c2935;
  --vertex-line-bright: #26394b;
  --vertex-text: #cbd5df;
  --vertex-muted: #718195;
  --vertex-faint: #455364;
  --vertex-blue: #168cff;
  --vertex-blue-bright: #3ab8ff;
  --vertex-blue-soft: #102c44;
  --vertex-green: #55d69e;
  --vertex-amber: #f1b85b;
  --vertex-red: #ff6f7c;
}

.hub-launcher {
  position: absolute;
  z-index: 12;
  top: 7px;
  right: 8px;
  display: flex;
  align-items: center;
  gap: 9px;
  height: 34px;
  padding: 0 10px 0 8px;
  border: 1px solid rgba(119, 135, 171, .28);
  border-radius: 8px;
  background:
    linear-gradient(180deg, #111923, #0b1118);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, .04),
    0 6px 18px rgba(0, 0, 0, .22);
  color: #cbd5df;
  cursor: pointer;
  transition:
    border-color .18s ease,
    transform .18s ease,
    box-shadow .18s ease;
}

.hub-launcher:hover {
  transform: translateY(-1px);
  border-color: rgba(58, 184, 255, .62);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, .06),
    0 9px 24px rgba(0, 0, 0, .34),
    0 0 0 1px rgba(22, 140, 255, .09);
}

.hub-launcher.online {
  border-color: rgba(83, 224, 191, .34);
}

.launcher-mark {
  position: relative;
  width: 20px;
  height: 20px;
}

.launcher-mark span {
  position: absolute;
  border: 1px solid rgba(22, 140, 255, .78);
  transform: rotate(45deg);
}

.launcher-mark span:nth-child(1) {
  inset: 1px;
}

.launcher-mark span:nth-child(2) {
  inset: 5px;
  border-color: rgba(80, 216, 224, .85);
}

.launcher-mark span:nth-child(3) {
  inset: 9px;
  background: #168cff;
  border: 0;
}

.launcher-copy {
  text-align: left;
}

.launcher-copy strong,
.launcher-copy small {
  display: block;
}

.launcher-copy strong {
  font:
    700 9px/1.1 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: .12em;
}

.launcher-copy small {
  margin-top: 3px;
  color: #6f7e98;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .07em;
}

.launcher-pulse {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #55d69e;
  box-shadow: 0 0 10px rgba(79, 224, 178, .8);
}

.hub-backdrop {
  position: fixed;
  z-index: 10000;
  inset: 0;
  display: grid;
  place-items: center;
  padding: 26px;
  background:
    radial-gradient(circle at 50% 0%, rgba(78, 55, 132, .18), transparent 38%),
    rgba(4, 8, 12, .84);
  backdrop-filter: blur(14px) saturate(.85);
}

.hub-shell {
  position: relative;
  width: min(1540px, calc(100vw - 52px));
  height: min(900px, calc(100vh - 52px));
  overflow: hidden;
  border: 1px solid var(--vertex-line-bright);
  border-radius: 14px;
  background:
    linear-gradient(135deg, rgba(17, 25, 35, .985), rgba(7, 11, 16, .995) 55%);
  box-shadow:
    0 38px 100px rgba(0, 0, 0, .72),
    0 0 0 1px rgba(255, 255, 255, .02) inset,
    0 1px 0 rgba(255, 255, 255, .05) inset;
  color: #cbd5df;
}

.hub-grid-glow {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(rgba(130, 145, 180, .025) 1px, transparent 1px),
    linear-gradient(90deg, rgba(130, 145, 180, .025) 1px, transparent 1px);
  background-size: 40px 40px;
  mask-image: linear-gradient(to bottom, black, transparent 72%);
}

.hub-noise {
  position: absolute;
  inset: 0;
  pointer-events: none;
  opacity: .18;
  background:
    radial-gradient(circle at 18% 8%, rgba(22, 140, 255, .13), transparent 24%),
    radial-gradient(circle at 72% 0%, rgba(41, 185, 211, .11), transparent 30%);
}

.hub-command {
  position: relative;
  z-index: 2;
  display: flex;
  justify-content: space-between;
  align-items: center;
  height: 94px;
  padding: 0 24px;
  border-bottom: 1px solid var(--vertex-line-bright);
  background: rgba(11, 17, 24, .72);
}

.hub-command::after {
  position: absolute;
  right: 0;
  bottom: -1px;
  left: 0;
  height: 1px;
  background: linear-gradient(
    90deg,
    transparent,
    rgba(22, 140, 255, .70),
    transparent 72%
  );
  box-shadow: 0 0 8px rgba(22, 140, 255, .24);
  content: "";
}

.brand {
  display: flex;
  align-items: center;
  gap: 16px;
}

.brand-sigil {
  position: relative;
  display: grid;
  place-items: center;
  width: 48px;
  height: 48px;
}

.sigil-core {
  position: relative;
  z-index: 2;
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border: 1px solid rgba(58, 184, 255, .76);
  transform: rotate(45deg);
  background:
    linear-gradient(135deg, rgba(22, 140, 255, .22), rgba(27, 34, 53, .5));
  color: #e4f4ff;
  font:
    800 13px/1 Inter,
    sans-serif;
  box-shadow: 0 0 24px rgba(22, 140, 255, .18);
}

.sigil-core b {
  display: block;
  transform: rotate(-45deg);
  font: inherit;
}

.sigil-ring {
  position: absolute;
  inset: 0;
  border: 1px solid rgba(73, 199, 220, .28);
  border-radius: 50%;
}

.eyebrow {
  color: #6f7d98;
  font:
    700 8px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .19em;
}

.brand h1 {
  margin: 4px 0 0;
  font:
    650 24px/1.05 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: -.025em;
}

.brand p {
  margin: 5px 0 0;
  color: #718195;
  font: 10px/1.3 Inter, "Segoe UI", sans-serif;
}

.command-status {
  display: flex;
  align-items: center;
  gap: 10px;
}

.status-block {
  min-width: 108px;
  padding: 7px 10px;
  border-left: 1px solid rgba(120, 137, 170, .16);
}

.status-block span,
.status-block strong {
  display: block;
}

.status-block span {
  color: #455364;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .14em;
}

.status-block strong {
  margin-top: 5px;
  color: #a7b3c7;
  font:
    700 8px/1 ui-monospace,
    Consolas,
    monospace;
}

.status-block strong.green {
  color: #55dfb4;
}

.icon-button,
.close-button {
  display: grid;
  place-items: center;
  width: 32px;
  height: 32px;
  border: 1px solid rgba(117, 133, 165, .18);
  border-radius: 7px;
  background: rgba(17, 25, 35, .82);
  color: #8c9ab1;
  cursor: pointer;
}

.close-button {
  font-size: 20px;
}

.icon-button:hover,
.close-button:hover {
  border-color: rgba(58, 184, 255, .46);
  color: #dbe7f1;
}

.hub-body {
  position: relative;
  z-index: 2;
  display: grid;
  grid-template-columns: 178px minmax(0, 1fr) 250px;
  height: calc(100% - 94px);
}

.hub-rail,
.hub-inspector {
  background: rgba(8, 13, 19, .74);
}

.hub-rail {
  display: flex;
  flex-direction: column;
  padding: 22px 14px 18px;
  border-right: 1px solid var(--vertex-line);
}

.rail-section {
  display: grid;
  gap: 6px;
}

.rail-bottom {
  margin-top: auto;
  gap: 12px;
}

.rail-label {
  margin: 0 8px 5px;
  color: #455364;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .16em;
}

.rail-button {
  display: grid;
  grid-template-columns: 8px 1fr auto;
  align-items: center;
  gap: 8px;
  height: 34px;
  padding: 0 9px;
  border: 1px solid transparent;
  border-radius: 7px;
  background: transparent;
  color: #718195;
  text-align: left;
  font:
    650 9px/1 Inter,
    "Segoe UI",
    sans-serif;
  cursor: pointer;
}

.rail-button:hover {
  background: rgba(255, 255, 255, .025);
  color: #cbd5e5;
}

.rail-button.active {
  border-color: rgba(22, 140, 255, .22);
  background:
    linear-gradient(90deg, rgba(22, 140, 255, .11), rgba(76, 95, 129, .025));
  color: #e5e9f3;
}

.rail-dot {
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: #455168;
}

.rail-button.active .rail-dot {
  background: #168cff;
  box-shadow: 0 0 9px rgba(22, 140, 255, .82);
}

.rail-button em {
  color: #556177;
  font:
    normal 700 8px/1 ui-monospace,
    monospace;
}

.rail-meter {
  padding: 0 8px;
}

.rail-meter span,
.rail-meter strong {
  display: block;
}

.rail-meter span {
  color: #4d596d;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.rail-meter strong {
  margin-top: 5px;
  color: #8896ac;
  font:
    700 8px/1 ui-monospace,
    Consolas,
    monospace;
}

.rail-meter strong.denied {
  color: #ff6f7c;
}

.hub-main {
  min-width: 0;
  overflow: auto;
  padding: 26px 28px 36px;
}

.hub-main::-webkit-scrollbar,
.activity-list::-webkit-scrollbar {
  width: 7px;
}

.hub-main::-webkit-scrollbar-thumb,
.activity-list::-webkit-scrollbar-thumb {
  border-radius: 6px;
  background: #293246;
}

.hub-hero {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 28px;
  padding: 7px 2px 24px;
}

.hub-hero h2 {
  margin: 7px 0 8px;
  color: #dbe7f1;
  font:
    600 30px/1.05 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: -.035em;
}

.hub-hero p {
  max-width: 660px;
  margin: 0;
  color: #718195;
  font: 11px/1.6 Inter, "Segoe UI", sans-serif;
}

.hero-stats {
  display: flex;
  gap: 8px;
}

.hero-stats article {
  min-width: 92px;
  padding: 10px 12px;
  border: 1px solid rgba(112, 129, 160, .13);
  border-radius: 8px;
  background: rgba(12, 18, 26, .78);
}

.hero-stats span,
.hero-stats strong {
  display: block;
}

.hero-stats span {
  color: #455364;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.hero-stats strong {
  margin-top: 7px;
  color: #cbd5df;
  font:
    600 19px/1 Inter,
    sans-serif;
}

.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 18px;
  margin-bottom: 18px;
}

.search-box {
  display: grid;
  grid-template-columns: 20px minmax(0, 1fr) auto;
  align-items: center;
  gap: 8px;
  width: min(560px, 100%);
  height: 39px;
  padding: 0 11px;
  border: 1px solid rgba(112, 129, 160, .18);
  border-radius: 8px;
  background: rgba(9, 14, 20, .82);
}

.search-box > span {
  color: #69778d;
  font-size: 18px;
}

.search-box input {
  min-width: 0;
  border: 0;
  outline: 0;
  background: transparent;
  color: #cbd5df;
  font: 10px/1 Inter, "Segoe UI", sans-serif;
}

.search-box input::placeholder {
  color: #4d5a6f;
}

.search-box kbd {
  padding: 3px 5px;
  border: 1px solid rgba(108, 123, 151, .18);
  border-radius: 4px;
  background: rgba(255, 255, 255, .02);
  color: #5c697e;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.toolbar-copy {
  display: flex;
  gap: 7px;
  color: #455364;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .09em;
}

.separator {
  color: #313b4d;
}

.package-stage {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(390px, 1fr));
  gap: 14px;
}

.package-card {
  position: relative;
  overflow: hidden;
  min-height: 330px;
  padding: 18px;
  border: 1px solid rgba(110, 128, 160, .14);
  border-radius: 11px;
  background:
    linear-gradient(145deg, rgba(17, 25, 35, .88), rgba(8, 13, 19, .95));
  box-shadow:
    0 9px 24px rgba(0, 0, 0, .14),
    inset 0 1px 0 rgba(255, 255, 255, .025);
  transition:
    transform .18s ease,
    border-color .18s ease,
    box-shadow .18s ease;
}

.package-card::before {
  content: "";
  position: absolute;
  inset: 0 auto auto 0;
  width: 100%;
  height: 1px;
  background:
    linear-gradient(90deg, transparent, rgba(22, 140, 255, .58), transparent);
  opacity: .55;
}

.package-card:hover {
  transform: translateY(-2px);
  border-color: rgba(58, 184, 255, .28);
  box-shadow:
    0 16px 34px rgba(0, 0, 0, .22),
    0 0 30px rgba(22, 140, 255, .05);
}

.package-card.active {
  border-color: rgba(68, 212, 177, .28);
}

.package-card.active::before {
  background:
    linear-gradient(90deg, transparent, rgba(76, 226, 184, .65), transparent);
}

.package-card.incompatible {
  border-color: rgba(214, 161, 88, .2);
}

.card-topline {
  display: grid;
  grid-template-columns: 52px minmax(0, 1fr) auto;
  gap: 13px;
  align-items: start;
}

.package-icon {
  position: relative;
  display: grid;
  place-items: center;
  width: 48px;
  height: 48px;
  border: 1px solid rgba(22, 140, 255, .30);
  border-radius: 10px;
  background:
    radial-gradient(circle at 50% 50%, rgba(22, 140, 255, .18), transparent 62%),
    rgba(8, 13, 19, .86);
  color: #cfeeff;
  font:
    700 15px/1 Inter,
    sans-serif;
}

.icon-orbit {
  position: absolute;
  inset: 7px;
  border: 1px solid rgba(73, 194, 213, .18);
  transform: rotate(45deg);
}

.package-state {
  display: flex;
  gap: 8px;
  align-items: center;
  min-height: 13px;
}

.package-state span {
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
  letter-spacing: .06em;
}

.verified {
  color: #55d69e;
}

.verified.bad {
  color: #ff6f7c;
}

.live-state {
  color: #54ddb0;
}

.installed-state {
  color: #8e9bb2;
}

.available-state {
  color: #728096;
}

.package-title h3 {
  margin: 6px 0 4px;
  color: #dbe7f1;
  font:
    600 17px/1.1 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: -.018em;
}

.package-id {
  margin: 0;
  color: #506275;
  font:
    700 8px/1.2 ui-monospace,
    Consolas,
    monospace;
}

.package-id span {
  color: #3ab8ff;
}

.package-channel {
  padding: 4px 6px;
  border: 1px solid rgba(97, 112, 140, .17);
  border-radius: 4px;
  color: #69768b;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.summary {
  min-height: 44px;
  margin: 17px 0 14px;
  color: #8d99ad;
  font: 10px/1.55 Inter, "Segoe UI", sans-serif;
}

.capability-row {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
  min-height: 25px;
}

.capability-row span {
  padding: 4px 6px;
  border: 1px solid rgba(103, 119, 150, .15);
  border-radius: 4px;
  background: rgba(255, 255, 255, .018);
  color: #718195;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.runtime-row {
  display: grid;
  grid-template-columns: .8fr 1.2fr 1fr;
  gap: 8px;
  margin-top: 14px;
  padding: 12px 0;
  border-top: 1px solid rgba(109, 126, 156, .1);
  border-bottom: 1px solid rgba(109, 126, 156, .1);
}

.runtime-row span,
.runtime-row strong {
  display: block;
}

.runtime-row span {
  color: #455364;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.runtime-row strong {
  margin-top: 5px;
  color: #8491a6;
  font:
    700 7px/1.25 ui-monospace,
    Consolas,
    monospace;
}

.trust-row {
  display: grid;
  grid-template-columns: auto 1fr auto;
  gap: 8px;
  align-items: center;
  margin-top: 11px;
  color: #455364;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.trust-row code {
  overflow: hidden;
  color: #6e7b90;
  text-overflow: ellipsis;
}

.trust-copy {
  color: #5d6a80;
}

.package-actions {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-top: 15px;
}

.compatibility {
  display: flex;
  align-items: center;
  gap: 6px;
  color: #68758a;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.compat-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #f1b85b;
}

.compat-dot.online {
  background: #55d69e;
  box-shadow: 0 0 8px rgba(78, 221, 176, .52);
}

.actions {
  display: flex;
  gap: 6px;
}

.actions button {
  height: 29px;
  padding: 0 11px;
  border-radius: 6px;
  font:
    700 8px/1 Inter,
    "Segoe UI",
    sans-serif;
  letter-spacing: .06em;
  cursor: pointer;
}

.actions button:disabled {
  opacity: .38;
  cursor: default;
}

.primary-action {
  border: 1px solid rgba(22, 140, 255, .66);
  background:
    linear-gradient(180deg, rgba(22, 140, 255, .94), rgba(16, 91, 168, .96));
  color: white;
  box-shadow:
    0 5px 14px rgba(22, 140, 255, .22),
    inset 0 1px 0 rgba(255, 255, 255, .16);
}

.secondary-action {
  border: 1px solid rgba(74, 207, 172, .32);
  background: rgba(31, 83, 70, .22);
  color: #55d69e;
}

.ghost-action {
  border: 1px solid rgba(110, 126, 154, .18);
  background: rgba(255, 255, 255, .015);
  color: #718195;
}

.empty-state {
  grid-column: 1 / -1;
  display: grid;
  justify-items: center;
  padding: 90px 20px;
  color: #718195;
  text-align: center;
}

.empty-orbit {
  display: grid;
  place-items: center;
  width: 54px;
  height: 54px;
  margin-bottom: 14px;
  border: 1px solid rgba(22, 140, 255, .30);
  transform: rotate(45deg);
}

.empty-orbit span {
  transform: rotate(-45deg);
  color: #3ab8ff;
}

.empty-state strong {
  color: #a8b3c5;
  font: 12px/1 Inter, sans-serif;
}

.empty-state p {
  color: #506275;
  font: 9px/1.4 Inter, sans-serif;
}

.hub-inspector {
  display: flex;
  flex-direction: column;
  min-width: 0;
  padding: 20px 16px 16px;
  border-left: 1px solid var(--vertex-line);
}

.inspector-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.inspector-head .rail-label {
  margin: 0;
}

.inspector-head strong {
  color: #55d69e;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.trust-stack {
  display: grid;
  gap: 7px;
  margin-top: 14px;
}

.trust-stack article {
  padding: 10px;
  border: 1px solid rgba(107, 124, 153, .1);
  border-radius: 7px;
  background: rgba(255, 255, 255, .015);
}

.trust-stack span,
.trust-stack strong,
.trust-stack em {
  display: block;
}

.trust-stack span {
  color: #455364;
  font: 8px/1 Inter, sans-serif;
}

.trust-stack strong {
  margin-top: 6px;
  color: #a8b4c7;
  font:
    700 9px/1 ui-monospace,
    Consolas,
    monospace;
}

.trust-stack em {
  margin-top: 4px;
  color: #536077;
  font:
    normal 700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.activity-panel {
  min-height: 0;
  margin-top: 18px;
}

.activity-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.activity-head span,
.activity-head small {
  color: #455364;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.activity-list {
  display: grid;
  gap: 5px;
  max-height: 180px;
  margin-top: 9px;
  overflow: auto;
}

.activity-list p,
.activity-list code {
  margin: 0;
  color: #667389;
  font:
    7px/1.45 ui-monospace,
    Consolas,
    monospace;
}

.activity-list code {
  color: #75839a;
}

.error-panel {
  margin-top: 16px;
  padding: 9px;
  border: 1px solid rgba(221, 93, 111, .2);
  border-radius: 7px;
  background: rgba(97, 28, 39, .13);
}

.error-panel span {
  color: #ff6f7c;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.error-panel pre {
  max-height: 100px;
  margin: 7px 0 0;
  overflow: auto;
  color: #c78790;
  white-space: pre-wrap;
  font:
    7px/1.45 ui-monospace,
    Consolas,
    monospace;
}

.inspector-footer {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-top: auto;
  padding-top: 14px;
  border-top: 1px solid rgba(105, 122, 151, .1);
}

.signal {
  width: 8px;
  height: 8px;
  border: 1px solid rgba(81, 218, 179, .55);
  border-radius: 50%;
  box-shadow:
    0 0 0 3px rgba(81, 218, 179, .05),
    0 0 12px rgba(81, 218, 179, .2);
}

.inspector-footer strong,
.inspector-footer small {
  display: block;
}

.inspector-footer strong {
  color: #718195;
  font:
    700 7px/1 ui-monospace,
    Consolas,
    monospace;
}

.inspector-footer small {
  margin-top: 4px;
  color: #455364;
  font:
    700 6px/1 ui-monospace,
    Consolas,
    monospace;
}

.hub-fade-enter-active,
.hub-fade-leave-active {
  transition:
    opacity .16s ease,
    transform .16s ease;
}

.hub-fade-enter-from,
.hub-fade-leave-to {
  opacity: 0;
}

.hub-fade-enter-from .hub-shell,
.hub-fade-leave-to .hub-shell {
  transform: translateY(8px) scale(.992);
}

@media (max-width: 1120px) {
  .hub-body {
    grid-template-columns: 150px minmax(0, 1fr);
  }

  .hub-inspector {
    display: none;
  }

  .hero-stats {
    display: none;
  }
}

@media (max-width: 760px) {
  .hub-backdrop {
    padding: 8px;
  }

  .hub-shell {
    width: calc(100vw - 16px);
    height: calc(100vh - 16px);
  }

  .hub-body {
    grid-template-columns: 1fr;
  }

  .hub-rail {
    display: none;
  }

  .hub-command {
    padding: 0 14px;
  }

  .status-block {
    display: none;
  }

  .hub-main {
    padding: 18px 14px 28px;
  }

  .package-stage {
    grid-template-columns: 1fr;
  }

  .toolbar-copy {
    display: none;
  }
}
</style>