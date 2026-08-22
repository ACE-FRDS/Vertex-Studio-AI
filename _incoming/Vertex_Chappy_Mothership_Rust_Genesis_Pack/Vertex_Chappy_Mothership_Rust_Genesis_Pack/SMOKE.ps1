param([string]$Token='vertex-owner-local-test')
$headers=@{'X-Vertex-Owner-Token'=$Token;'Content-Type'='application/json'}
Write-Host "=== HEALTH ===" -ForegroundColor Cyan
Invoke-RestMethod 'http://127.0.0.1:9876/health' | ConvertTo-Json -Depth 10
Write-Host "=== CAPABILITIES ===" -ForegroundColor Cyan
Invoke-RestMethod 'http://127.0.0.1:9876/capabilities' -Headers $headers | ConvertTo-Json -Depth 10
Write-Host "=== MOTHERSHIP STATE ===" -ForegroundColor Cyan
$body=@{capability='READ_MOTHERSHIP_STATE';payload=@{};actor='owner'}|ConvertTo-Json -Depth 10
Invoke-RestMethod 'http://127.0.0.1:9876/mission' -Method Post -Headers $headers -Body $body | ConvertTo-Json -Depth 30
