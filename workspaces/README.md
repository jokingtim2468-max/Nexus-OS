# Workspaces

Each distro the VM Hub launches gets a persistent workspace here:
`workspaces/<distro-id>/disk.qcow2` (its saved disk) + `meta.json`.

These are **machine-local and git-ignored** — your Kali/Ubuntu/etc. state lives
here and is not committed. Create one with:

    python3 apps/vmhub/vmhub.py create kali --run
