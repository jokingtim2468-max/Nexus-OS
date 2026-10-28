#pragma once

// Windows replacements for the POSIX primitives Quickshell uses on Linux.
// Only compiled and included on Windows.

#include <qstring.h>
#include <qtypes.h>

namespace qs::win {

// Replaces fcntl(F_GETLK) on instance.lock: an instance is live while its process is.
bool pidAlive(qint64 pid);

// Replaces fcntl(F_SETLK) for whole-process locks. Takes a session-local named mutex
// derived from `path`; returns false if another process already holds it.
// The mutex is held until the process exits.
bool tryProcessLock(const QString& path);

// Replaces symlinkat() for the by-id / by-pid / by-path run dir links. Creates an NTFS
// directory junction (no admin rights or Developer Mode needed), replacing any old one.
bool makeDirLink(const QString& target, const QString& link);

} // namespace qs::win
