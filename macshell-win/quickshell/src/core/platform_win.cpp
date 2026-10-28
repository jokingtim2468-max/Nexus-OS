#include "platform_win.hpp"

#include <qcryptographichash.h>
#include <windows.h>

namespace qs::win {

bool pidAlive(qint64 pid) {
	if (pid <= 0) return false;

	auto* process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(pid));
	if (!process) return GetLastError() == ERROR_ACCESS_DENIED; // exists, owned by someone else

	DWORD code = 0;
	auto alive = GetExitCodeProcess(process, &code) && code == STILL_ACTIVE;
	CloseHandle(process);
	return alive;
}

bool tryProcessLock(const QString& path) {
	auto hash = QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1).toHex();
	auto name = QStringLiteral("Local\\quickshell-lock-") + QString::fromLatin1(hash);

	auto* mutex = CreateMutexW(nullptr, TRUE, reinterpret_cast<LPCWSTR>(name.utf16()));
	if (!mutex) return false;

	if (GetLastError() == ERROR_ALREADY_EXISTS) {
		CloseHandle(mutex);
		return false;
	}

	return true; // intentionally leaked: released when the process exits
}

} // namespace qs::win
