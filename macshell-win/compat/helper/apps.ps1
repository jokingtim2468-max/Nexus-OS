# apps.ps1 — every app in the Start Menu (shortcuts + Microsoft Store apps), with a 256 px icon.
# Prints one JSON array: [{ name, launch, target, icon }]. Used by `macshell-helper apps sync`.
param([string]$IconDir, [switch]$NoIcons)   # -NoIcons: fast list, only icons already extracted
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $OutputEncoding = [System.Text.Encoding]::UTF8   # é, ñ, ó... reach FreeForm intact
$ErrorActionPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $IconDir | Out-Null
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class FFIcon {
  [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellItemImageFactory { void GetImage(SIZE size, int flags, out IntPtr phbm); }
  [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx, cy; public SIZE(int x, int y) { cx = x; cy = y; } }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
  static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);
  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);
  // 256 px icon (with transparency) for a file, shortcut or "shell:AppsFolder\<AUMID>"
  public static bool Save(string parsingName, string png) {
    try {
      Guid iid = typeof(IShellItemImageFactory).GUID; IShellItemImageFactory f;
      SHCreateItemFromParsingName(parsingName, IntPtr.Zero, ref iid, out f);
      IntPtr hbm; f.GetImage(new SIZE(256, 256), 0x1 /* SIIGBF_BIGGERSIZEOK */ | 0x4 /* ICONONLY */, out hbm);
      using (var b = Image.FromHbitmap(hbm)) {
        var bd = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, b.PixelFormat);
        using (var a = new Bitmap(b.Width, b.Height, bd.Stride, PixelFormat.Format32bppArgb, bd.Scan0)) a.Save(png, ImageFormat.Png);
        b.UnlockBits(bd);
      }
      DeleteObject(hbm); return true;
    } catch { return false; }
  }
}
'@
function Safe([string]$s) { ($s -replace '[^A-Za-z0-9._-]', '_').ToLower() }
$ws = New-Object -ComObject WScript.Shell
$out = @(); $seen = @{}
$dirs = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")
foreach ($lnk in Get-ChildItem $dirs -Recurse -Filter *.lnk) {
    $t = $ws.CreateShortcut($lnk.FullName).TargetPath
    if (-not $t -or $t -notmatch '\.exe$') { continue }                  # skip docs, URLs, uninstallers' folders
    if ($lnk.BaseName -match '(?i)uninstall|readme|help|website|documentation') { continue }
    $key = $lnk.BaseName.ToLower(); if ($seen[$key]) { continue }; $seen[$key] = 1
    $png = Join-Path $IconDir ((Safe $lnk.BaseName) + '.png')
    if (-not $NoIcons -and -not (Test-Path $png)) { [void][FFIcon]::Save($lnk.FullName, $png) }
    $out += @{ name = $lnk.BaseName; launch = $lnk.FullName; target = $t; icon = $(if (Test-Path $png) { $png } else { '' }) }
}
[Console]::Error.WriteLine("[apps] Start Menu shortcuts: $($out.Count)")
foreach ($a in Get-StartApps) {                                          # Store apps: AUMIDs contain '!'
    if ($a.AppID -notmatch '!') { continue }
    $key = $a.Name.ToLower(); if ($seen[$key]) { continue }; $seen[$key] = 1
    $png = Join-Path $IconDir ((Safe $a.Name) + '.png')
    if (-not $NoIcons -and -not (Test-Path $png)) { [void][FFIcon]::Save("shell:AppsFolder\$($a.AppID)", $png) }
    $out += @{ name = $a.Name; launch = "shell:AppsFolder\$($a.AppID)"; target = ''; icon = $(if (Test-Path $png) { $png } else { '' }) }
}
[Console]::Error.WriteLine("[apps] with Store apps: $($out.Count)")
ConvertTo-Json -InputObject $out -Compress -Depth 3
