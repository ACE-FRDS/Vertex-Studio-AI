param([string]$Token='vertex-demo-owner-token')
$headers=@{
  'X-Vertex-Owner-Token'=$Token
  'Content-Type'='application/json'
}
$body=@{
  mission_type='RELATION_QUERY'
  capability='QUERY_RELATIONS'
  payload=@{
    asset_id='unit://fme/enterprise-ui-core'
    mode='impact'
    max_depth=4
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod 'http://127.0.0.1:8765/mission' -Method Post -Headers $headers -Body $body
