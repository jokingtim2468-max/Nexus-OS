# Third-party

## MacShell — MIT, Copyright (c) 2026 Rickky
https://github.com/0-ss/MacShell — vendored at `vendor/MacShell` (pristine upstream) and copied into
`macshell-win/macshell/` and `macshell-win/maclock/` (our Windows port, modified).
Bundles the Open Runde font (SIL Open Font License 1.1) and gemoji emoji data (MIT). Full license text: `vendor/MacShell/LICENSE`.

## Quickshell — LGPL-3.0, Copyright (c) outfoxxed and contributors
https://github.com/quickshell-mirror/quickshell — vendored at `macshell-win/quickshell/`
(commit recorded in `macshell-win/quickshell/UPSTREAM`). The first commit adding it is unmodified
upstream; our Windows changes are separate commits on top, so `git diff` shows exactly what we changed.
Full license text: `macshell-win/quickshell/LICENSE` (and `LICENSE-GPL`).
