# brightness.ps1 — screen brightness for Settings / Control Center on Windows.
#   brightness.ps1 get        -> prints 0-100 (nothing if no screen can be dimmed)
#   brightness.ps1 set 42     -> laptop panel (WMI), else every external monitor over DDC/CI
#   brightness.ps1 serve      -> long-running: reads a value per line on stdin and applies the newest
#                                one at once (smooth slider); prints the current value every 5 s
param([string]$Cmd = 'get', [int]$Value = 50)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class FFDdc {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct PM { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string d; }
  delegate bool EnumProc(IntPtr m, IntPtr dc, IntPtr r, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, EnumProc f, IntPtr p);
  [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr m, out uint n);
  [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr m, uint n, [Out] PM[] a);
  [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint n, PM[] a);
  [DllImport("dxva2.dll")] static extern bool GetMonitorBrightness(IntPtr h, out uint min, out uint cur, out uint max);
  [DllImport("dxva2.dll")] static extern bool SetMonitorBrightness(IntPtr h, uint v);
  static List<PM[]> All() {
    var l = new List<PM[]>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (m, dc, r, p) => { uint n; if (GetNumberOfPhysicalMonitorsFromHMONITOR(m, out n) && n > 0) { var a = new PM[n]; if (GetPhysicalMonitorsFromHMONITOR(m, n, a)) l.Add(a); } return true; }, IntPtr.Zero);
    return l;
  }
  public static int Get() {
    int r = -1;
    foreach (var a in All()) { foreach (var pm in a) { uint mn, c, mx; if (r < 0 && GetMonitorBrightness(pm.h, out mn, out c, out mx) && mx > mn) r = (int)Math.Round(100.0 * (c - mn) / (mx - mn)); } DestroyPhysicalMonitors((uint)a.Length, a); }
    return r;
  }
  // stdin on a background thread (Console.In.ReadLineAsync blocks in Windows PowerShell 5.1)
  public static System.Collections.Concurrent.ConcurrentQueue<string> Lines = new System.Collections.Concurrent.ConcurrentQueue<string>();
  public static volatile bool Eof = false;
  public static void StartReader() {
    var t = new System.Threading.Thread(() => { string l; while ((l = Console.In.ReadLine()) != null) Lines.Enqueue(l); Eof = true; });
    t.IsBackground = true; t.Start();
  }
  public static void Set(int pct) {
    foreach (var a in All()) { foreach (var pm in a) { uint mn, c, mx; if (GetMonitorBrightness(pm.h, out mn, out c, out mx) && mx > mn) SetMonitorBrightness(pm.h, (uint)(mn + (mx - mn) * pct / 100)); } DestroyPhysicalMonitors((uint)a.Length, a); }
  }
}
'@
$wmi = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness | Select-Object -First 1
$methods = if ($wmi) { Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods | Select-Object -First 1 }
function Set-Level([int]$v) {
    $v = [Math]::Max(1, [Math]::Min(100, $v))
    if ($methods) { Invoke-CimMethod -InputObject $methods -MethodName WmiSetBrightness -Arguments @{ Timeout = 0; Brightness = [byte]$v } | Out-Null }
    else { [FFDdc]::Set($v) }
}
function Get-Level {
    if ($wmi) { [int](Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness | Select-Object -First 1).CurrentBrightness }
    else { $g = [FFDdc]::Get(); if ($g -ge 0) { $g } }
}
if ($Cmd -eq 'set') { Set-Level $Value }
elseif ($Cmd -eq 'serve') {
    [FFDdc]::StartReader(); $next = [DateTime]::MinValue
    while ($true) {
        $want = $null; $line = $null
        while ([FFDdc]::Lines.TryDequeue([ref]$line)) { $want = $line.Trim() }      # keep only the newest value
        if ($null -eq $want -and [FFDdc]::Eof) { exit 0 }
        if ($want -match '^\d+$') { Set-Level ([int]$want); $next = (Get-Date).AddSeconds(2) }
        elseif ((Get-Date) -ge $next) { $l = Get-Level; if ($null -ne $l) { [Console]::Out.WriteLine($l); [Console]::Out.Flush() }; $next = (Get-Date).AddSeconds(5) }
        Start-Sleep -Milliseconds 15
    }
}
else { Get-Level }
