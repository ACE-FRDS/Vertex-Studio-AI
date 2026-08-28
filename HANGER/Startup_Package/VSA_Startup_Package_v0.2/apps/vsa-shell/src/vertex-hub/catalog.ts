import { markRaw, type Component } from 'vue'
import LiveFlightPanel from './packages/vertex.live-flight-panel/1.0.0/src/VertexLiveFlightPanel.vue'

export interface VertexHubUiPackage {
  packageId: string
  version: string
  displayName: string
  summary: string
  kind: 'ui.component'
  publisher: string
  channel: 'stable' | 'preview'
  manifestSha256: string
  component: Component
  capabilities: string[]
  runtime: string[]
  executionMode: 'bundled'
}

export const vertexHubUiPackages: VertexHubUiPackage[] = [
  {
    packageId: 'vertex.live-flight-panel',
    version: '1.0.0',
    displayName: 'Live Flight Panel',
    summary: 'Real-time Mothership session, wave, dispatch, Genesis and VSP telemetry.',
    kind: 'ui.component',
    publisher: 'Vertex',
    channel: 'stable',
    manifestSha256: '813bf218cc8e3d0c7a8f247650ee79dac60354be4bea4ca0860ca5f0c1e7cad1',
    component: markRaw(LiveFlightPanel),
    capabilities: ['TELEMETRY', 'READ_ONLY', 'VSP'],
    runtime: ['VUE 3', 'TAURI 2'],
    executionMode: 'bundled',
  },
]