export type EquipmentRuntimeMode =
  | 'static'
  | 'dockable'
  | 'agent'
  | 'drone'

export type EquipmentKind =
  | 'primary'
  | 'human-interface'
  | 'explorer'
  | 'monitor'
  | 'execution'
  | 'build'
  | 'test'
  | 'review'
  | 'assistant'
  | 'source-control'
  | 'memory'
  | 'system'

export type EquipmentPermission =
  | 'read-workspace'
  | 'write-workspace'
  | 'run-controlled-action'
  | 'mission-submit'
  | 'mission-observe'
  | 'runtime-read'

export interface EquipmentPort {
  id: string
  label: string
  direction: 'in' | 'out' | 'bidirectional'
  signal: string
}

export interface EquipmentLayout {
  col: number
  row: number
  colSpan: number
  rowSpan: number
  minColSpan: number
  minRowSpan: number
}

export interface EquipmentUnitDescriptor {
  id: string
  title: string
  subtitle: string
  kind: EquipmentKind
  runtimeMode: EquipmentRuntimeMode

  primary: boolean
  movable: boolean
  resizable: boolean
  floatable: boolean

  droneEligible: boolean
  droneRuntimeImplemented: boolean

  capabilities: string[]
  ports: EquipmentPort[]
  permissions: EquipmentPermission[]

  layout: EquipmentLayout
}

export const equipmentRegistry: EquipmentUnitDescriptor[] = [
  {
    id: 'hyperagent-chat',
    title: 'HYPERAgent チャット',
    subtitle: 'ヒューマン意図入力',
    kind: 'human-interface',
    runtimeMode: 'agent',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: false,
    droneRuntimeImplemented: false,
    capabilities: ['intent','mission-submit','mission-observe'],
    ports: [
      {
        id: 'intent-out',
        label: 'Human Intent',
        direction: 'out',
        signal: 'vertex.intent',
      },
      {
        id: 'mission-state-in',
        label: 'Mission State',
        direction: 'in',
        signal: 'vertex.mission.state',
      },
    ],
    permissions: ['mission-submit','mission-observe','runtime-read'],
    layout: {
      col: 1,row: 1,colSpan: 5,rowSpan: 10,minColSpan: 4,minRowSpan: 5,
    },
  },
  {
    id: 'vsa-editor',
    title: 'VSA エディター',
    subtitle: 'Primary Development Surface',
    kind: 'primary',
    runtimeMode: 'static',
    primary: true,
    movable: true,
    resizable: true,
    floatable: false,
    droneEligible: false,
    droneRuntimeImplemented: false,
    capabilities: ['read','write','diagnostics'],
    ports: [
      {
        id: 'file-open-in',
        label: 'File Open',
        direction: 'in',
        signal: 'vertex.file.open',
      },
      {
        id: 'active-file-out',
        label: 'Active File',
        direction: 'out',
        signal: 'vertex.file.active',
      },
    ],
    permissions: ['read-workspace','write-workspace','runtime-read'],
    layout: {
      col: 6,row: 1,colSpan: 13,rowSpan: 10,minColSpan: 8,minRowSpan: 5,
    },
  },
  {
    id: 'vve-explorer',
    title: 'VVE エクスプローラー',
    subtitle: 'Project World',
    kind: 'explorer',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['tree','search','file-open'],
    ports: [
      {
        id: 'file-open-out',
        label: 'File Open',
        direction: 'out',
        signal: 'vertex.file.open',
      },
      {
        id: 'structure-out',
        label: 'Project Structure',
        direction: 'out',
        signal: 'vertex.structure',
      },
    ],
    permissions: ['read-workspace','runtime-read'],
    layout: {
      col: 19,row: 1,colSpan: 6,rowSpan: 10,minColSpan: 4,minRowSpan: 5,
    },
  },
  {
    id: 'ai-activity',
    title: 'AI 活動モニター',
    subtitle: 'Agent Activity',
    kind: 'monitor',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['observe'],
    ports: [
      {
        id: 'activity-in',
        label: 'Activity',
        direction: 'in',
        signal: 'vertex.agent.activity',
      },
    ],
    permissions: ['mission-observe','runtime-read'],
    layout: {
      col: 1,row: 11,colSpan: 5,rowSpan: 6,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'terminal',
    title: 'ターミナル',
    subtitle: 'Controlled Execution',
    kind: 'execution',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['controlled-exec','evidence'],
    ports: [
      {
        id: 'command-in',
        label: 'Controlled Command',
        direction: 'in',
        signal: 'vertex.command.controlled',
      },
      {
        id: 'evidence-out',
        label: 'Execution Evidence',
        direction: 'out',
        signal: 'vertex.execution.evidence',
      },
    ],
    permissions: ['run-controlled-action','runtime-read'],
    layout: {
      col: 6,row: 11,colSpan: 7,rowSpan: 6,minColSpan: 5,minRowSpan: 3,
    },
  },
  {
    id: 'build',
    title: 'ビルド',
    subtitle: 'Cargo Build',
    kind: 'build',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['cargo-build','cargo-release'],
    ports: [
      {
        id: 'build-in',
        label: 'Build Request',
        direction: 'in',
        signal: 'vertex.build.request',
      },
      {
        id: 'build-out',
        label: 'Build Result',
        direction: 'out',
        signal: 'vertex.build.result',
      },
    ],
    permissions: ['run-controlled-action'],
    layout: {
      col: 13,row: 11,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'test',
    title: 'テスト',
    subtitle: 'Cargo Test',
    kind: 'test',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['cargo-test'],
    ports: [
      {
        id: 'test-in',
        label: 'Test Request',
        direction: 'in',
        signal: 'vertex.test.request',
      },
      {
        id: 'test-out',
        label: 'Test Result',
        direction: 'out',
        signal: 'vertex.test.result',
      },
    ],
    permissions: ['run-controlled-action'],
    layout: {
      col: 17,row: 11,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'reviewer',
    title: 'レビュアー',
    subtitle: 'Diagnostics / Clippy / Diff',
    kind: 'review',
    runtimeMode: 'agent',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['diagnostics','clippy','diff'],
    ports: [
      {
        id: 'review-in',
        label: 'Review Input',
        direction: 'in',
        signal: 'vertex.review.input',
      },
      {
        id: 'review-out',
        label: 'Review Result',
        direction: 'out',
        signal: 'vertex.review.result',
      },
    ],
    permissions: ['read-workspace','run-controlled-action','mission-observe'],
    layout: {
      col: 21,row: 11,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'ai-assistant',
    title: 'AI アシスタント',
    subtitle: 'Activity-derived Suggestions',
    kind: 'assistant',
    runtimeMode: 'agent',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['suggest'],
    ports: [
      {
        id: 'suggestion-out',
        label: 'Suggestion',
        direction: 'out',
        signal: 'vertex.suggestion',
      },
    ],
    permissions: ['mission-observe','runtime-read'],
    layout: {
      col: 13,row: 14,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'git',
    title: 'Git',
    subtitle: 'Status / Diff',
    kind: 'source-control',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['status','diff'],
    ports: [
      {
        id: 'git-state-out',
        label: 'Git State',
        direction: 'out',
        signal: 'vertex.git.state',
      },
    ],
    permissions: ['read-workspace','run-controlled-action'],
    layout: {
      col: 17,row: 14,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'system-monitor',
    title: 'システム監視',
    subtitle: 'Runtime Telemetry',
    kind: 'system',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: true,
    droneRuntimeImplemented: false,
    capabilities: ['telemetry'],
    ports: [
      {
        id: 'telemetry-in',
        label: 'Telemetry',
        direction: 'in',
        signal: 'vertex.telemetry',
      },
    ],
    permissions: ['runtime-read'],
    layout: {
      col: 21,row: 14,colSpan: 4,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
  {
    id: 'vsp-status',
    title: 'VSP 状態',
    subtitle: 'Save Point / Lineage',
    kind: 'memory',
    runtimeMode: 'dockable',
    primary: false,
    movable: true,
    resizable: true,
    floatable: true,
    droneEligible: false,
    droneRuntimeImplemented: false,
    capabilities: ['savepoint-observe'],
    ports: [
      {
        id: 'vsp-in',
        label: 'VSP State',
        direction: 'in',
        signal: 'vertex.vsp.state',
      },
    ],
    permissions: ['runtime-read'],
    layout: {
      col: 1,row: 14,colSpan: 5,rowSpan: 3,minColSpan: 4,minRowSpan: 3,
    },
  },
]

export const equipmentById = Object.fromEntries(
  equipmentRegistry.map((item) => [item.id, item]),
) as Record<string, EquipmentUnitDescriptor>