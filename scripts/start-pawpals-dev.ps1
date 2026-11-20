# Jalankan dari PowerShell, setelah npm ci dan npm run build. Tidak mengubah .env.
$Root = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $Root 'BackEnd'
$Frontend = Join-Path $Root 'FrontEnd'
if (!(Test-Path (Join-Path $Backend '.env'))) { throw 'Pertahankan BackEnd/.env lama sebelum menjalankan.' }
if (!(Test-Path (Join-Path $Backend 'dist/server.js'))) { throw 'Jalankan npm run build di BackEnd terlebih dahulu.' }
if (!(Test-Path (Join-Path $Frontend 'node_modules'))) { throw 'Jalankan npm ci di FrontEnd terlebih dahulu.' }
Start-Process powershell -WorkingDirectory $Backend -ArgumentList '-NoExit','-Command','npm start'
Start-Process powershell -WorkingDirectory $Backend -ArgumentList '-NoExit','-Command','$env:NODE_PATH=(Join-Path (Get-Location).Path "node_modules"); node ../scripts/pawpals-local-media.cjs'
Start-Process powershell -WorkingDirectory $Frontend -ArgumentList '-NoExit','-Command','npm run dev'
if (Test-NetConnection 127.0.0.1 -Port 6379 -InformationLevel Quiet) { Start-Process powershell -WorkingDirectory $Backend -ArgumentList '-NoExit','-Command','npm run worker' } else { Write-Warning 'Redis port 6379 belum aktif. Jalankan Redis dan npm run worker secara manual.' }
