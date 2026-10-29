# audio.ps1 — default speaker / microphone volume for the Pipewire stand-in, via Core Audio (IAudioEndpointVolume).
# Long-running: prints {"sink":{volume,muted,name},"source":{...}} whenever it changes; reads commands on stdin:
#   sink volume 0.42 | sink mute 1 | source volume 0.8 | source mute 0 | default <endpoint id>
# Every ~2 s it also lists the active devices: "outs"/"ins": [{id,name}], "defOut"/"defIn": id.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
  int RegisterControlChangeNotify(IntPtr p); int UnregisterControlChangeNotify(IntPtr p);
  int GetChannelCount(out uint c); int SetMasterVolumeLevel(float l, Guid g); int SetMasterVolumeLevelScalar(float l, Guid g);
  int GetMasterVolumeLevel(out float l); int GetMasterVolumeLevelScalar(out float l);
  int SetChannelVolumeLevel(uint c, float l, Guid g); int SetChannelVolumeLevelScalar(uint c, float l, Guid g);
  int GetChannelVolumeLevel(uint c, out float l); int GetChannelVolumeLevelScalar(uint c, out float l);
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool m, Guid g); int GetMute(out bool m);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice { int Activate(ref Guid id, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); int OpenPropertyStore(int a, out IPropertyStore s); int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); int GetState(out int s); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator { int EnumAudioEndpoints(int f, int m, out IMMDeviceCollection d); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice d); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] public class MMDeviceEnumerator {}
[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceCollection { int GetCount(out int n); int Item(int i, out IMMDevice d); }
[StructLayout(LayoutKind.Sequential)] public struct PropKey { public Guid fmt; public int pid; }
[StructLayout(LayoutKind.Sequential)] public struct PropVar { public short vt; short r1, r2, r3; public IntPtr p; IntPtr p2; }
[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore { int GetCount(out int n); int GetAt(int i, out PropKey k); int GetValue(ref PropKey k, out PropVar v); }
// undocumented but stable since Windows 7: what the Sound control panel uses to change the default device
[Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPolicyConfig { int a(); int b(); int c(); int d(); int e(); int f(); int g(); int h(); int i(); int j();
  int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role); }
[ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")] public class PolicyConfigClient {}
public static class FFAudio {
  static IAudioEndpointVolume Ep(int flow) {
    var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d; e.GetDefaultAudioEndpoint(flow, 1, out d);
    var g = typeof(IAudioEndpointVolume).GUID; object o; d.Activate(ref g, 23, IntPtr.Zero, out o); return (IAudioEndpointVolume)o; }
  public static float Get(int flow) { try { float v; Ep(flow).GetMasterVolumeLevelScalar(out v); return v; } catch { return -1; } }
  public static bool Muted(int flow) { try { bool m; Ep(flow).GetMute(out m); return m; } catch { return true; } }
  public static void Set(int flow, float v) { Ep(flow).SetMasterVolumeLevelScalar(Math.Max(0f, Math.Min(1f, v)), Guid.Empty); }
  public static void Mute(int flow, bool m) { Ep(flow).SetMute(m, Guid.Empty); }
  public static string DefaultId(int flow) { try { var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d; e.GetDefaultAudioEndpoint(flow, 1, out d); string id; d.GetId(out id); return id; } catch { return ""; } }
  // [[id, friendly name], ...] of the active devices for one direction
  public static string[][] List(int flow) {
    var r = new System.Collections.Generic.List<string[]>();
    try {
      var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDeviceCollection c; e.EnumAudioEndpoints(flow, 1, out c);
      int n; c.GetCount(out n);
      var key = new PropKey { fmt = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };   // PKEY_Device_FriendlyName
      for (int i = 0; i < n; i++) {
        IMMDevice d; c.Item(i, out d); string id; d.GetId(out id);
        string name = id;
        try { IPropertyStore ps; d.OpenPropertyStore(0, out ps); PropVar v; ps.GetValue(ref key, out v); if (v.vt == 31) name = Marshal.PtrToStringUni(v.p); } catch {}
        r.Add(new[] { id, name });
      }
    } catch {}
    return r.ToArray();
  }
  public static void SetDefault(string id) { var p = (IPolicyConfig)new PolicyConfigClient(); for (int role = 0; role < 3; role++) p.SetDefaultEndpoint(id, role); }
}
'@
$stdin = [Console]::In
$pending = $stdin.ReadLineAsync()
$last = ''
$tick = 0; $devs = @{}
while ($true) {
    if ($pending.IsCompleted) {
        $line = $pending.Result
        if ($null -eq $line) { break }
        $f = $line.Trim() -split '\s+'
        $flow = if ($f[0] -eq 'source') { 1 } else { 0 }
        try {
            if ($f[0] -eq 'default') { [FFAudio]::SetDefault($line.Trim().Substring(8)); $tick = 0 }
            elseif ($f[1] -eq 'volume') { [FFAudio]::Set($flow, [float]$f[2]) }
            elseif ($f[1] -eq 'mute') { [FFAudio]::Mute($flow, $f[2] -eq '1') }
        } catch {}
        $pending = $stdin.ReadLineAsync()
    }
    if ($tick -le 0) {
        $tick = 8
        $devs = @{ outs = @([FFAudio]::List(0) | ForEach-Object { @{ id = $_[0]; name = $_[1] } }); defOut = [FFAudio]::DefaultId(0)
                   ins = @([FFAudio]::List(1) | ForEach-Object { @{ id = $_[0]; name = $_[1] } }); defIn = [FFAudio]::DefaultId(1) }
    }
    $tick--
    $j = @{ outs = $devs.outs; ins = $devs.ins; defOut = $devs.defOut; defIn = $devs.defIn; sink = @{ volume = [Math]::Round([FFAudio]::Get(0), 3); muted = [FFAudio]::Muted(0) }
            source = @{ volume = [Math]::Round([FFAudio]::Get(1), 3); muted = [FFAudio]::Muted(1) } } | ConvertTo-Json -Compress -Depth 4
    if ($j -ne $last) { [Console]::Out.WriteLine($j); [Console]::Out.Flush(); $last = $j }
    Start-Sleep -Milliseconds 250
}
