# Custom distros

Drop a distro file here to use your own Linux in FreeForm:

- a `.iso` installer/live image, or
- a rootfs tarball, or
- a small manifest describing where to get it.

Then add an entry under `"custom"` in `../registry.json` (or let the loader
auto-detect files in this folder). It will appear in the loader with the same
FreeForm UI as the recommended distros.
