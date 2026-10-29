// macshell-helper.exe — lets Windows programs (Quickshell's Process) run the Python helper.
// CreateProcess only finds .exe files, so MacShell's `macshell-helper ...` calls land here.
// Runs <package>\python\pythonw.exe (else pythonw on PATH) with macshell_helper.py next to this
// exe, the same arguments, inherited stdin/stdout/stderr; returns its exit code. Built under other
// names too (xdg-open.exe, brightnessctl.exe, ...): then that name goes first, e.g. `xdg-open URL`
// runs `macshell_helper.py xdg-open URL`. Console program:
// Qt starts it with CREATE_NO_WINDOW from the shell, so no window flashes.
#include <windows.h>
#include <wchar.h>

static const wchar_t* skip_arg0(const wchar_t* cmd) {
	if (*cmd == L'"') { cmd++; while (*cmd && *cmd != L'"') cmd++; if (*cmd) cmd++; }
	else while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
	while (*cmd == L' ' || *cmd == L'\t') cmd++;
	return cmd;
}

int wmain(void) {
	wchar_t dir[MAX_PATH], py[MAX_PATH], script[MAX_PATH];
	GetModuleFileNameW(NULL, dir, MAX_PATH);
	wchar_t* slash = wcsrchr(dir, L'\\');
	wchar_t tool[MAX_PATH] = L"";
	if (slash) {
		*slash = 0;
		wcscpy(tool, slash + 1);
		wchar_t* dot = wcsrchr(tool, L'.');
		if (dot) *dot = 0;
		if (_wcsicmp(tool, L"macshell-helper") == 0) tool[0] = 0;
	}

	swprintf(script, MAX_PATH, L"%ls\\macshell_helper.py", dir);
	swprintf(py, MAX_PATH, L"%ls\\..\\..\\python\\pythonw.exe", dir);   // package: <root>\compat\helper
	if (GetFileAttributesW(py) == INVALID_FILE_ATTRIBUTES) wcscpy(py, L"pythonw.exe");

	const wchar_t* args = skip_arg0(GetCommandLineW());
	size_t n = wcslen(py) + wcslen(script) + wcslen(tool) + wcslen(args) + 16;
	wchar_t* cmd = HeapAlloc(GetProcessHeap(), 0, n * sizeof(wchar_t));
	swprintf(cmd, n, tool[0] ? L"\"%ls\" \"%ls\" %ls %ls" : L"\"%ls\" \"%ls\" %ls%ls", py, script, tool, args);

	STARTUPINFOW si = { sizeof(si) };
	si.dwFlags = STARTF_USESTDHANDLES;
	si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
	si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
	si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
	PROCESS_INFORMATION pi;
	if (!CreateProcessW(NULL, cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) return 127;
	WaitForSingleObject(pi.hProcess, INFINITE);
	DWORD code = 1;
	GetExitCodeProcess(pi.hProcess, &code);
	CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
	return (int)code;
}
