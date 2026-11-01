/* Test-only proxy for dinput8.dll (the sandbox copy of the game, never the owner's install).
 * It forwards DirectInput to the system's dinput8 and keeps the game from taking over the PC while it is tested:
 *  - game windows are created without activation (WS_EX_NOACTIVATE) and, when SHREK2_POS="x,y" is set, on that spot
 *    (the second monitor), so a test window is visible but never gets the keyboard or the mouse;
 *  - the game is told that it is the foreground window anyway, so it does not go to sleep (UE2 sleeps when inactive);
 *  - the game cannot move, clip or capture the mouse cursor.
 * The hooks are 5-byte hot patches in user32, the same for every module of the process. Log: quiet.log next to Game.exe. */
#include <windows.h>
#define DIRECTINPUT_VERSION 0x0800
#include <stdio.h>
#include <string.h>

static FILE *lg;
static void L(const char *f, const char *a)
{
	if (!lg) lg = fopen("quiet.log", "a");
	if (lg) { fprintf(lg, f, a); fputc('\n', lg); fflush(lg); }
}

/* ---- the real dinput8 ---- */
static HMODULE real;
static FARPROC rf(const char *n)
{
	if (!real) {
		char p[MAX_PATH];
		GetSystemDirectoryA(p, MAX_PATH);
		strcat(p, "\\dinput8.dll");
		real = LoadLibraryA(p);
	}
	return real ? GetProcAddress(real, n) : NULL;
}
static int quiet;
static void patch_vtbl(void **vt, int idx, void *fn)
{
	DWORD old;
	if (vt[idx] == fn) return;
	if (VirtualProtect(&vt[idx], sizeof(void *), PAGE_READWRITE, &old)) { vt[idx] = fn; VirtualProtect(&vt[idx], sizeof(void *), old, &old); }
}
/* tests: every DirectInput device (keyboard, mouse, pad) reads as "nothing pressed, nothing moved", so the person's own
 * mouse and keyboard never reach the game window */
static HRESULT WINAPI h_GetDeviceState(void *self, DWORD cb, LPVOID data)
{
	(void)self;
	{
		static int logged;
		if (logged < 6 && cb != 256) {
			char b[96];
			logged++;
			snprintf(b, sizeof b, "GetDeviceState cb=%lu", (unsigned long)cb);
			L("%s", b);
		}
	}
	if (data)
		memset(data, 0, cb);
	/* tests: a keyboard state (256 bytes) with the keys named in the file keys.req (one scan code per byte) held down */
	if (data && cb == 256) {
		FILE *f = fopen("keys.req", "rb");
		if (f) {
			unsigned char b[16];
			size_t n = fread(b, 1, sizeof b, f), i;
			fclose(f);
			for (i = 0; i < n; i++)
				((unsigned char *)data)[b[i]] = 0x80;
		}
	}
	return S_OK;
}
/* the keyboard device (made with GUID_SysKeyboard) also gives the buffered events of keys.req: a press when a key appears in the file, a release when it goes */
static void *g_kbd;
static unsigned char g_prevkeys[256];
static void read_keys(unsigned char *cur)
{
	FILE *f = fopen("keys.req", "rb");
	memset(cur, 0, 256);
	if (f) {
		unsigned char b[16];
		size_t n = fread(b, 1, sizeof b, f), i;
		fclose(f);
		for (i = 0; i < n; i++)
			cur[b[i]] = 0x80;
	}
}
static HRESULT WINAPI h_GetDeviceData(void *self, DWORD cb, void *data, LPDWORD n, DWORD fl)
{
	DWORD room = n ? *n : 0, out = 0;
	{
		static int logged;
		if (logged < 6) {
			char b[96];
			logged++;
			snprintf(b, sizeof b, "GetDeviceData self=%p kbd=%p cb=%lu room=%lu flags=%lu", self, g_kbd, (unsigned long)cb, (unsigned long)room, (unsigned long)fl);
			L("%s", b);
		}
	}
	if (n)
		*n = 0;
	if (self == g_kbd && (cb == 16 || cb == 20) && data && n) {
		unsigned char cur[256];
		int i;
		DWORD *ev = (DWORD *)data;
		DWORD stride = cb / 4;
		read_keys(cur);
		for (i = 0; i < 256 && out < room; i++) {
			if (cur[i] != g_prevkeys[i]) {
				ev[out * stride + 0] = (DWORD)i;
				ev[out * stride + 1] = cur[i];
				ev[out * stride + 2] = GetTickCount();
				ev[out * stride + 3] = (DWORD)(out + 1);
				out++;
				if (!(fl & 1))
					g_prevkeys[i] = cur[i];
			}
		}
		*n = out;
	}
	return S_OK;
}
static HRESULT (WINAPI *o_CreateDevice)(void *, REFGUID, void **, LPUNKNOWN);
static HRESULT WINAPI h_CreateDevice(void *self, REFGUID g, void **dev, LPUNKNOWN u)
{
	HRESULT r = o_CreateDevice(self, g, dev, u);
	if (SUCCEEDED(r) && dev && *dev) {
		void **vt = *(void ***)*dev;
		{
			static const GUID kb = {0x6F1D2B61, 0xD5A0, 0x11CF, {0xBF, 0xC7, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00}};
			if (memcmp(g, &kb, sizeof kb) == 0)
				g_kbd = *dev;
		}
		patch_vtbl(vt, 9, (void *)h_GetDeviceState);
		patch_vtbl(vt, 10, (void *)h_GetDeviceData);
	}
	return r;
}
HRESULT WINAPI q_DirectInput8Create(HINSTANCE h, DWORD v, REFIID r, LPVOID *o, LPUNKNOWN u)
{
	HRESULT (WINAPI *f)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN) = (void *)rf("DirectInput8Create");
	HRESULT hr = f ? f(h, v, r, o, u) : E_FAIL;
	if (quiet && SUCCEEDED(hr) && o && *o) {
		void **vt = *(void ***)*o;
		if (!o_CreateDevice) o_CreateDevice = (void *)vt[3];
		patch_vtbl(vt, 3, (void *)h_CreateDevice);
	}
	return hr;
}
HRESULT WINAPI q_DllCanUnloadNow(void) { return S_FALSE; }
HRESULT WINAPI q_DllGetClassObject(REFCLSID c, REFIID i, LPVOID *o)
{ HRESULT (WINAPI *f)(REFCLSID, REFIID, LPVOID *) = (void *)rf("DllGetClassObject"); return f ? f(c, i, o) : E_FAIL; }
HRESULT WINAPI q_DllRegisterServer(void) { return S_OK; }
HRESULT WINAPI q_DllUnregisterServer(void) { return S_OK; }

/* ---- the game window ---- */
static HWND cache;
static BOOL CALLBACK findw(HWND h, LPARAM l)
{
	DWORD pid; char t[64];
	GetWindowThreadProcessId(h, &pid);
	if (pid == GetCurrentProcessId() && IsWindowVisible(h)) {
		GetWindowTextA(h, t, sizeof t);
		if (strcmp(t, "Shrek 2") == 0) { *(HWND *)l = h; return FALSE; }
	}
	return TRUE;
}
static HWND gamewin(void)
{
	if (cache && IsWindow(cache)) return cache;
	cache = NULL;
	EnumWindows(findw, (LPARAM)&cache);
	return cache;
}

static int posx = CW_USEDEFAULT, posy = CW_USEDEFAULT, haspos;

/* ---- the hooks ---- */
static HWND (WINAPI *o_CreateWindowExA)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
static HWND (WINAPI *o_CreateWindowExW)(DWORD, LPCWSTR, LPCWSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
static HWND WINAPI h_CreateWindowExA(DWORD ex, LPCSTR c, LPCSTR n, DWORD st, int x, int y, int w, int h, HWND par, HMENU m, HINSTANCE i, LPVOID p)
{
	if (!par && !(st & WS_CHILD)) { ex |= WS_EX_NOACTIVATE; if (haspos) { x = posx; y = posy; } }
	return o_CreateWindowExA(ex, c, n, st, x, y, w, h, par, m, i, p);
}
static HWND WINAPI h_CreateWindowExW(DWORD ex, LPCWSTR c, LPCWSTR n, DWORD st, int x, int y, int w, int h, HWND par, HMENU m, HINSTANCE i, LPVOID p)
{
	if (!par && !(st & WS_CHILD)) { ex |= WS_EX_NOACTIVATE; if (haspos) { x = posx; y = posy; } }
	return o_CreateWindowExW(ex, c, n, st, x, y, w, h, par, m, i, p);
}
static HWND WINAPI h_GetForegroundWindow(void) { HWND g = gamewin(); return g ? g : NULL; }
static HWND WINAPI h_GetFocus(void) { return gamewin(); }
static HWND WINAPI h_GetActiveWindow(void) { return gamewin(); }
static BOOL WINAPI h_SetForegroundWindow(HWND h) { (void)h; return TRUE; }
static HWND WINAPI h_SetFocus(HWND h) { (void)h; return gamewin(); }
static HWND WINAPI h_SetActiveWindow(HWND h) { (void)h; return gamewin(); }
static BOOL WINAPI h_BringWindowToTop(HWND h) { (void)h; return TRUE; }
static BOOL WINAPI h_SetCursorPos(int x, int y) { (void)x; (void)y; return TRUE; }
static BOOL WINAPI h_ClipCursor(const RECT *r) { (void)r; return TRUE; }
static HWND WINAPI h_SetCapture(HWND h) { (void)h; return NULL; }
static BOOL WINAPI h_GetCursorPos(LPPOINT p)
{
	RECT r; HWND g = gamewin();
	if (!p) return FALSE;
	if (g && GetWindowRect(g, &r)) { p->x = (r.left + r.right) / 2; p->y = (r.top + r.bottom) / 2; return TRUE; }
	p->x = p->y = 0; return TRUE;
}

/* 5-byte hot patch: [p-5] jmp hook ; [p] short jmp back to it. Needs the usual "mov edi,edi" and free padding. */
static void hook(const char *fn, void *hk, void **orig)
{
	BYTE *p = (BYTE *)GetProcAddress(GetModuleHandleA("user32.dll"), fn);
	DWORD old; int i;
	if (!p) { L("no export %s", fn); return; }
	if (p[0] != 0x8B || p[1] != 0xFF) {
		/* a thunk or a short function: the replacement never calls the original, so the first 5 bytes are overwritten */
		if (orig || !VirtualProtect(p, 5, PAGE_EXECUTE_READWRITE, &old)) { L("not patchable: %s", fn); return; }
		p[0] = 0xE9; *(DWORD *)(p + 1) = (DWORD)hk - (DWORD)p - 5;
		VirtualProtect(p, 5, old, &old);
		L("hooked (overwritten) %s", fn);
		return;
	}
	for (i = 1; i <= 5; i++) if (p[-i] != 0x90 && p[-i] != 0xCC) { L("no padding: %s", fn); return; }
	if (!VirtualProtect(p - 5, 7, PAGE_EXECUTE_READWRITE, &old)) { L("protect failed: %s", fn); return; }
	if (orig) *orig = p + 2;
	p[-5] = 0xE9; *(DWORD *)(p - 4) = (DWORD)hk - (DWORD)p;
	p[0] = 0xEB; p[1] = 0xF9;
	VirtualProtect(p - 5, 7, old, &old);
	L("hooked %s", fn);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID res)
{
	(void)inst; (void)res;
	if (reason == DLL_PROCESS_ATTACH) {
		char pos[64];
		if (GetEnvironmentVariableA("SHREK2_QUIET", pos, sizeof pos) == 0) return TRUE;   /* only when asked for */
		quiet = 1;
		LoadLibraryA("user32.dll");
		if (GetEnvironmentVariableA("SHREK2_POS", pos, sizeof pos) > 0 && sscanf(pos, "%d,%d", &posx, &posy) == 2) haspos = 1;
		hook("CreateWindowExA", h_CreateWindowExA, (void **)&o_CreateWindowExA);
		hook("CreateWindowExW", h_CreateWindowExW, (void **)&o_CreateWindowExW);
		hook("GetForegroundWindow", h_GetForegroundWindow, NULL);
		hook("GetFocus", h_GetFocus, NULL);
		hook("GetActiveWindow", h_GetActiveWindow, NULL);
		hook("SetForegroundWindow", h_SetForegroundWindow, NULL);
		hook("SetFocus", h_SetFocus, NULL);
		hook("SetActiveWindow", h_SetActiveWindow, NULL);
		hook("BringWindowToTop", h_BringWindowToTop, NULL);
		hook("SetCursorPos", h_SetCursorPos, NULL);
		hook("ClipCursor", h_ClipCursor, NULL);
		hook("SetCapture", h_SetCapture, NULL);
		hook("GetCursorPos", h_GetCursorPos, NULL);
	}
	return TRUE;
}
