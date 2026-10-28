# winnet.ps1 — Windows network / Bluetooth backend for macshell-helper.
# Uses only public, language-independent Windows APIs (WinRT Radio / WiFiAdapter /
# NetworkInformation / Bluetooth + NetAdapter cmdlets), so it works on any Windows
# display language and needs no admin rights (except enabling/disabling an Ethernet adapter).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File winnet.ps1 <command> [args]
#
# Queries print one JSON object on stdout. Actions exit 0 on success; on failure they
# print an nmcli/bluetoothctl-style message on stderr (MacShell shows it) and exit non-zero.
# Must run under Windows PowerShell 5.1 (powershell.exe), which has the WinRT projection.

param([Parameter(Position = 0)][string]$Cmd, [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$script:asTaskOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$script:asTaskAct = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function Await($op, [Type]$type) {
    $t = $script:asTaskOp.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result
}
function AwaitAction($op) { $t = $script:asTaskAct.Invoke($null, @($op)); $t.Wait(-1) | Out-Null }

[void][Windows.Devices.Radios.Radio, Windows.Devices.Radios, ContentType = WindowsRuntime]
[void][Windows.Devices.WiFi.WiFiAdapter, Windows.Devices.WiFi, ContentType = WindowsRuntime]
[void][Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
[void][Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
[void][Windows.Devices.Bluetooth.BluetoothDevice, Windows.Devices.Bluetooth, ContentType = WindowsRuntime]
[void][Windows.Security.Credentials.PasswordCredential, Windows.Security.Credentials, ContentType = WindowsRuntime]

function Fail([string]$msg, [int]$code = 1) { [Console]::Error.WriteLine($msg); exit $code }
function Out-Json($o) { $o | ConvertTo-Json -Depth 5 -Compress }

# ── radios (Wi-Fi / Bluetooth on-off, like the quick-settings tiles) ──
function Get-Radios {
    $null = Await ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
    Await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
}
function Get-Radio([string]$kind) { Get-Radios | Where-Object { "$($_.Kind)" -eq $kind } | Select-Object -First 1 }
function Set-Radio([string]$kind, [bool]$on) {
    $r = Get-Radio $kind
    if (-not $r) { Fail "No $kind radio found on this PC." 2 }
    $state = if ($on) { [Windows.Devices.Radios.RadioState]::On } else { [Windows.Devices.Radios.RadioState]::Off }
    $res = Await ($r.SetStateAsync($state)) ([Windows.Devices.Radios.RadioAccessStatus])
    if ("$res" -ne 'Allowed') { Fail "Windows refused to change the $kind radio ($res)." 3 }
}

# ── wi-fi ──
function Get-WifiAdapter {
    $null = Await ([Windows.Devices.WiFi.WiFiAdapter]::RequestAccessAsync()) ([Windows.Devices.WiFi.WiFiAccessStatus])
    $all = Await ([Windows.Devices.WiFi.WiFiAdapter]::FindAllAdaptersAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.WiFi.WiFiAdapter]])
    if ($all.Count -gt 0) { $all[0] } else { $null }
}
function Get-WlanProfiles { [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles() | Where-Object { $_.IsWlanConnectionProfile } }
function Get-Current {
    foreach ($p in Get-WlanProfiles) {
        $ssid = $p.WlanConnectionProfileDetails.GetConnectedSsid()
        if ($ssid) {
            $bars = $p.GetSignalBars()
            return @{ ssid = $ssid; signal = $(if ($bars -ne $null) { [int]$bars * 20 } else { 60 }) }
        }
    }
    @{ ssid = ''; signal = 0 }
}
function Get-Ethernet {
    @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq '802.3' } | ForEach-Object {
            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
            @{ name = $_.Name; device = $_.InterfaceDescription; up = ($_.Status -eq 'Up'); ip = "$ip"
                speed = [int]([long]$_.ReceiveLinkSpeed / 1000000) }
        })
}
function Rssi-To-Percent([double]$dbm) { [int][Math]::Max(0, [Math]::Min(100, 2 * ($dbm + 100))) }

switch ($Cmd) {
    'status' {
        $w = Get-Radio 'WiFi'; $c = Get-Current
        $up = @(Get-Ethernet | Where-Object { $_.up }).Count -gt 0
        Out-Json @{ wifi_on = [bool]($w -and "$($w.State)" -eq 'On'); ssid = $c.ssid; signal = $c.signal; ethernet_up = $up }
    }
    'wifilist' {
        $a = Get-WifiAdapter
        if (-not $a) { Out-Json @{ networks = @(); saved = @() }; break }
        AwaitAction ($a.ScanAsync())
        $cur = (Get-Current).ssid
        $nets = @($a.NetworkReport.AvailableNetworks | Where-Object { $_.Ssid } | ForEach-Object {
                $auth = "$($_.SecuritySettings.NetworkAuthenticationType)"
                @{ ssid = $_.Ssid; signal = (Rssi-To-Percent $_.NetworkRssiInDecibelMilliwatts)
                    secure = -not ($auth -eq 'Open80211' -or $auth -eq 'None'); inUse = ($_.Ssid -eq $cur) }
            })
        Out-Json @{ networks = $nets; saved = @(Get-WlanProfiles | ForEach-Object { $_.ProfileName }) }
    }
    'wificonnect' {
        $ssid = $Rest[0]; $pw = if ($Rest.Count -gt 1) { $Rest[1] } else { '' }
        $a = Get-WifiAdapter
        if (-not $a) { Fail 'Error: No Wi-Fi adapter.' 2 }
        AwaitAction ($a.ScanAsync())
        $n = $a.NetworkReport.AvailableNetworks | Where-Object { $_.Ssid -eq $ssid } | Select-Object -First 1
        if (-not $n) { Fail "Error: No network with SSID '$ssid' found." 10 }
        $kind = [Windows.Devices.WiFi.WiFiReconnectionKind]::Automatic
        if ($pw) {
            $cred = New-Object Windows.Security.Credentials.PasswordCredential; $cred.Password = $pw
            $res = Await ($a.ConnectAsync($n, $kind, $cred)) ([Windows.Devices.WiFi.WiFiConnectionResult])
        } else {
            $res = Await ($a.ConnectAsync($n, $kind)) ([Windows.Devices.WiFi.WiFiConnectionResult])
        }
        switch ("$($res.ConnectionStatus)") {
            'Success' { exit 0 }
            'InvalidCredential' { Fail 'Error: Secrets were required, but not provided.' 4 }
            'NetworkNotAvailable' { Fail "Error: No network with SSID '$ssid' found." 10 }
            default { Fail "Error: Connection failed ($($res.ConnectionStatus))." 5 }
        }
    }
    'wifidisconnect' { $a = Get-WifiAdapter; if ($a) { $a.Disconnect() } }
    'radio' {   # radio wifi|bluetooth on|off
        $kind = if ($Rest[0] -eq 'bluetooth') { 'Bluetooth' } else { 'WiFi' }
        Set-Radio $kind ($Rest[1] -eq 'on')
    }
    'airplane' {   # all radios off (on) / back on (off), like the Airplane mode tile
        $on = ($Rest[0] -ne 'on')
        foreach ($r in Get-Radios) {
            $st = if ($on) { [Windows.Devices.Radios.RadioState]::On } else { [Windows.Devices.Radios.RadioState]::Off }
            $null = Await ($r.SetStateAsync($st)) ([Windows.Devices.Radios.RadioAccessStatus])
        }
    }
    'conns' {
        $vpn = @(Get-VpnConnection -ErrorAction SilentlyContinue | ForEach-Object { @{ name = $_.Name; connected = ("$($_.ConnectionStatus)" -eq 'Connected') } })
        Out-Json @{ eth = @(Get-Ethernet); vpn = $vpn }
    }
    'conn' {   # conn up|down <name>   (Ethernet adapter or VPN)
        $up = $Rest[0] -eq 'up'; $name = $Rest[1]
        if (Get-VpnConnection -Name $name -ErrorAction SilentlyContinue) {
            $out = if ($up) { rasdial "$name" 2>&1 } else { rasdial "$name" /disconnect 2>&1 }
            if ($LASTEXITCODE -ne 0) { Fail "Error: $($out | Select-Object -Last 1)" 6 }
        } else {
            try { if ($up) { Enable-NetAdapter -Name $name -Confirm:$false } else { Disable-NetAdapter -Name $name -Confirm:$false } }
            catch { Fail 'Error: Turning a network adapter on or off needs administrator rights.' 7 }
        }
    }
    'bt' {
        $r = Get-Radio 'Bluetooth'
        $devs = @()
        foreach ($sel in @([Windows.Devices.Bluetooth.BluetoothDevice]::GetDeviceSelectorFromPairingState($true))) {
            $infos = Await ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($sel)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
            foreach ($i in $infos) {
                try { $d = Await ([Windows.Devices.Bluetooth.BluetoothDevice]::FromIdAsync($i.Id)) ([Windows.Devices.Bluetooth.BluetoothDevice]) } catch { continue }
                if (-not $d) { continue }
                $mac = ('{0:X12}' -f $d.BluetoothAddress) -replace '(..)(?!$)', '$1:'
                $devs += @{ mac = $mac; name = $i.Name; paired = $true; connected = ("$($d.ConnectionStatus)" -eq 'Connected'); battery = '' }
            }
        }
        Out-Json @{ on = [bool]($r -and "$($r.State)" -eq 'On'); present = [bool]$r; devices = $devs }
    }
    default { Fail "winnet.ps1: unknown command '$Cmd'" 64 }
}
exit 0
