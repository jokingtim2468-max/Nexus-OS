# CI helper: a screenshot that includes layered (translucent) windows, like FreeForm's panels.
# .NET's CopyFromScreen leaves those out, and rejects the CAPTUREBLT flag. Dot-source, then:
#   $bmp = [ScreenGrab]::Grab($width, $height)
Add-Type -ReferencedAssemblies System.Drawing.Common, System.Drawing.Primitives -TypeDefinition @"
using System; using System.Drawing; using System.Runtime.InteropServices;
public static class ScreenGrab {
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr d, int x, int y, int w, int h, IntPtr s, int sx, int sy, int op);
    public static Bitmap Grab(int w, int h) {
        var bmp = new Bitmap(w, h);
        using (var g = Graphics.FromImage(bmp)) {
            IntPtr dst = g.GetHdc(), src = GetDC(IntPtr.Zero);
            BitBlt(dst, 0, 0, w, h, src, 0, 0, 0x00CC0020 | 0x40000000);   // SRCCOPY | CAPTUREBLT
            ReleaseDC(IntPtr.Zero, src); g.ReleaseHdc(dst);
        }
        return bmp;
    }
}
"@
