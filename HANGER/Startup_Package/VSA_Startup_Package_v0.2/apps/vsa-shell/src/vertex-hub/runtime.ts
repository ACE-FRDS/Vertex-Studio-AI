import { invoke } from '@tauri-apps/api/core'

export interface HubRegistryEntry {
  package_id: string
  version: string
  kind: string
  status: string
  manifest: string
  manifest_sha256: string
}

export interface HubRegistry {
  schema: string
  generated_at?: string
  packages: HubRegistryEntry[]
}

export interface HubRuntimePackage {
  package_id: string
  version: string
  enabled: boolean
  installed_at_ms: number
}

export interface HubRuntimeState {
  schema: string
  packages: HubRuntimePackage[]
}

export interface HubRuntimeMutation {
  package_id: string
  version: string
  installed: boolean
  enabled: boolean
}

export async function validatedHubRegistry(): Promise<HubRegistry> {
  const raw = await invoke<string>('vertex_hub_registry')
  return JSON.parse(raw) as HubRegistry
}

export async function hubRuntimeState(): Promise<HubRuntimeState> {
  const raw = await invoke<string>('vertex_hub_runtime_state')
  return JSON.parse(raw) as HubRuntimeState
}

export async function installHubPackage(
  packageId: string,
  version: string,
): Promise<HubRuntimeMutation> {
  const raw = await invoke<string>('vertex_hub_install', {
    packageId,
    version,
  })

  return JSON.parse(raw) as HubRuntimeMutation
}

export async function setHubPackageEnabled(
  packageId: string,
  version: string,
  enabled: boolean,
): Promise<HubRuntimeMutation> {
  const raw = await invoke<string>('vertex_hub_set_enabled', {
    packageId,
    version,
    enabled,
  })

  return JSON.parse(raw) as HubRuntimeMutation
}

export async function uninstallHubPackage(
  packageId: string,
  version: string,
): Promise<HubRuntimeMutation> {
  const raw = await invoke<string>('vertex_hub_uninstall', {
    packageId,
    version,
  })

  return JSON.parse(raw) as HubRuntimeMutation
}