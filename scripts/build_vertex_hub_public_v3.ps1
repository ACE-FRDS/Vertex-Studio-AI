#requires -Version 7.0
$ErrorActionPreference = "Stop"

# Compatibility entry point. The v4 builder preserves all v3 routes while
# adding the canonical Research and Public Knowledge layers.
& (Join-Path $PSScriptRoot "build_vertex_hub_public_v4.ps1") @args
