import { markRaw, type Component } from 'vue'
import { vertexHubUiPackages } from '../vertex-hub/catalog'
import VertexSystemPreview from './VertexSystemPreview.vue'

export interface VertexPreviewTarget {
  id: string
  label: string
  group: 'SYSTEM' | 'VERTEXHUB'
  description: string
  component: Component
  source: string
}

const hubTargets: VertexPreviewTarget[] = vertexHubUiPackages.map((pkg) => ({
  id: `hub:${pkg.packageId}@${pkg.version}`,
  label: pkg.displayName,
  group: 'VERTEXHUB',
  description: pkg.summary,
  component: markRaw(pkg.component),
  source: `${pkg.packageId}@${pkg.version}`,
}))

export const vertexPreviewTargets: VertexPreviewTarget[] = [
  {
    id: 'system:vertex-surface',
    label: 'Vertex System Surface',
    group: 'SYSTEM',
    description: 'FME-derived Vertex visual language and live-development reference surface.',
    component: markRaw(VertexSystemPreview),
    source: 'src/vertex-preview/VertexSystemPreview.vue',
  },
  ...hubTargets,
]