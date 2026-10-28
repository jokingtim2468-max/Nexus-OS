# power.ps1 — battery for the UPower stand-in: {"present":bool,"percentage":0-100,"state":"Charging|Discharging|FullyCharged|Unknown"}
$b = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $b) { '{"present":false,"percentage":0,"state":"Unknown"}'; exit 0 }
$st = switch ([int]$b.BatteryStatus) { 1 { 'Discharging' } 2 { if ($b.EstimatedChargeRemaining -ge 99) { 'FullyCharged' } else { 'Charging' } } 3 { 'FullyCharged' } { $_ -in 6..9 } { 'Charging' } default { 'Unknown' } }
@{ present = $true; percentage = [int]$b.EstimatedChargeRemaining; state = $st } | ConvertTo-Json -Compress
