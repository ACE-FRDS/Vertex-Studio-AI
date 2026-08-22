param([string]$Token='vertex-demo-owner-token')

$headers=@{'X-Vertex-Owner-Token'=$Token}

Write-Host "=== HEALTH ===" -ForegroundColor Cyan
Invoke-RestMethod 'http://127.0.0.1:8765/health'

Write-Host "`n=== CAPABILITIES ===" -ForegroundColor Cyan
Invoke-RestMethod 'http://127.0.0.1:8765/capabilities' -Headers $headers

Write-Host "`n=== VUR STATUS ===" -ForegroundColor Cyan
Invoke-RestMethod 'http://127.0.0.1:8765/vur/status' -Headers $headers
