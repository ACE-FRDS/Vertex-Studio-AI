export type CockpitPanelMobility = 'fixed' | 'dockable'
export type CockpitHostKind = 'panel' | 'agent' | 'drone'

export interface CockpitPanelDescriptor {
  id: string
  title: string
  region: 'TOP' | 'LEFT' | 'RIGHT' | 'BOTTOM' | 'FLOAT'
  packageReady: boolean
  source: string
  mobility: CockpitPanelMobility
  supportedHostKinds: CockpitHostKind[]
}

export const cockpitPanelRegistry: CockpitPanelDescriptor[] = [
  {
    id: 'vertex.project-status-panel',
    title: 'PROJECT',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ProjectStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'vertex.vsp-status-panel',
    title: 'VSP',
    region: 'TOP',
    packageReady: true,
    source: 'panels/VspStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'vertex.vxn-status-panel',
    title: 'VXN',
    region: 'TOP',
    packageReady: true,
    source: 'panels/VxnStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'vertex.ard-status-panel',
    title: 'ARD',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ArdStatusPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel', 'agent'],
  },
  {
    id: 'vertex.project-brain-panel',
    title: 'PROJECT BRAIN',
    region: 'TOP',
    packageReady: true,
    source: 'panels/ProjectBrainPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel', 'agent'],
  },
  {
    id: 'vertex.workspace-health-panel',
    title: 'WORKSPACE HEALTH',
    region: 'TOP',
    packageReady: true,
    source: 'panels/WorkspaceHealthPanel.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
  {
    id: 'system-monitor',
    title: 'SYSTEM MONITOR',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/SystemMonitorPanel.vue',
    mobility: 'dockable',
    supportedHostKinds: ['panel', 'agent', 'drone'],
  },
  {
    id: 'hyper-agent',
    title: 'HYPER AGENT',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/HyperAgentPanel.vue',
    mobility: 'dockable',
    supportedHostKinds: ['panel', 'agent', 'drone'],
  },
  {
    id: 'vsp-snapshot',
    title: 'VSP SNAPSHOT',
    region: 'RIGHT',
    packageReady: true,
    source: 'panels/VspSnapshotPanel.vue',
    mobility: 'dockable',
    supportedHostKinds: ['panel', 'agent', 'drone'],
  },
  {
    id: 'vertex.cockpit-status-bar',
    title: 'COCKPIT STATUS BAR',
    region: 'BOTTOM',
    packageReady: true,
    source: 'panels/CockpitStatusBar.vue',
    mobility: 'fixed',
    supportedHostKinds: ['panel'],
  },
]