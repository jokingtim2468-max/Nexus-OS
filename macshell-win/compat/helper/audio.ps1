# audio.ps1 — default speaker / microphone volume for the Pipewire stand-in, via Core Audio (IAudioEndpointVolume).
# Long-running: prints {"sink":{volume,muted,name},"source":{...}} whenever it changes; reads commands on stdin:
#   sink volume 0.42 | sink mute 1 | source volume 0.8 | source mute 0
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
public interface IMMDevice { int Activate(ref Guid id, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); int OpenPropertyStore(int a, out IntPtr s); int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); int GetState(out int s); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator { int EnumAudioEndpoints(int f, int m, out IntPtr d); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice d); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] public class MMDeviceEnumerator {}
public static class FFAudio {
  static IAudioEndpointVolume Ep(int flow) {
    var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d; e.GetDefaultAudioEndpoint(flow, 1, out d);
    var g = typeof(IAudioEndpointVolume).GUID; object o; d.Activate(ref g, 23, IntPtr.Zero, out o); return (IAudioEndpointVolume)o; }
  public static float Get(int flow) { try { float v; Ep(flow).GetMasterVolumeLevelScalar(out v); return v; } catch { return -1; } }
  public static bool Muted(int flow) { try { bool m; Ep(flow).GetMute(out m); return m; } catch { return true; } }
  public static void Set(int flow, float v) { Ep(flow).SetMasterVolumeLevelScalar(Math.Max(0f, Math.Min(1f, v)), Guid.Empty); }
  public static void Mute(int flow, bool m) { Ep(flow).SetMute(m, Guid.Empty); }
}
'@
$stdin = [Console]::In
$pending = $stdin.ReadLineAsync()
$last = ''
while ($true) {
    if ($pending.IsCompleted) {
        $line = $pending.Result
        if ($null -eq $line) { break }
        $f = $line.Trim() -split '\s+'
        $flow = if ($f[0] -eq 'source') { 1 } else { 0 }
        try {
            if ($f[1] -eq 'volume') { [FFAudio]::Set($flow, [float]$f[2]) }
            elseif ($f[1] -eq 'mute') { [FFAudio]::Mute($flow, $f[2] -eq '1') }
        } catch {}
        $pending = $stdin.ReadLineAsync()
    }
    $j = @{ sink = @{ volume = [Math]::Round([FFAudio]::Get(0), 3); muted = [FFAudio]::Muted(0) }
            source = @{ volume = [Math]::Round([FFAudio]::Get(1), 3); muted = [FFAudio]::Muted(1) } } | ConvertTo-Json -Compress
    if ($j -ne $last) { [Console]::Out.WriteLine($j); [Console]::Out.Flush(); $last = $j }
    Start-Sleep -Milliseconds 250
}
