/* Test-only proxy for msvcr70.dll: forwards everything to msvcr70_real.dll and gives
 * every process its own "UnrealIsRunning" mutex so two copies of the sandbox game can run.
 * Only used in the sandbox copy, never in the owner's install. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static HANDLE (WINAPI *real_CreateMutexA)(LPSECURITY_ATTRIBUTES, BOOL, LPCSTR);
static HANDLE (WINAPI *real_CreateMutexW)(LPSECURITY_ATTRIBUTES, BOOL, LPCWSTR);

static HANDLE WINAPI my_CreateMutexA(LPSECURITY_ATTRIBUTES sa, BOOL own, LPCSTR name)
{
	char buf[128];
	if (name && strcmp(name, "UnrealIsRunning") == 0) {
		snprintf(buf, sizeof buf, "UnrealIsRunning-%lu", GetCurrentProcessId());
		name = buf;
	}
	return real_CreateMutexA(sa, own, name);
}

static HANDLE WINAPI my_CreateMutexW(LPSECURITY_ATTRIBUTES sa, BOOL own, LPCWSTR name)
{
	wchar_t buf[128];
	if (name && wcscmp(name, L"UnrealIsRunning") == 0) {
		swprintf(buf, 128, L"UnrealIsRunning-%lu", GetCurrentProcessId());
		name = buf;
	}
	return real_CreateMutexW(sa, own, name);
}


/* Test isolation: when SHREK2_DOCS is set, the game's "My Documents" is that folder,
 * so a sandbox copy keeps its own ini, log and saves. */
static HRESULT (WINAPI *real_SHGetFolderPathW)(HWND, int, HANDLE, DWORD, LPWSTR);
static FARPROC (WINAPI *real_GetProcAddress)(HMODULE, LPCSTR);

static HRESULT WINAPI my_SHGetFolderPathW(HWND w, int csidl, HANDLE tok, DWORD fl, LPWSTR out)
{
	wchar_t dir[MAX_PATH];
	if ((csidl & 0xff) == 0x05 && out && GetEnvironmentVariableW(L"SHREK2_DOCS", dir, MAX_PATH) > 0) {
		wcsncpy(out, dir, MAX_PATH - 1);
		out[MAX_PATH - 1] = 0;
		return 0; /* S_OK */
	}
	return real_SHGetFolderPathW ? real_SHGetFolderPathW(w, csidl, tok, fl, out) : E_FAIL;
}

static FARPROC WINAPI my_GetProcAddress(HMODULE m, LPCSTR name)
{
	FARPROC f = real_GetProcAddress(m, name);
	if (f && !((ULONG_PTR)name < 0x10000) && strcmp(name, "SHGetFolderPathW") == 0) {
		real_SHGetFolderPathW = (void *)f;
		return (FARPROC)my_SHGetFolderPathW;
	}
	return f;
}

static void patch_module(HMODULE mod)
{
	BYTE *base = (BYTE *)mod;
	IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
	IMAGE_NT_HEADERS *nt;
	IMAGE_DATA_DIRECTORY *dir;
	IMAGE_IMPORT_DESCRIPTOR *imp;
	if (!mod || dos->e_magic != IMAGE_DOS_SIGNATURE)
		return;
	nt = (IMAGE_NT_HEADERS *)(base + dos->e_lfanew);
	dir = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
	if (!dir->VirtualAddress)
		return;
	for (imp = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir->VirtualAddress); imp->Name; imp++) {
		IMAGE_THUNK_DATA *thunk, *orig;
		if (_stricmp((char *)(base + imp->Name), "kernel32.dll") != 0)
			continue;
		thunk = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk);
		orig = (IMAGE_THUNK_DATA *)(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
		for (; orig->u1.AddressOfData; orig++, thunk++) {
			IMAGE_IMPORT_BY_NAME *ibn;
			void *repl = NULL;
			DWORD old;
			if (orig->u1.Ordinal & IMAGE_ORDINAL_FLAG)
				continue;
			ibn = (IMAGE_IMPORT_BY_NAME *)(base + orig->u1.AddressOfData);
			if (strcmp((char *)ibn->Name, "CreateMutexA") == 0)
				repl = (void *)my_CreateMutexA;
			else if (strcmp((char *)ibn->Name, "CreateMutexW") == 0)
				repl = (void *)my_CreateMutexW;
			else if (strcmp((char *)ibn->Name, "GetProcAddress") == 0)
				repl = (void *)my_GetProcAddress;
			if (!repl)
				continue;
			if (VirtualProtect(&thunk->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) {
				thunk->u1.Function = (DWORD_PTR)repl;
				VirtualProtect(&thunk->u1.Function, sizeof(void *), old, &old);
			}
		}
	}
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
	(void)inst; (void)reserved;
	if (reason == DLL_PROCESS_ATTACH) {
		HMODULE k32 = GetModuleHandleA("kernel32.dll");
		real_GetProcAddress = (void *)GetProcAddress(k32, "GetProcAddress");
		real_CreateMutexA = (void *)GetProcAddress(k32, "CreateMutexA");
		real_CreateMutexW = (void *)GetProcAddress(k32, "CreateMutexW");
		patch_module(GetModuleHandleA(NULL));
		patch_module(GetModuleHandleA("Core.dll"));
		patch_module(GetModuleHandleA("Engine.dll"));
	}
	return TRUE;
}
