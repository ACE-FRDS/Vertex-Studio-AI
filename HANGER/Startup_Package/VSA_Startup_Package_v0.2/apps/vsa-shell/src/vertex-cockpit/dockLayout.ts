import { computed, ref, watch } from 'vue'

export type DockZone = 'left' | 'right' | 'bottom' | 'float'
export type DockEntityKind = 'panel' | 'agent' | 'drone'

export interface DockPanelState {
  id: string
  zone: DockZone
  order: number
  visible: boolean
  x: number
  y: number
  width: number
  height: number
}

export interface DockHostCapability {
  kind: DockEntityKind
  dock: true
  float: true
  resize: true
  persist: true
}

export interface DockLayoutSnapshot {
  schema: 'vertex.cockpit.role-layout.v5'
  panels: DockPanelState[]
  leftWidth: number
  rightWidth: number
  bottomHeight: number
}

const STORAGE_KEY = 'vertex.cockpit.role-layout.v5'

const defaults: DockLayoutSnapshot = {
  schema: 'vertex.cockpit.role-layout.v5',
  panels: [
    // HUMAN INTENT GATEWAY
    {
      id: 'hyperagent-chat',
      zone: 'left',
      order: 0,
      visible: true,
      x: 30,
      y: 120,
      width: 430,
      height: 720,
    },

    // WORLD / PROJECT STRUCTURE
    {
      id: 'vve-tree-explorer',
      zone: 'right',
      order: 0,
      visible: true,
      x: 1080,
      y: 120,
      width: 430,
      height: 720,
    },

    // INDEPENDENT UTILITY COMPONENTS
    {
      id: 'ai-activity-monitor',
      zone: 'bottom',
      order: 0,
      visible: true,
      x: 100,
      y: 600,
      width: 380,
      height: 280,
    },
    {
      id: 'terminal',
      zone: 'bottom',
      order: 1,
      visible: true,
      x: 180,
      y: 620,
      width: 620,
      height: 300,
    },
    {
      id: 'build',
      zone: 'bottom',
      order: 2,
      visible: true,
      x: 300,
      y: 620,
      width: 360,
      height: 260,
    },
    {
      id: 'test',
      zone: 'bottom',
      order: 3,
      visible: true,
      x: 340,
      y: 620,
      width: 360,
      height: 260,
    },
    {
      id: 'reviewer',
      zone: 'bottom',
      order: 4,
      visible: true,
      x: 400,
      y: 620,
      width: 420,
      height: 300,
    },
    {
      id: 'ai-assistant',
      zone: 'bottom',
      order: 5,
      visible: true,
      x: 460,
      y: 620,
      width: 390,
      height: 300,
    },

    // OPTIONAL EQUIPMENT - AVAILABLE BUT NOT DEFAULT MAIN
    {
      id: 'system-monitor',
      zone: 'right',
      order: 10,
      visible: false,
      x: 980,
      y: 160,
      width: 420,
      height: 310,
    },
    {
      id: 'vsp-snapshot',
      zone: 'right',
      order: 11,
      visible: false,
      x: 940,
      y: 210,
      width: 420,
      height: 330,
    },
  ],
  leftWidth: 390,
  rightWidth: 390,
  bottomHeight: 300,
}

export const dockHostCapabilities: DockHostCapability[] = [
  { kind: 'panel', dock: true, float: true, resize: true, persist: true },
  { kind: 'agent', dock: true, float: true, resize: true, persist: true },
  { kind: 'drone', dock: true, float: true, resize: true, persist: true },
]

function cloneDefaults(): DockLayoutSnapshot {
  return JSON.parse(JSON.stringify(defaults)) as DockLayoutSnapshot
}

function clamp(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback
  return Math.min(maximum, Math.max(minimum, value))
}

function sanitizePanel(
  rawValue: unknown,
  fallback: DockPanelState,
): DockPanelState {
  const raw =
    typeof rawValue === 'object' && rawValue !== null
      ? (rawValue as Partial<DockPanelState>)
      : {}

  const allowed: DockZone[] = ['left', 'right', 'bottom', 'float']
  const zone =
    typeof raw.zone === 'string' && allowed.includes(raw.zone as DockZone)
      ? (raw.zone as DockZone)
      : fallback.zone

  return {
    id: fallback.id,
    zone,
    order: clamp(raw.order, fallback.order, 0, 2000),
    visible: typeof raw.visible === 'boolean' ? raw.visible : fallback.visible,
    x: clamp(raw.x, fallback.x, 0, 10000),
    y: clamp(raw.y, fallback.y, 0, 10000),
    width: clamp(raw.width, fallback.width, 300, 1400),
    height: clamp(raw.height, fallback.height, 180, 1200),
  }
}

function loadSnapshot(): DockLayoutSnapshot {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return cloneDefaults()

    const parsed = JSON.parse(raw) as Partial<DockLayoutSnapshot>
    if (parsed.schema !== 'vertex.cockpit.role-layout.v5') {
      return cloneDefaults()
    }

    const sourcePanels = Array.isArray(parsed.panels) ? parsed.panels : []

    return {
      schema: 'vertex.cockpit.role-layout.v5',
      panels: defaults.panels.map((fallback) => {
        const found = sourcePanels.find(
          (item) =>
            typeof item === 'object'
            && item !== null
            && (item as Partial<DockPanelState>).id === fallback.id,
        )
        return sanitizePanel(found, fallback)
      }),
      leftWidth: clamp(parsed.leftWidth, defaults.leftWidth, 320, 720),
      rightWidth: clamp(parsed.rightWidth, defaults.rightWidth, 320, 720),
      bottomHeight: clamp(parsed.bottomHeight, defaults.bottomHeight, 220, 620),
    }
  } catch {
    return cloneDefaults()
  }
}

export function useDockLayout() {
  const snapshot = ref<DockLayoutSnapshot>(loadSnapshot())

  const visiblePanels = computed(() =>
    snapshot.value.panels.filter((panel) => panel.visible),
  )

  function panelsIn(zone: DockZone) {
    return computed(() =>
      visiblePanels.value
        .filter((panel) => panel.zone === zone)
        .sort((a, b) => a.order - b.order),
    )
  }

  function movePanel(
    id: string,
    zone: DockZone,
    position?: { x: number; y: number },
  ) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (!target) return

    target.zone = zone
    target.visible = true

    const maxOrder = Math.max(
      -1,
      ...snapshot.value.panels
        .filter((panel) => panel.zone === zone && panel.id !== id)
        .map((panel) => panel.order),
    )
    target.order = maxOrder + 1

    if (zone === 'float' && position) {
      target.x = Math.max(8, position.x)
      target.y = Math.max(8, position.y)
    }
  }

  function hidePanel(id: string) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (target) target.visible = false
  }

  function showPanel(id: string) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (target) target.visible = true
  }

  function updateFloatRect(
    id: string,
    rect: Partial<Pick<DockPanelState, 'x' | 'y' | 'width' | 'height'>>,
  ) {
    const target = snapshot.value.panels.find((panel) => panel.id === id)
    if (!target) return

    if (typeof rect.x === 'number') target.x = Math.max(0, rect.x)
    if (typeof rect.y === 'number') target.y = Math.max(0, rect.y)
    if (typeof rect.width === 'number') {
      target.width = Math.max(300, Math.min(1400, rect.width))
    }
    if (typeof rect.height === 'number') {
      target.height = Math.max(180, Math.min(1200, rect.height))
    }
  }

  function setLeftWidth(value: number) {
    snapshot.value.leftWidth = Math.max(320, Math.min(720, value))
  }

  function setRightWidth(value: number) {
    snapshot.value.rightWidth = Math.max(320, Math.min(720, value))
  }

  function setBottomHeight(value: number) {
    snapshot.value.bottomHeight = Math.max(220, Math.min(620, value))
  }

  function resetLayout() {
    snapshot.value = cloneDefaults()
  }

  watch(
    snapshot,
    (value) => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
    },
    { deep: true },
  )

  return {
    snapshot,
    visiblePanels,
    leftPanels: panelsIn('left'),
    rightPanels: panelsIn('right'),
    bottomPanels: panelsIn('bottom'),
    floatingPanels: panelsIn('float'),
    movePanel,
    hidePanel,
    showPanel,
    updateFloatRect,
    setLeftWidth,
    setRightWidth,
    setBottomHeight,
    resetLayout,
  }
}