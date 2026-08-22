<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useNavigationStore, type WorkspaceMode } from '../../stores/navigation'
import { useLocaleStore } from '../../stores/locale'
import { isTauriRuntime, nativeGateway, type FileMakerStatus, type UpdateCheck } from '../../services/nativeGateway'
import { featureAccess, type FeatureId } from '../../services/featureAccess'
import KnowledgeBrainIcon from '../icons/KnowledgeBrainIcon.vue'

// Keep Codex next to the development utilities: Collections → Codex → Tools.
const navigation = [
  { id: 'clipboard', label: 'navClipboard', icon: 'assignment' },
  { id: 'library', label: 'navLibrary', icon: 'library_books' },
  { id: 'collections', label: 'navCollections', icon: 'account_tree' },
  { id: 'codex', label: 'navCodex', icon: 'smart_toy' },
  { id: 'knowledge', label: 'navKnowledge', icon: 'psychology', feature: 'knowledgePackEngine', pro: true },
  { id: 'relationship', label: 'navRelationshipDesigner', icon: 'hub', feature: 'relationshipDesigner', pro: true },
  { id: 'tools', label: 'navTools', icon: 'construction' },
  { id: 'settings', label: 'navSettings', icon: 'settings' },
  { id: 'docs', label: 'navDocs', icon: 'menu_book' },
] as const
const visibleNavigation = computed(() => navigation.filter((item) =>
  ('pro' in item && item.pro) || !('feature' in item) || featureAccess.can(item.feature as FeatureId),
))
const navigationStore = useNavigationStore()
const locale = useLocaleStore()
const appVersion = ref('0.1.0')
const distributionRepository = 'ACE-FRDS/vrtex_fm_engine'
const distributionRepositoryUrl = `https://github.com/${distributionRepository}`
const updatePanelOpen = ref(false)
const updateChecking = ref(false)
const updateCheck = ref<UpdateCheck | null>(null)
const updateCheckError = ref('')
const lastSeenUpdateVersion = ref(localStorage.getItem('vertex.lastSeenUpdateVersion') ?? '')
const updateUnread = computed(() => lastSeenUpdateVersion.value !== appVersion.value)
const runtimeChannel = computed(() =>
  isTauriRuntime() ? locale.t('desktopDevelopmentChannel') : locale.t('browserPreviewChannel'),
)
const fileMaker = ref<FileMakerStatus>({
  detected: !isTauriRuntime(),
  version: !isTauriRuntime() ? '26' : null,
  displayName: !isTauriRuntime() ? 'FileMaker Pro' : 'FileMaker',
})
const fileMakerLabel = computed(() =>
  `${fileMaker.value.displayName}${fileMaker.value.version ? ` ${fileMaker.value.version}` : ''}`,
)
let detectionTimer: number | undefined

async function refreshFileMakerStatus() {
  if (!isTauriRuntime()) return
  try {
    fileMaker.value = await nativeGateway.detectFileMaker()
  } catch {
    fileMaker.value = { detected: false, version: null, displayName: 'FileMaker' }
  }
}

async function loadAppVersion() {
  if (!isTauriRuntime()) return
  try {
    const { getVersion } = await import('@tauri-apps/api/app')
    appVersion.value = await getVersion()
  } catch {
    appVersion.value = '0.1.0'
  }
}

function markUpdateInformationRead() {
  lastSeenUpdateVersion.value = appVersion.value
  localStorage.setItem('vertex.lastSeenUpdateVersion', appVersion.value)
}

function toggleUpdatePanel() {
  updatePanelOpen.value = !updatePanelOpen.value
  if (updatePanelOpen.value) {
    markUpdateInformationRead()
    if (!updateCheck.value && !updateCheckError.value) void checkUpdates()
  }
}

async function checkUpdates() {
  if (updateChecking.value) return
  updateChecking.value = true
  updateCheckError.value = ''
  try {
    updateCheck.value = isTauriRuntime()
      ? await nativeGateway.checkForUpdates(appVersion.value)
      : {
          currentVersion: appVersion.value,
          latestVersion: appVersion.value,
          updateAvailable: false,
          releaseUrl: distributionRepositoryUrl,
          publishedAt: null,
          notes: '',
        }
  } catch (error) {
    updateCheckError.value = error instanceof Error ? error.message : String(error)
  } finally {
    updateChecking.value = false
  }
}

function closeUpdatePanel() {
  updatePanelOpen.value = false
}

onMounted(() => {
  void loadAppVersion()
  void refreshFileMakerStatus()
  detectionTimer = window.setInterval(refreshFileMakerStatus, 5_000)
  document.addEventListener('click', closeUpdatePanel)
})
onBeforeUnmount(() => {
  window.clearInterval(detectionTimer)
  document.removeEventListener('click', closeUpdatePanel)
})
</script>

<template>
  <header class="vertex-header">
    <div class="brand-block">
      <svg class="vertex-mark" viewBox="0 0 54 46" aria-label="Vertex logo" role="img">
        <defs>
          <linearGradient id="vertex-left" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="#43bdf5" />
            <stop offset="1" stop-color="#1977ca" />
          </linearGradient>
          <linearGradient id="vertex-right" x1="0" y1="0" x2="0.9" y2="1">
            <stop offset="0" stop-color="#536bd7" />
            <stop offset="1" stop-color="#2946a6" />
          </linearGradient>
        </defs>
        <path fill="url(#vertex-left)" d="M2 2h16l11.5 18.2L20 40.5z" />
        <path fill="url(#vertex-right)" d="M28 2h18L20 44 11.5 29.5z" />
      </svg>
      <div>
        <div class="brand-name">VERTEX <strong>FM</strong> ENGINE</div>
        <div class="brand-subtitle">{{ locale.t('brandSubtitle') }}</div>
      </div>
    </div>

    <nav class="top-navigation" aria-label="Primary navigation">
      <button
        v-for="item in visibleNavigation"
        :key="item.id"
        class="nav-item"
        :class="{ active: navigationStore.active === item.id }"
        type="button"
        :aria-pressed="navigationStore.active === item.id"
        @click="navigationStore.setActive(item.id as WorkspaceMode)"
      >
        <KnowledgeBrainIcon v-if="item.id === 'knowledge'" class="nav-svg-icon" />
        <span v-else class="material-icons">{{ item.icon }}</span>
        <span class="nav-label">{{ locale.t(item.label) }}</span>
        <span v-if="'pro' in item && item.pro" class="nav-pro-badge">PRO</span>
      </button>
    </nav>

    <div class="connection-block">
      <div class="connection-copy">
        <span class="connection-name">{{ fileMakerLabel }}</span>
        <span class="connection-state" :class="{ disconnected: !fileMaker.detected }"><i /> {{ fileMaker.detected ? locale.t('detectedLocally') : locale.t('fileMakerNotDetected') }}</span>
      </div>
      <div class="header-divider" />
      <div class="system-notification-wrap" @click.stop>
        <q-btn
          class="system-notification-button"
          flat
          dense
          round
          icon="notifications_none"
          :aria-label="locale.t('notifications')"
          :aria-expanded="updatePanelOpen"
          @click="toggleUpdatePanel"
        >
          <q-badge v-if="updateUnread" floating color="primary" rounded />
        </q-btn>
        <section
          v-if="updatePanelOpen"
          class="system-update-menu"
          role="dialog"
          :aria-label="locale.t('systemUpdateTitle')"
        >
          <div class="system-update-panel">
            <header class="system-update-heading">
              <span class="system-update-icon material-icons">system_update</span>
              <div>
                <span>{{ locale.t('systemInformation') }}</span>
                <h3>{{ locale.t('systemUpdateTitle') }}</h3>
              </div>
              <span class="system-version-badge">v{{ appVersion }}</span>
            </header>

            <div class="system-version-grid">
              <div>
                <span>{{ locale.t('currentVersion') }}</span>
                <strong>Vertex FM Engine {{ appVersion }}</strong>
              </div>
              <div>
                <span>{{ locale.t('releaseChannel') }}</span>
                <strong>{{ runtimeChannel }}</strong>
              </div>
            </div>

            <div class="update-status-card" :class="{ available: updateCheck?.updateAvailable, error: updateCheckError }">
              <span class="material-icons">{{ updateChecking ? 'sync' : updateCheckError ? 'cloud_off' : updateCheck?.updateAvailable ? 'system_update_alt' : 'verified' }}</span>
              <div>
                <strong v-if="updateChecking">{{ locale.language === 'ja' ? '更新情報を確認しています…' : 'Checking for updates…' }}</strong>
                <strong v-else-if="updateCheckError">{{ locale.language === 'ja' ? '更新確認に失敗しました' : 'Update check failed' }}</strong>
                <strong v-else-if="updateCheck?.updateAvailable">{{ locale.language === 'ja' ? `新しいバージョン ${updateCheck.latestVersion} があります` : `Version ${updateCheck.latestVersion} is available` }}</strong>
                <strong v-else>{{ locale.language === 'ja' ? '最新バージョンです' : 'You are up to date' }}</strong>
                <p>{{ updateCheckError || (updateCheck?.updateAvailable ? (locale.language === 'ja' ? 'GitHub Releaseからインストーラーを取得できます。' : 'Download the installer from GitHub Releases.') : (locale.language === 'ja' ? 'GitHub Releasesの最新情報を確認しました。' : 'Checked the latest GitHub Release.')) }}</p>
              </div>
              <button type="button" :disabled="updateChecking" :aria-label="locale.language === 'ja' ? '更新を再確認' : 'Check again'" @click="checkUpdates"><span class="material-icons">refresh</span></button>
            </div>

            <a v-if="updateCheck?.updateAvailable" class="update-download-link" :href="updateCheck.releaseUrl" target="_blank" rel="noopener noreferrer"><span class="material-icons">download</span>{{ locale.language === 'ja' ? 'GitHub Releaseを開く' : 'Open GitHub Release' }}</a>

            <a
              class="distribution-repository"
              :href="distributionRepositoryUrl"
              target="_blank"
              rel="noopener noreferrer"
            >
              <span class="material-icons">inventory_2</span>
              <span>
                <small>{{ locale.t('distributionRepository') }}</small>
                <strong>{{ distributionRepository }}</strong>
              </span>
              <span class="distribution-planned">Private</span>
            </a>

            <div class="recent-update-list">
              <h4>{{ locale.t('recentUpdates') }}</h4>
              <div><span class="material-icons">check_circle</span>{{ locale.t('updateItemClipboard') }}</div>
              <div><span class="material-icons">check_circle</span>{{ locale.t('updateItemMultipleScripts') }}</div>
              <div><span class="material-icons">check_circle</span>{{ locale.t('updateItemUi') }}</div>
            </div>

            <footer class="system-update-footer">
              <span class="material-icons">shield</span>
              {{ locale.t('updateSecurityNotice') }}
            </footer>
          </div>
        </section>
      </div>
      <q-btn flat dense round icon="account_circle" :aria-label="locale.t('account')" />
    </div>
  </header>
</template>
