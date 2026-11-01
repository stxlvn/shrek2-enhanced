/* Test-only proxy for shfolder.dll: when SHREK2_DOCS is set, the "My Documents" folder (CSIDL_PERSONAL)
 * of the process is that folder, so a tool such as ucc keeps its ini and log inside a sandbox.
 * Everything else is passed to shell32. Never installed next to the owner's game. */
#include <windows.h>
#include <string.h>

typedef HRESULT (WINAPI *PFW)(HWND, int, HANDLE, DWORD, LPWSTR);
typedef HRESULT (WINAPI *PFA)(HWND, int, HANDLE, DWORD, LPSTR);

static HRESULT real_w(HWND h, int csidl, HANDLE t, DWORD f, LPWSTR p)
{
	static PFW fn;
	if (!fn) fn = (PFW)GetProcAddress(LoadLibraryA("shell32.dll"), "SHGetFolderPathW");
	return fn ? fn(h, csidl, t, f, p) : E_FAIL;
}

HRESULT WINAPI SHGetFolderPathW(HWND h, int csidl, HANDLE t, DWORD f, LPWSTR p)
{
	wchar_t dir[MAX_PATH];
	if ((csidl & 0xff) == 0x05 && p && GetEnvironmentVariableW(L"SHREK2_DOCS", dir, MAX_PATH) > 0) {
		wcsncpy(p, dir, MAX_PATH - 1);
		p[MAX_PATH - 1] = 0;
		return S_OK;
	}
	return real_w(h, csidl, t, f, p);
}

HRESULT WINAPI SHGetFolderPathA(HWND h, int csidl, HANDLE t, DWORD f, LPSTR p)
{
	wchar_t w[MAX_PATH];
	HRESULT r = SHGetFolderPathW(h, csidl, t, f, w);
	if (r == S_OK && p) WideCharToMultiByte(CP_ACP, 0, w, -1, p, MAX_PATH, NULL, NULL);
	return r;
}
