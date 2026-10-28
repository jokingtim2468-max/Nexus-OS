#include "platform_win.hpp"

#include <cstring>
#include <vector>

#include <qcryptographichash.h>
#include <qdir.h>
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

bool makeDirLink(const QString& target, const QString& link) {
	auto linkPath = QDir::toNativeSeparators(link).toStdWString();
	RemoveDirectoryW(linkPath.c_str()); // an old junction; never touches its target
	if (!CreateDirectoryW(linkPath.c_str(), nullptr)) return false;

	auto* handle = CreateFileW(
	    linkPath.c_str(),
	    GENERIC_WRITE,
	    0,
	    nullptr,
	    OPEN_EXISTING,
	    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
	    nullptr
	);
	if (handle == INVALID_HANDLE_VALUE) return false;

	// REPARSE_DATA_BUFFER (MountPointReparseBuffer) isn't in MinGW's headers; build it by hand.
	auto substitute = L"\\??\\" + QDir::toNativeSeparators(target).toStdWString();
	auto print = QDir::toNativeSeparators(target).toStdWString();
	auto subBytes = static_cast<WORD>(substitute.size() * sizeof(wchar_t));
	auto printBytes = static_cast<WORD>(print.size() * sizeof(wchar_t));

	constexpr DWORD headerSize = 8;  // ReparseTag, ReparseDataLength, Reserved
	constexpr DWORD offsetsSize = 8; // Substitute/Print name offset + length
	auto pathBytes = subBytes + sizeof(wchar_t) + printBytes + sizeof(wchar_t);
	auto dataLength = static_cast<WORD>(offsetsSize + pathBytes);
	auto buffer = std::vector<BYTE>(headerSize + dataLength, 0);

	auto put16 = [&](size_t at, WORD v) { std::memcpy(buffer.data() + at, &v, sizeof(v)); };
	DWORD tag = IO_REPARSE_TAG_MOUNT_POINT;
	std::memcpy(buffer.data(), &tag, sizeof(tag));
	put16(4, dataLength);
	put16(8, 0);                                              // SubstituteNameOffset
	put16(10, subBytes);                                      // SubstituteNameLength
	put16(12, static_cast<WORD>(subBytes + sizeof(wchar_t))); // PrintNameOffset
	put16(14, printBytes);                                    // PrintNameLength
	std::memcpy(buffer.data() + 16, substitute.c_str(), subBytes);
	std::memcpy(buffer.data() + 16 + subBytes + sizeof(wchar_t), print.c_str(), printBytes);

	DWORD returned = 0;
	auto ok = DeviceIoControl(
	    handle,
	    FSCTL_SET_REPARSE_POINT,
	    buffer.data(),
	    static_cast<DWORD>(buffer.size()),
	    nullptr,
	    0,
	    &returned,
	    nullptr
	);
	CloseHandle(handle);

	if (!ok) RemoveDirectoryW(linkPath.c_str());
	return ok != 0;
}

} // namespace qs::win
