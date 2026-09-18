$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:5000'
$repo = 'demo/wasm'
$payload = [System.Text.Encoding]::UTF8.GetBytes('hello from a Wasm-style OCI artifact')
$sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($payload)
$hex = -join ($sha | ForEach-Object { $_.ToString('x2') })
$digest = "sha256:$hex"

$id = (Invoke-WebRequest -Method Post -Uri "$base/v2/$repo/blobs/uploads/").Headers['Docker-Upload-UUID']
$null = Invoke-WebRequest -Method Put -Uri "$base/v2/$repo/blobs/uploads/$id`?digest=$digest" -Body $payload -ContentType 'application/octet-stream'

$manifest = '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/wasm","digest":"' + $digest + '","size":' + $payload.Length + '},"layers":[]}'
$null = Invoke-WebRequest -Method Put -Uri "$base/v2/$repo/manifests/v1" -Body $manifest -ContentType 'application/vnd.oci.image.manifest.v1+json'
Write-Output (Invoke-RestMethod -Uri "$base/v2/$repo/manifests/v1")
Write-Output (Invoke-RestMethod -Uri "$base/v2/$repo/tags/list")
