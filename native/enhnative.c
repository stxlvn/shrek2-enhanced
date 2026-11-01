/* Test-only proxy for msvcr70.dll: forwards everything to msvcr70_real.dll and gives
 * every process its own "UnrealIsRunning" mutex so two copies of the sandbox game can run.
 * Only used in the sandbox copy, never in the owner's install. */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

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


/* ---- Native layer: natives that the game's scripts can call -------------------------------------------------
 * The engine calls a native function through GNatives[index]: void (UObject *self, FFrame &stack, void *result).
 * Index 3500 and up are free in the retail game. A script declares  native(3500) final function int EnhNativeVersion();  */
#define ENH_NATIVE_VERSION 1

typedef struct { void *vtbl; void *node; void *object; unsigned char *code; unsigned char *locals; } FFrame;
typedef void (__attribute__((thiscall)) *NativeFn)(void *self, FFrame *stack, void *result);

static void enh_log(const char *fmt, ...)
{
	FILE *f = fopen("enhnative.log", "a");
	va_list ap;
	if (!f)
		return;
	va_start(ap, fmt);
	vfprintf(f, fmt, ap);
	va_end(ap);
	fputc(10, f);
	fclose(f);
}

static void __attribute__((thiscall)) nat_version(void *self, FFrame *stack, void *result)
{
	(void)self;
	stack->code++;                                    /* EX_EndFunctionParms */
	*(int *)result = ENH_NATIVE_VERSION;
}

static void register_native(void **table, int index, NativeFn fn, void *undefined)
{
	if (table[index] != undefined && table[index] != NULL) {
		enh_log("native %d is taken (%p), not registered", index, table[index]);
		return;
	}
	table[index] = (void *)fn;
	enh_log("native %d registered", index);
}


/* ---- Hooks ------------------------------------------------------------------------------------------------
 * Engine.dll is linked incrementally: every exported function is a 5-byte "jmp rel32" thunk, and the callers (also inside Engine.dll) reach
 * the function through it. A hook replaces the rel32 of the thunk and calls the old target. */
static void *hook_thunk(const char *module, const char *symbol, void *hook, void **original)
{
	HMODULE m = GetModuleHandleA(module);
	unsigned char *t;
	DWORD old;
	int rel;
	if (!m)
		return NULL;
	t = (unsigned char *)GetProcAddress(m, symbol);
	if (!t || t[0] != 0xE9) {
		enh_log("hook %s: no jmp thunk (%p)", symbol, (void *)t);
		return NULL;
	}
	memcpy(&rel, t + 1, 4);
	*original = t + 5 + rel;
	rel = (int)((unsigned char *)hook - (t + 5));
	if (!VirtualProtect(t, 5, PAGE_EXECUTE_READWRITE, &old))
		return NULL;
	memcpy(t + 1, &rel, 4);
	VirtualProtect(t, 5, old, &old);
	FlushInstructionCache(GetCurrentProcess(), t, 5);
	enh_log("hook %s: thunk %p, original %p", symbol, (void *)t, *original);
	return t;
}

static volatile int g_animSync;
static int is_hero_name(const unsigned short *n);
typedef void (__attribute__((thiscall)) *ThisVoid)(void *);
typedef float (__attribute__((thiscall)) *GetRateFn)(void *, int);
typedef const unsigned short *(__attribute__((thiscall)) *GetNameFn)(void *);
static GetNameFn fn_GetName;
static ThisVoid orig_PlayReplicatedAnim;
static GetRateFn fn_GetAnimRateOnChannel;

/* AActor::PlayReplicatedAnim: SimAnim sits at +0x340 (name), +0x344 bit 0 (loop), +0x348 rate, +0x349 frame, +0x34a tween (bytes); the mesh instance at +0xdc. */
static void __attribute__((thiscall)) hook_PlayReplicatedAnim(void *self)
{
	static int n;
	unsigned char *a = (unsigned char *)self;
	void *mesh;
	if (g_animSync && fn_GetName && is_hero_name(fn_GetName(self)))
		return;
	orig_PlayReplicatedAnim(self);
	mesh = *(void **)(a + 0xdc);
	if (mesh && fn_GetAnimRateOnChannel && fn_GetName && n < 80) {
		const unsigned short *nm = fn_GetName(self);
		if (nm && nm[0] == 'S' && nm[1] == 'h' && nm[2] == 'r') {
			n++;
			enh_log("PlayReplicatedAnim %ls: name %d decoded rate %.3f frame %.3f tween %d loop %d",
				(const wchar_t *)nm, *(int *)(a + 0x340), ((float)a[0x348] - 124.0f) * 0.032258063f,
				((float)a[0x349] - 127.0f) * 0.007874016f, a[0x34a], (a[0x344] & 1));
		}
	}
}

typedef void (__attribute__((thiscall)) *ReplicateAnimFn)(void *, int, int, float, float, float, float, int);
static ReplicateAnimFn orig_ReplicateAnim;

/* AActor::ReplicateAnim(int channel, FName seq, float, float, float, float, int loop), called by the engine on the machine that plays the animation. */
static void __attribute__((thiscall)) hook_ReplicateAnim(void *self, int ch, int name, float f4, float f5, float f6, float f7, int loop)
{
	static int n;
	if (n < 80 && ch == 0 && fn_GetName) {
		const unsigned short *nm = fn_GetName(self);
		if (nm && nm[0] == 'S' && nm[1] == 'h' && nm[2] == 'r') {
			n++;
			enh_log("ReplicateAnim %ls: name %d  f4 %.3f f5 %.3f f6 %.3f f7 %.3f loop %d", (const wchar_t *)nm, name, f4, f5, f6, f7, loop);
		}
	}
	orig_ReplicateAnim(self, ch, name, f4, f5, f6, f7, loop);
}

/* ---- Natives for the animation sync (EnhancedAnimSync in the mod's scripts) -----------------------------------
 * 3501 EnhAnimExtra(Actor A, int Channel): what the scripts cannot read: bit 0 = the channel loops, bits 1..8 = its blend alpha (0..255).
 * 3502 EnhAnimSyncOn(int On): while on, the engine's own one-channel animation replication is skipped for the hero pawns (the sync carries all channels). */
typedef void (__attribute__((thiscall)) *StepFn)(FFrame *, void *, void *);
typedef int (__attribute__((thiscall)) *IsAFn)(void *, void *);
typedef int (__attribute__((thiscall)) *IntChFn)(void *, int);
typedef float (__attribute__((thiscall)) *FloatChFn)(void *, int);
static StepFn fn_Step;
static IsAFn fn_IsA;
static IntChFn fn_IsAnimLooping, fn_GetAnimChannelCount0;
static FloatChFn fn_GetBlendAlpha;
static void *pSkelClass;
static volatile int g_animSync;

static void __attribute__((thiscall)) nat_animextra(void *self, FFrame *stack, void *result)
{
	void *actor = NULL;
	int ch = 0, r = 0;
	(void)self;
	fn_Step(stack, stack->object, &actor);
	fn_Step(stack, stack->object, &ch);
	stack->code++;
	if (actor && ch >= 0 && ch < 40 && fn_IsA && pSkelClass && fn_IsAnimLooping && fn_GetBlendAlpha) {
		void *mesh = *(void **)((unsigned char *)actor + 0xdc);
		if (mesh && fn_IsA(mesh, pSkelClass)) {
			float a = fn_GetBlendAlpha(mesh, ch);
			int ia = (int)(a * 255.0f + 0.5f);
			if (ia < 0) ia = 0;
			if (ia > 255) ia = 255;
			r = (fn_IsAnimLooping(mesh, ch) ? 1 : 0) | (ia << 1);
		}
	}
	*(int *)result = r;
}

static void __attribute__((thiscall)) nat_animsyncon(void *self, FFrame *stack, void *result)
{
	int on = 0;
	(void)self; (void)result;
	fn_Step(stack, stack->object, &on);
	stack->code++;
	g_animSync = on;
	enh_log("animation sync %s", on ? "on" : "off");
}

static int is_hero_name(const unsigned short *n)
{
	if (!n)
		return 0;
	if (n[0] == 'S' && n[1] == 'h' && n[2] == 'r' && n[3] == 'e' && n[4] == 'k' && n[5] != 'S')   /* Shrek0, not ShrekSwitch0 */
		return 1;
	return n[0] == 'E' && n[1] == 'n' && n[2] == 'h' && n[3] == 'a' && n[4] == 'n' && n[5] == 'c' && n[6] == 'e' && n[7] == 'd' && n[8] == 'S' && n[9] == 'h';
}

/* ---- Draw offsets of the guests' pawns on the host ----------------------------------------------------------
 * PrePivot is replicated, so the host cannot smooth a guest's drawn position by writing it every frame (the guests would see the shift and the
 * link would carry it). The script gives the wanted shift with 3503 EnhDrawOffset(slot, Actor, X, Y) and resets PrePivot at the start of every
 * tick (before the replication); this hook adds the shift to PrePivot once per frame just before the host's view is worked out, i.e. after the
 * replication and before the scene is drawn. 3504 EnhPrePivotCalib(Actor) finds where PrePivot sits in the actor: the script writes 123/456/789
 * into it first and the memory of the actor is searched for those three floats. */
#define MAXOFF 8
static struct { void *actor; float ox, oy; int applied; } g_off[MAXOFF];
static int g_pivotOfs = -1;

static void __attribute__((thiscall)) nat_drawoffset(void *self, FFrame *stack, void *result)
{
	int slot = 0;
	void *actor = NULL;
	float x = 0.0f, y = 0.0f;
	(void)self; (void)result;
	fn_Step(stack, stack->object, &slot);
	fn_Step(stack, stack->object, &actor);
	fn_Step(stack, stack->object, &x);
	fn_Step(stack, stack->object, &y);
	stack->code++;
	if (slot >= 0 && slot < MAXOFF) {
		g_off[slot].actor = actor;
		g_off[slot].ox = x;
		g_off[slot].oy = y;
		g_off[slot].applied = 0;
	}
}

static void __attribute__((thiscall)) nat_calib(void *self, FFrame *stack, void *result)
{
	void *actor = NULL;
	int off;
	(void)self;
	fn_Step(stack, stack->object, &actor);
	stack->code++;
	*(int *)result = 0;
	if (!actor)
		return;
	for (off = 0x100; off < 0x700; off += 4) {
		float *f = (float *)((unsigned char *)actor + off);
		if (f[0] == 123.0f && f[1] == 456.0f && f[2] == 789.0f) {
			g_pivotOfs = off;
			*(int *)result = off;
			enh_log("PrePivot found at +0x%x", off);
			return;
		}
	}
	enh_log("PrePivot not found");
}

typedef void (__attribute__((thiscall)) *CalcViewFn)(void *, void *, void *, void *);
static CalcViewFn orig_PlayerCalcView;

static void __attribute__((thiscall)) hook_PlayerCalcView(void *self, void *a, void *b, void *c)
{
	static int n;
	int i;
	if (g_pivotOfs > 0) {
		for (i = 0; i < MAXOFF; i++) {
			if (g_off[i].actor && !g_off[i].applied) {
				float *pv = (float *)((unsigned char *)g_off[i].actor + g_pivotOfs);
				pv[0] += g_off[i].ox;
				pv[1] += g_off[i].oy;
				g_off[i].applied = 1;
				if (n < 10) {
					n++;
					enh_log("draw offset slot %d: %.1f %.1f -> PrePivot %.1f %.1f %.1f", i, g_off[i].ox, g_off[i].oy, pv[0], pv[1], pv[2]);
				}
			}
		}
	}
	orig_PlayerCalcView(self, a, b, c);
}

/* ---- Hardware probe and first-run tuning ----------------------------------------------------------------------
 * The 2004 engine knows nothing newer than its tables: it prints "Unknown processor" for a modern CPU, caps the memory it sees at 4 GB, keeps
 * the anisotropic filtering at 1, the resource cache at 32 MB, the refresh rate at 60 Hz and the resolution at 1920x1080 whatever the machine is.
 * The probe reads the real values (CPUID, GlobalMemoryStatusEx, DXGI, the display mode) and writes them to enhnative.log; the scripts read them
 * through 3510 EnhHwInfo(what). The tuning changes Game.ini only where the value still equals the stock one (so a choice of the player is never
 * overwritten), takes effect from the next start, and is switched off by  AutoTune=False  anywhere in Game.ini. */
#include <intrin.h>
#include <stdlib.h>
static int g_noPrefetch;     /* Prefetch=False in Game.ini */
static int g_msaa;           /* multisample count to ask Direct3D for (MSAA=N in Game.ini) */
static int g_maxfps;         /* frame limiter: MaxFPS=N in Game.ini (0 = none); the game's physics was made for about 60 steps a second */
typedef struct {
	char cpu[64];
	int logical, ramMB, vramMB, monW, monH, monHz, vendor;
	char gpu[128];
} HwInfo;
static HwInfo g_hw;

static void hw_probe_cpu(void)
{
	int r[4], i;
	unsigned int n;
	SYSTEM_INFO si;
	memset(g_hw.cpu, 0, sizeof g_hw.cpu);
	__cpuid(r, 0x80000000);
	n = (unsigned int)r[0];
	if (n >= 0x80000004) {
		for (i = 0; i < 3; i++) {
			__cpuid(r, 0x80000002 + i);
			memcpy(g_hw.cpu + i * 16, r, 16);
		}
	}
	GetSystemInfo(&si);
	g_hw.logical = (int)si.dwNumberOfProcessors;
}

typedef struct { unsigned long Data1; unsigned short Data2, Data3; unsigned char Data4[8]; } GuidRaw;
typedef struct {
	wchar_t Description[128];
	unsigned int VendorId, DeviceId, SubSysId, Revision;
	size_t DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
	unsigned int LuidLow;
	int LuidHigh;
	unsigned int Flags;
} DxgiDesc1;

static void hw_probe_gpu(void)
{
	typedef long (__stdcall *CreateFactoryFn)(const GuidRaw *, void **);
	HMODULE dx = LoadLibraryA("dxgi.dll");
	CreateFactoryFn create;
	GuidRaw iid = { 0x770aae78, 0xf26f, 0x4dba, { 0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87 } };
	void *factory = NULL, *adapter = NULL;
	size_t best = 0;
	unsigned int i;
	g_hw.gpu[0] = 0;
	if (!dx) {
		enh_log("dxgi.dll cannot be loaded");
		return;
	}
	create = (CreateFactoryFn)GetProcAddress(dx, "CreateDXGIFactory1");
	if (!create) {
		enh_log("CreateDXGIFactory1 not found");
		return;
	}
	{
		long hr = create(&iid, &factory);
		if (hr < 0 || !factory) {
			enh_log("CreateDXGIFactory1 failed: 0x%lx", hr);
			return;
		}
	}
	for (i = 0; i < 8; i++) {
		void **vt = *(void ***)factory;
		long (__stdcall *enumAdapters1)(void *, unsigned int, void **) = (long (__stdcall *)(void *, unsigned int, void **))vt[12];
		long (__stdcall *getDesc1)(void *, DxgiDesc1 *);
		void (__stdcall *release)(void *);
		DxgiDesc1 d;
		adapter = NULL;
		if (enumAdapters1(factory, i, &adapter) < 0 || !adapter)
			break;
		vt = *(void ***)adapter;
		getDesc1 = (long (__stdcall *)(void *, DxgiDesc1 *))vt[10];
		release = (void (__stdcall *)(void *))vt[2];
		memset(&d, 0, sizeof d);
		/* the adapter with the most dedicated memory (the discrete card on a laptop); software adapters (flag 2) are skipped */
		if (getDesc1(adapter, &d) >= 0 && !(d.Flags & 2) && (g_hw.gpu[0] == 0 || d.DedicatedVideoMemory > best)) {
			best = d.DedicatedVideoMemory;
			WideCharToMultiByte(CP_ACP, 0, d.Description, -1, g_hw.gpu, (int)sizeof g_hw.gpu - 1, NULL, NULL);
			g_hw.vendor = (int)d.VendorId;
			g_hw.vramMB = (int)(d.DedicatedVideoMemory / (1024 * 1024));
		}
		release(adapter);
	}
	(*(void (__stdcall **)(void *))(*(void ***)factory + 2))(factory);
}

/* The vendor from the primary display adapter's PCI id (no DXGI: this runs inside DllMain, before the engine reads Game.ini). */
static void hw_probe_vendor(void)
{
	DISPLAY_DEVICEA dd;
	int i;
	for (i = 0; i < 8; i++) {
		memset(&dd, 0, sizeof dd);
		dd.cb = sizeof dd;
		if (!EnumDisplayDevicesA(NULL, (DWORD)i, &dd, 0))
			break;
		if ((dd.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) && (dd.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) {
			const char *v = strstr(dd.DeviceID, "VEN_");
			if (v)
				g_hw.vendor = (int)strtoul(v + 4, NULL, 16);
			break;
		}
	}
}

/* Quick part (inside DllMain): CPU, memory, display, vendor. The GPU name and video memory come later from DXGI, in a thread. */
static void hw_probe_quick(void)
{
	MEMORYSTATUSEX ms;
	DEVMODEA dm;
	hw_probe_cpu();
	memset(&ms, 0, sizeof ms);
	ms.dwLength = sizeof ms;
	if (GlobalMemoryStatusEx(&ms))
		g_hw.ramMB = (int)(ms.ullTotalPhys / (1024 * 1024));
	memset(&dm, 0, sizeof dm);
	dm.dmSize = sizeof dm;
	if (EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &dm)) {
		g_hw.monW = (int)dm.dmPelsWidth;
		g_hw.monH = (int)dm.dmPelsHeight;
		g_hw.monHz = (int)dm.dmDisplayFrequency;
	}
	hw_probe_vendor();
}

static void hw_probe(void)
{
	MEMORYSTATUSEX ms;
	DEVMODEA dm;
	hw_probe_cpu();
	memset(&ms, 0, sizeof ms);
	ms.dwLength = sizeof ms;
	if (GlobalMemoryStatusEx(&ms))
		g_hw.ramMB = (int)(ms.ullTotalPhys / (1024 * 1024));
	hw_probe_gpu();
	memset(&dm, 0, sizeof dm);
	dm.dmSize = sizeof dm;
	if (EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &dm)) {
		g_hw.monW = (int)dm.dmPelsWidth;
		g_hw.monH = (int)dm.dmPelsHeight;
		g_hw.monHz = (int)dm.dmDisplayFrequency;
	}
	enh_log("hardware: cpu '%s', %d logical processors, %d MB RAM, gpu '%s' (vendor 0x%x) %d MB video memory, display %dx%d at %d Hz",
		g_hw.cpu, g_hw.logical, g_hw.ramMB, g_hw.gpu, g_hw.vendor, g_hw.vramMB, g_hw.monW, g_hw.monH, g_hw.monHz);
}

static void __attribute__((thiscall)) nat_hwinfo(void *self, FFrame *stack, void *result)
{
	int what = 0, v = 0;
	(void)self;
	fn_Step(stack, stack->object, &what);
	stack->code++;
	switch (what) {
	case 0: v = g_hw.logical; break;
	case 1: v = g_hw.ramMB; break;
	case 2: v = g_hw.vramMB; break;
	case 3: v = g_hw.monW; break;
	case 4: v = g_hw.monH; break;
	case 5: v = g_hw.monHz; break;
	case 6: v = g_hw.vendor; break;
	}
	*(int *)result = v;
}

/* Game.ini: replace the value of Key in [Section] when it is one of the stock values (a '|' list). Returns 1 when the text changed. */
static int ini_tune(char **buf, size_t *len, const char *section, const char *key, const char *stock, const char *value)
{
	char *b = *buf, *p, *end = *buf + *len;
	char head[160];
	size_t kl = strlen(key);
	snprintf(head, sizeof head, "[%s]", section);
	p = strstr(b, head);
	if (!p)
		return 0;
	p += strlen(head);
	while (p < end && *p != '[') {
		char *line = p, *eol = line;
		while (eol < end && *eol != '\r' && *eol != '\n')
			eol++;
		if ((size_t)(eol - line) > kl && !_strnicmp(line, key, kl) && line[kl] == '=') {
			char cur[64];
			size_t cl = (size_t)(eol - (line + kl + 1));
			const char *s = stock;
			int ok = 0;
			if (cl >= sizeof cur)
				return 0;
			memcpy(cur, line + kl + 1, cl);
			cur[cl] = 0;
			while (*s) {
				size_t sl = strcspn(s, "|");
				if (sl == cl && !strncmp(s, cur, sl))
					ok = 1;
				s += sl;
				if (*s == '|')
					s++;
			}
			if (!ok || !strcmp(cur, value))
				return 0;
			{
				size_t vl = strlen(value), tail = (size_t)(end - eol), head_len = (size_t)(line + kl + 1 - b);
				char *nb = (char *)malloc(*len + vl + 1);
				if (!nb)
					return 0;
				memcpy(nb, b, head_len);
				memcpy(nb + head_len, value, vl);
				memcpy(nb + head_len + vl, eol, tail);
				*len = head_len + vl + tail;
				nb[*len] = 0;
				free(b);
				*buf = nb;
				enh_log("Game.ini [%s] %s: %s -> %s", section, key, cur, value);
				return 1;
			}
		}
		p = eol;
		while (p < end && (*p == '\r' || *p == '\n'))
			p++;
	}
	return 0;
}

static void hw_tune(void)
{
	char dir[MAX_PATH], path[MAX_PATH], bak[MAX_PATH], val[32];
	FILE *f;
	long sz;
	char *buf;
	size_t len;
	int changed = 0, af, cache;
	DWORD n = GetEnvironmentVariableA("SHREK2_DOCS", dir, MAX_PATH);
	if (n == 0 || n >= MAX_PATH) {
		HMODULE sh = LoadLibraryA("shell32.dll");
		HRESULT (WINAPI *get)(HWND, int, HANDLE, DWORD, LPSTR) = sh ? (void *)GetProcAddress(sh, "SHGetFolderPathA") : NULL;
		if (!get || get(NULL, 5, NULL, 0, dir) != 0)
			return;
	}
	snprintf(path, sizeof path, "%s\\Shrek 2\\Game.ini", dir);
	f = fopen(path, "rb");
	if (!f)
		return;
	fseek(f, 0, SEEK_END);
	sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	buf = (char *)malloc((size_t)sz + 1);
	if (!buf || fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
		fclose(f);
		free(buf);
		return;
	}
	fclose(f);
	buf[sz] = 0;
	len = (size_t)sz;
	if (strstr(buf, "Prefetch=False"))
		g_noPrefetch = 1;
	{
		const char *f = strstr(buf, "MaxFPS=");
		g_maxfps = f ? atoi(f + 7) : 0;
	}
	{
		const char *q = strstr(buf, "MSAA=");
		if (q)
			g_msaa = atoi(q + 5);
		else
			g_msaa = (g_hw.vendor == 0x10de || g_hw.vendor == 0x1002) ? 4 : 0;
	}
	if (strstr(buf, "AutoTune=False")) {
		free(buf);
		return;
	}
	/* the stock Settings page can leave the software renderer in the ini (its renderer list); on a machine with a graphics adapter that makes the
	 * game black and slow, so Direct3D is put back */
	if (g_hw.vendor != 0)
		changed += ini_tune(&buf, &len, "Engine.Engine", "RenderDevice", "PixoDrv.PixoRenderDevice", "D3DDrv.D3DRenderDevice");
	af = (g_hw.vendor == 0x10de || g_hw.vendor == 0x1002) ? 16 : 4;
	snprintf(val, sizeof val, "%d", af);
	changed += ini_tune(&buf, &len, "D3DDrv.D3DRenderDevice", "LevelOfAnisotropy", "1", val);
	if (g_hw.monHz > 60) {
		snprintf(val, sizeof val, "%d", g_hw.monHz);
		changed += ini_tune(&buf, &len, "D3DDrv.D3DRenderDevice", "DesiredRefreshRate", "60", val);
	}
	if (g_hw.monW > 1920 || g_hw.monH > 1080) {
		snprintf(val, sizeof val, "%d", g_hw.monW);
		changed += ini_tune(&buf, &len, "D3DDrv.D3DRenderDevice", "MaxResWidth", "1920", val);
		snprintf(val, sizeof val, "%d", g_hw.monH);
		changed += ini_tune(&buf, &len, "D3DDrv.D3DRenderDevice", "MaxResHeight", "1080", val);
	}
	cache = g_hw.ramMB >= 16000 ? 256 : (g_hw.ramMB >= 8000 ? 128 : 32);
	snprintf(val, sizeof val, "%d", cache);
	changed += ini_tune(&buf, &len, "Engine.GameEngine", "CacheSizeMegs", "32", val);
	/* the stock net rates (10000 bytes a second for an Internet player, 20000 for the host's side of a client) sit close to the peaks of the mod's world sync */
	changed += ini_tune(&buf, &len, "Engine.Player", "ConfiguredInternetSpeed", "10000", "25000");
	changed += ini_tune(&buf, &len, "Engine.Player", "ConfiguredLanSpeed", "20000", "50000");
	changed += ini_tune(&buf, &len, "IpDrv.TcpNetDriver", "MaxClientRate", "20000", "50000");
	if (changed) {
		snprintf(bak, sizeof bak, "%s.before-enhanced-tune", path);
		if (GetFileAttributesA(bak) == INVALID_FILE_ATTRIBUTES)
			CopyFileA(path, bak, TRUE);
		f = fopen(path, "wb");
		if (f) {
			fwrite(buf, 1, len, f);
			fclose(f);
			enh_log("Game.ini tuned for this machine (%d changes), applies to this start already (the engine reads Game.ini after this DLL is loaded); a copy is %s", changed, bak);
		}
	}
	free(buf);
}

/* ---- Resource prefetch ------------------------------------------------------------------------------------------
 * The engine reads its packages one after another in its single thread, and every first read of a file waits for the disk. While the engine
 * is still starting (the DLL is loaded before it), a few background threads read the game's data files once, so that by the time the
 * engine asks for them they are in the system file cache. Order: the script packages of System, animations, static meshes, textures,
 * sounds, the maps. The total is limited (a quarter of the RAM, 3 GB at most), the threads run below normal priority, and  Prefetch=False
 * anywhere in Game.ini switches it off. Nothing is kept by the DLL: it only reads. */
#define PF_MAXFILES 4096
static char *g_pfPath[PF_MAXFILES];
static unsigned long long g_pfSize[PF_MAXFILES];
static int g_pfCount;
static volatile LONG g_pfNext;
static volatile LONG g_pfDone;
static volatile LONGLONG g_pfBytes;
static unsigned long long g_pfBudget;
static int g_pfThreads;
static DWORD g_pfStart;

static void pf_add_dir(const char *root, const char *dir, const char *pattern)
{
	char pat[MAX_PATH], full[MAX_PATH];
	WIN32_FIND_DATAA fd;
	HANDLE h;
	snprintf(pat, sizeof pat, "%s\\%s\\%s", root, dir, pattern);
	h = FindFirstFileA(pat, &fd);
	if (h == INVALID_HANDLE_VALUE)
		return;
	do {
		if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
			continue;
		if (g_pfCount >= PF_MAXFILES)
			break;
		snprintf(full, sizeof full, "%s\\%s\\%s", root, dir, fd.cFileName);
		g_pfPath[g_pfCount] = _strdup(full);
		g_pfSize[g_pfCount] = ((unsigned long long)fd.nFileSizeHigh << 32) | fd.nFileSizeLow;
		g_pfCount++;
	} while (FindNextFileA(h, &fd));
	FindClose(h);
}

static DWORD WINAPI pf_worker(LPVOID unused)
{
	static unsigned char *buf;
	unsigned char *mine = (unsigned char *)VirtualAlloc(NULL, 1 << 20, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
	(void)unused; (void)buf;
	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
	for (;;) {
		LONG i = InterlockedIncrement(&g_pfNext) - 1;
		HANDLE f;
		DWORD got;
		if (!mine || i >= g_pfCount)
			break;
		if ((unsigned long long)g_pfBytes + g_pfSize[i] > g_pfBudget)
			continue;
		f = CreateFileA(g_pfPath[i], GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
		if (f == INVALID_HANDLE_VALUE)
			continue;
		while (ReadFile(f, mine, 1 << 20, &got, NULL) && got > 0)
			InterlockedExchangeAdd64(&g_pfBytes, got);
		CloseHandle(f);
	}
	if (mine)
		VirtualFree(mine, 0, MEM_RELEASE);
	if (InterlockedIncrement(&g_pfDone) == g_pfThreads)
		enh_log("prefetch: %d files, %lld MB read by %d threads in %lu ms", g_pfCount, (long long)(g_pfBytes / (1024 * 1024)), g_pfThreads, (unsigned long)(GetTickCount() - g_pfStart));
	return 0;
}

/* ---- Multisample anti-aliasing for the Direct3D 8 renderer ------------------------------------------------------
 * The engine's D3DDrv has no anti-aliasing option: it creates the device with MultiSampleType = none, so every edge is a staircase.
 * This DLL is the d3d8.dll the game loads, so it can answer Direct3DCreate8 itself: the IDirect3D8 it returns gets a CreateDevice (and its
 * devices a Reset) that ask for multisampling when the adapter supports it. The swap effect must be DISCARD and the back buffer must not be
 * lockable for that. It works the same on the system's Direct3D 8 and behind DXVK. Amount: MSAA=N in Game.ini (0 = off, 2, 4, 8); without the
 * line, 4x on a discrete NVIDIA or AMD card, none otherwise. */
static void *g_d3d;
static UINT g_adapter, g_devtype;

typedef HRESULT (__stdcall *CreateDeviceFn)(void *, UINT, UINT, HWND, DWORD, DWORD *, void **);
typedef HRESULT (__stdcall *ResetFn)(void *, DWORD *);
typedef HRESULT (__stdcall *CheckMsFn)(void *, UINT, UINT, DWORD, BOOL, DWORD);
static CreateDeviceFn real_CreateDevice;
static ResetFn real_Reset;
static int g_msaaLogged;

/* D3DPRESENT_PARAMETERS of Direct3D 8 as DWORDs: 0 width, 1 height, 2 back buffer format, 3 back buffer count, 4 multisample type, 5 swap effect,
 * 6 window, 7 windowed, 8 auto depth stencil, 9 its format, 10 flags, 11 refresh rate, 12 presentation interval. */
/* The system's Direct3D 8 cannot read a multisampled back buffer: the engine's ReadPixels (the loading screen's picture, screenshots) fails with
 * "LockRect failed: D3DERR_INVALIDCALL". DXVK resolves it. So multisampling is asked for only when d3d8_real.dll is DXVK's. */
static int g_isDxvk = -1;
static int real_is_dxvk(void)
{
	FILE *f;
	long sz;
	char *b;
	size_t i;
	if (g_isDxvk >= 0)
		return g_isDxvk;
	g_isDxvk = 0;
	f = fopen("d3d8_real.dll", "rb");
	if (!f)
		return 0;
	fseek(f, 0, SEEK_END);
	sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	b = (char *)malloc((size_t)sz + 1);
	if (b && fread(b, 1, (size_t)sz, f) == (size_t)sz) {
		for (i = 0; i + 4 <= (size_t)sz; i++) {
			if (b[i] == 'D' && b[i + 1] == 'X' && b[i + 2] == 'V' && b[i + 3] == 'K') {
				g_isDxvk = 1;
				break;
			}
		}
	}
	free(b);
	fclose(f);
	enh_log("d3d8_real.dll is %s: multisampling %s", g_isDxvk ? "DXVK" : "the system's Direct3D 8", g_isDxvk ? "allowed" : "switched off (a multisampled back buffer cannot be read there)");
	return g_isDxvk;
}

static void msaa_fix_params(DWORD *pp)
{
	void **vt;
	DWORD fmt;
	if (g_msaa < 2 || !real_is_dxvk() || !g_d3d || !pp || pp[4] != 0)
		return;
	vt = *(void ***)g_d3d;
	fmt = pp[2] ? pp[2] : 22;           /* D3DFMT_X8R8G8B8 when the windowed mode takes the desktop format */
	if (((CheckMsFn)vt[11])(g_d3d, g_adapter, g_devtype, fmt, (BOOL)pp[7], (DWORD)g_msaa) != 0)
		return;
	pp[4] = (DWORD)g_msaa;
	pp[5] = 1;                          /* D3DSWAPEFFECT_DISCARD */
	pp[10] &= ~1u;                      /* D3DPRESENTFLAG_LOCKABLE_BACKBUFFER */
	if (!g_msaaLogged) {
		g_msaaLogged = 1;
		enh_log("anti-aliasing: %dx multisampling asked for (%lux%lu, format %lu, windowed %lu)", g_msaa, pp[0], pp[1], fmt, pp[7]);
	}
}

static HRESULT __stdcall my_Reset(void *dev, DWORD *pp)
{
	msaa_fix_params(pp);
	return real_Reset(dev, pp);
}

/* ---- Frame limiter: IDirect3DDevice8::Present (slot 15 of the device) is followed by a wait until the next frame is due. Sleep (1 ms timer) for
 * the long part, a spin for the last half millisecond. */
typedef HRESULT (__stdcall *PresentFn)(void *, const void *, const void *, HWND, const void *);
static PresentFn real_Present;
static LARGE_INTEGER g_pcFreq, g_nextFrame;

/* ---- Picture of the finished frame (tests): when a file "grab.req" exists in the game's System folder, the back buffer is written as grab_<n>.bmp just before Present, with
 * everything the engine drew (the menu cursor included, which the engine's own shot command leaves out). The file is checked every 20 frames. */
static void grab_frame(void *dev)
{
	void **dvt = *(void ***)dev;
	typedef HRESULT (__stdcall *GetBBFn)(void *, UINT, DWORD, void **);
	typedef HRESULT (__stdcall *CreateImgFn)(void *, UINT, UINT, DWORD, void **);
	typedef HRESULT (__stdcall *CopyRectsFn)(void *, void *, const RECT *, UINT, void *, const POINT *);
	typedef HRESULT (__stdcall *GetDescFn)(void *, DWORD *);
	typedef HRESULT (__stdcall *LockFn)(void *, DWORD *, const RECT *, DWORD);
	typedef HRESULT (__stdcall *UnlockFn)(void *);
	typedef ULONG (__stdcall *RelFn)(void *);
	void *bb = NULL, *img = NULL;
	DWORD desc[8], lr[2];
	static int n;
	char name[64];
	FILE *f;
	if (((GetBBFn)dvt[16])(dev, 0, 0, &bb) != 0 || !bb)
		return;
	if (((GetDescFn)(*(void ***)bb)[8])(bb, desc) == 0 && ((CreateImgFn)dvt[27])(dev, desc[6], desc[7], desc[0], &img) == 0 && img) {
		if (((CopyRectsFn)dvt[28])(dev, bb, NULL, 0, img, NULL) == 0 && ((LockFn)(*(void ***)img)[9])(img, lr, NULL, 0x10) == 0) {
			DWORD w = desc[6], h = desc[7], y;
			unsigned char *bits = (unsigned char *)lr[1];
			snprintf(name, sizeof name, "grab_%d.bmp", ++n);
			f = fopen(name, "wb");
			if (f) {
				unsigned char hd[54] = {0x42, 0x4d};
				DWORD sz = 54 + w * h * 4, off = 54, bi = 40, pl = 1, bpp = 32;
				memcpy(hd + 2, &sz, 4); memcpy(hd + 10, &off, 4); memcpy(hd + 14, &bi, 4);
				memcpy(hd + 18, &w, 4); { int nh = -(int)h; memcpy(hd + 22, &nh, 4); }
				memcpy(hd + 26, &pl, 2); memcpy(hd + 28, &bpp, 2);
				fwrite(hd, 1, 54, f);
				for (y = 0; y < h; y++)
					fwrite(bits + (size_t)y * (size_t)lr[0], 1, w * 4, f);
				fclose(f);
				enh_log("grab: %s %lux%lu format %lu", name, (unsigned long)w, (unsigned long)h, (unsigned long)desc[0]);
			}
			((UnlockFn)(*(void ***)img)[10])(img);
		}
		((RelFn)(*(void ***)img)[2])(img);
	}
	((RelFn)(*(void ***)bb)[2])(bb);
}

/* ---- Menu mouse cursor size. UGUIController::NativePostRender (GUI.dll) draws the cursor with the size of its material times (ClipX / 640) as an INTEGER division, so at
 * 1920 wide the 64 x 64 hand is drawn 192 x 192. The scale is a constant 1.0 below 640 wide: the "jge" that skips that constant is removed and the constant is made smaller, so
 * the hand has the same pixel size at every resolution (default 0.75 = 48 px; SHREK2_CURSOR=<float> overrides it). Bytes are checked before they are changed. */
static unsigned char *g_cursor_p;
static int g_cursor_fixed;
static void patch_cursor(void)
{
	static int done;
	static const unsigned char want[9] = {0x7d, 0x07, 0xc7, 0x45, 0x08, 0x00, 0x00, 0x80, 0x3f};
	HMODULE m;
	unsigned char *p;
	DWORD old;
	float sc = 0.75f;
	char env[32];
	if (done)
		return;
	m = GetModuleHandleA("GUI.dll");
	if (!m)
		return;
	done = 1;
	p = (unsigned char *)m + 0x21dd8;
	if (memcmp(p, want, sizeof want) != 0) {
		enh_log("cursor: unexpected bytes in GUI.dll, nothing changed");
		return;
	}
	if (GetEnvironmentVariableA("SHREK2_CURSOR", env, sizeof env) > 0 && atof(env) > 0.05) {
		sc = (float)atof(env);
		g_cursor_fixed = 1;
	}
	if (!VirtualProtect(p, sizeof want, PAGE_EXECUTE_READWRITE, &old))
		return;
	p[0] = 0x90;
	p[1] = 0x90;
	memcpy(p + 5, &sc, 4);
	VirtualProtect(p, sizeof want, old, &old);
	FlushInstructionCache(GetCurrentProcess(), p, sizeof want);
	g_cursor_p = p;
	enh_log("cursor: GUI.dll scale fixed at %.2f", (double)sc);
}

/* The hand follows the screen: 0.75 (48 px) at 1080 lines, in proportion to the height of the back buffer at other sizes (a 4K screen gets a hand twice as large,
 * 480 lines a third), checked every 30 frames, so a change of the resolution in the settings is followed too. SHREK2_CURSOR keeps a fixed value. */
static void cursor_follow(void *dev)
{
	static DWORD calls;
	static float last;
	void **dvt = *(void ***)dev;
	typedef HRESULT (__stdcall *GetBBFn)(void *, UINT, DWORD, void **);
	typedef HRESULT (__stdcall *GetDescFn)(void *, DWORD *);
	typedef ULONG (__stdcall *RelFn)(void *);
	void *bb = NULL;
	DWORD desc[8], old;
	float sc;
	if (!g_cursor_p || g_cursor_fixed || (++calls % 30) != 0)
		return;
	if (((GetBBFn)dvt[16])(dev, 0, 0, &bb) != 0 || !bb)
		return;
	if (((GetDescFn)(*(void ***)bb)[8])(bb, desc) == 0 && desc[7] >= 200) {
		sc = 0.75f * (float)desc[7] / 1080.0f;
		if (sc < 0.4f)
			sc = 0.4f;
		if (sc > 2.0f)
			sc = 2.0f;
		if (sc != last && VirtualProtect(g_cursor_p, 9, PAGE_EXECUTE_READWRITE, &old)) {
			memcpy(g_cursor_p + 5, &sc, 4);
			VirtualProtect(g_cursor_p, 9, old, &old);
			FlushInstructionCache(GetCurrentProcess(), g_cursor_p, 9);
			enh_log("cursor: scale %.2f for %lu lines", (double)sc, (unsigned long)desc[7]);
			last = sc;
		}
	}
	((RelFn)(*(void ***)bb)[2])(bb);
}

static HRESULT __stdcall my_Present(void *dev, const void *src, const void *dst, HWND wnd, const void *dirty)
{
	patch_cursor();
	cursor_follow(dev);
	{
		static DWORD gcalls;
		if ((++gcalls % 20) == 0 && GetFileAttributesA("grab.req") != INVALID_FILE_ATTRIBUTES) {
			DeleteFileA("grab.req");
			grab_frame(dev);
		}
	}
	LARGE_INTEGER pa, pb;
	QueryPerformanceCounter(&pa);
	HRESULT hr = real_Present(dev, src, dst, wnd, dirty);
	QueryPerformanceCounter(&pb);
	{
		/* [FPS] once per 5 s: frames, average rate, the longest frame, and how much of the time the process waited inside Present (the graphics
		 * adapter or the screen); the pid tells the host's line from the guest's when both write one log */
		static DWORD calls, t0;
		static LONGLONG lastEnd, worst, inPresent, qf;
		DWORD tn = GetTickCount();
		if (!qf) {
			LARGE_INTEGER f;
			QueryPerformanceFrequency(&f);
			qf = f.QuadPart;
		}
		if (lastEnd && pb.QuadPart - lastEnd > worst)
			worst = pb.QuadPart - lastEnd;
		inPresent += pb.QuadPart - pa.QuadPart;
		lastEnd = pb.QuadPart;
		if (!t0)
			t0 = tn;
		calls++;
		if (tn - t0 >= 5000) {
			enh_log("[FPS] pid %lu: %lu frames in %lu ms = %.1f fps, longest frame %.0f ms, %.0f %% of the time inside Present (limit %d)", GetCurrentProcessId(), (unsigned long)calls,
				(unsigned long)(tn - t0), calls * 1000.0 / (tn - t0), worst * 1000.0 / qf, inPresent * 100.0 * 1000.0 / qf / (tn - t0), g_maxfps);
			calls = 0;
			worst = 0;
			inPresent = 0;
			t0 = tn;
		}
	}
	if (g_maxfps >= 20) {
		LARGE_INTEGER now;
		LONGLONG step;
		if (!g_pcFreq.QuadPart)
			QueryPerformanceFrequency(&g_pcFreq);
		step = g_pcFreq.QuadPart / g_maxfps;
		QueryPerformanceCounter(&now);
		if (g_nextFrame.QuadPart == 0 || now.QuadPart - g_nextFrame.QuadPart > step * 4)
			g_nextFrame.QuadPart = now.QuadPart;          /* first frame, or a long hitch (a level load): no catching up */
		g_nextFrame.QuadPart += step;
		for (;;) {
			LONGLONG left;
			QueryPerformanceCounter(&now);
			left = g_nextFrame.QuadPart - now.QuadPart;
			if (left <= 0)
				break;
			if (left * 1000 / g_pcFreq.QuadPart >= 2)
				Sleep(1);
			else
				YieldProcessor();
		}
	}
	return hr;
}

static HRESULT __stdcall my_CreateDevice(void *d3d, UINT adapter, UINT type, HWND wnd, DWORD flags, DWORD *pp, void **out)
{
	HRESULT hr;
	g_adapter = adapter;
	g_devtype = type;
	msaa_fix_params(pp);
	hr = real_CreateDevice(d3d, adapter, type, wnd, flags, pp, out);
	if (hr != 0 && g_msaa >= 2 && pp && pp[4] != 0) {
		/* the multisampled device was refused: the application's own parameters */
		enh_log("anti-aliasing: CreateDevice failed (0x%lx) with %lu samples, retrying without", (unsigned long)hr, pp[4]);
		pp[4] = 0;
		hr = real_CreateDevice(d3d, adapter, type, wnd, flags, pp, out);
	}
	if (hr == 0 && out && *out && !real_Reset) {
		void **dvt = *(void ***)*out;
		DWORD old;
		real_Reset = (ResetFn)dvt[14];
		if (VirtualProtect(&dvt[14], sizeof(void *), PAGE_READWRITE, &old)) {
			dvt[14] = (void *)my_Reset;
			VirtualProtect(&dvt[14], sizeof(void *), old, &old);
		}
		real_Present = (PresentFn)dvt[15];
		if (VirtualProtect(&dvt[15], sizeof(void *), PAGE_READWRITE, &old)) {
			dvt[15] = (void *)my_Present;
			VirtualProtect(&dvt[15], sizeof(void *), old, &old);
		}
		enh_log("frame limiter: %d fps", g_maxfps);
	}
	return hr;
}

typedef void *(__stdcall *Create8Fn)(UINT);

void *__stdcall Direct3DCreate8(UINT version)
{
	static Create8Fn real;
	void *d3d;
	if (!real) {
		HMODULE m = LoadLibraryA("d3d8_real.dll");
		real = m ? (Create8Fn)GetProcAddress(m, "Direct3DCreate8") : NULL;
	}
	if (!real)
		return NULL;
	d3d = real(version);
	if (d3d && !g_d3d) {
		void **vt = *(void ***)d3d;
		DWORD old;
		g_d3d = d3d;
		real_CreateDevice = (CreateDeviceFn)vt[15];
		if (VirtualProtect(&vt[15], sizeof(void *), PAGE_READWRITE, &old)) {
			vt[15] = (void *)my_CreateDevice;
			VirtualProtect(&vt[15], sizeof(void *), old, &old);
		}
		enh_log("Direct3DCreate8: IDirect3D8 %p, CreateDevice hooked, multisampling %dx", d3d, g_msaa);
	}
	return d3d;
}

static DWORD WINAPI pf_main(LPVOID unused)
{
	char exe[MAX_PATH], *p;
	unsigned long long total = 0;
	int i;
	(void)unused;
	if (g_noPrefetch)
		return 0;
	if (!GetModuleFileNameA(NULL, exe, MAX_PATH))
		return 0;
	p = strrchr(exe, '\\');
	if (!p)
		return 0;
	*p = 0;                                   /* ...\System */
	p = strrchr(exe, '\\');
	if (!p)
		return 0;
	*p = 0;                                   /* the game's folder */
	g_pfStart = GetTickCount();
	pf_add_dir(exe, "System", "*.u");
	pf_add_dir(exe, "Animations", "*.ukx");
	pf_add_dir(exe, "StaticMeshes", "*.usx");
	pf_add_dir(exe, "Textures", "*.utx");
	pf_add_dir(exe, "Sounds", "*.uax");
	pf_add_dir(exe, "Maps", "*.unr");
	for (i = 0; i < g_pfCount; i++)
		total += g_pfSize[i];
	g_pfBudget = (unsigned long long)g_hw.ramMB * 1024 * 1024 / 4;
	if (g_pfBudget > 3ull * 1024 * 1024 * 1024)
		g_pfBudget = 3ull * 1024 * 1024 * 1024;
	if (g_pfBudget == 0)
		g_pfBudget = 256ull * 1024 * 1024;
	g_pfThreads = g_hw.logical >= 8 ? 4 : (g_hw.logical >= 4 ? 2 : 1);
	enh_log("prefetch: %d files, %llu MB found, budget %llu MB, %d threads", g_pfCount, total / (1024 * 1024), g_pfBudget / (1024 * 1024), g_pfThreads);
	for (i = 0; i < g_pfThreads; i++)
		CreateThread(NULL, 0, pf_worker, NULL, 0, NULL);
	return 0;
}

/* ---- Settings the game's own menu can change ---------------------------------------------------------------------
 * 3511 EnhGetSetting(Id), 3512 EnhSetSetting(Id, Value). Ids: 1 anti-aliasing samples (0, 2, 4, 8): changes the live value of the Direct3D hook
 * (it is used by the next device creation or reset, so a SetRes in the menu applies it) and  MSAA=  in Game.ini; 2 anisotropy (1, 4, 8, 16):
 * LevelOfAnisotropy in Game.ini; 3 (read only) the Vulkan layer (DXVK) is installed. */
static int ini_path(char *path, size_t n)
{
	char dir[MAX_PATH];
	DWORD k = GetEnvironmentVariableA("SHREK2_DOCS", dir, MAX_PATH);
	if (k == 0 || k >= MAX_PATH) {
		HMODULE sh = LoadLibraryA("shell32.dll");
		HRESULT (WINAPI *get)(HWND, int, HANDLE, DWORD, LPSTR) = sh ? (void *)GetProcAddress(sh, "SHGetFolderPathA") : NULL;
		if (!get || get(NULL, 5, NULL, 0, dir) != 0)
			return 0;
	}
	snprintf(path, n, "%s\\Shrek 2\\Game.ini", dir);
	return 1;
}

/* Sets Key in [Section] whatever it was; adds the line (or the whole section) when it is missing. */
static void ini_put_file(const char *section, const char *key, const char *value)
{
	char path[MAX_PATH], head[160], line[160];
	FILE *f;
	long sz;
	char *buf, *p, *out;
	size_t kl = strlen(key), len;
	if (!ini_path(path, sizeof path))
		return;
	f = fopen(path, "rb");
	if (!f)
		return;
	fseek(f, 0, SEEK_END);
	sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	buf = (char *)malloc((size_t)sz + 1);
	if (!buf || fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
		fclose(f);
		free(buf);
		return;
	}
	fclose(f);
	buf[sz] = 0;
	len = (size_t)sz;
	snprintf(head, sizeof head, "[%s]", section);
	snprintf(line, sizeof line, "%s=%s", key, value);
	p = strstr(buf, head);
	out = (char *)malloc(len + strlen(line) + strlen(head) + 16);
	if (!out) {
		free(buf);
		return;
	}
	if (!p) {
		memcpy(out, buf, len);
		len += (size_t)sprintf(out + len, "\r\n%s\r\n%s\r\n", head, line);
	} else {
		char *s = p + strlen(head), *end = buf + len, *hit = NULL;
		while (s < end && *s != '[') {
			char *eol = s;
			while (eol < end && *eol != '\r' && *eol != '\n')
				eol++;
			if ((size_t)(eol - s) > kl && !_strnicmp(s, key, kl) && s[kl] == '=') {
				hit = s;
				break;
			}
			s = eol;
			while (s < end && (*s == '\r' || *s == '\n'))
				s++;
		}
		if (hit) {
			char *eol = hit;
			size_t a = (size_t)(hit - buf);
			while (eol < end && *eol != '\r' && *eol != '\n')
				eol++;
			memcpy(out, buf, a);
			memcpy(out + a, line, strlen(line));
			memcpy(out + a + strlen(line), eol, (size_t)(end - eol));
			len = a + strlen(line) + (size_t)(end - eol);
		} else {
			char *after = p + strlen(head);
			size_t a;
			while (after < end && (*after == '\r' || *after == '\n') && 0)
				after++;
			while (after < end && *after != '\r' && *after != '\n')
				after++;
			a = (size_t)(after - buf);
			memcpy(out, buf, a);
			len = a + (size_t)sprintf(out + a, "\r\n%s", line);
			memcpy(out + len, after, (size_t)(end - after));
			len += (size_t)(end - after);
		}
	}
	f = fopen(path, "wb");
	if (f) {
		fwrite(out, 1, len, f);
		fclose(f);
	}
	free(out);
	free(buf);
}

static int ini_get_int(const char *section, const char *key, int dflt)
{
	char path[MAX_PATH], head[160];
	FILE *f;
	long sz;
	char *buf, *s, *end;
	size_t kl = strlen(key);
	int v = dflt;
	if (!ini_path(path, sizeof path))
		return dflt;
	f = fopen(path, "rb");
	if (!f)
		return dflt;
	fseek(f, 0, SEEK_END);
	sz = ftell(f);
	fseek(f, 0, SEEK_SET);
	buf = (char *)malloc((size_t)sz + 1);
	if (!buf || fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
		fclose(f);
		free(buf);
		return dflt;
	}
	fclose(f);
	buf[sz] = 0;
	snprintf(head, sizeof head, "[%s]", section);
	s = strstr(buf, head);
	if (s) {
		s += strlen(head);
		end = buf + sz;
		while (s < end && *s != '[') {
			char *eol = s;
			while (eol < end && *eol != '\r' && *eol != '\n')
				eol++;
			if ((size_t)(eol - s) > kl && !_strnicmp(s, key, kl) && s[kl] == '=') {
				v = atoi(s + kl + 1);
				break;
			}
			s = eol;
			while (s < end && (*s == '\r' || *s == '\n'))
				s++;
		}
	}
	free(buf);
	return v;
}

static int dxvk_present(void)
{
	char exe[MAX_PATH], *p;
	if (!GetModuleFileNameA(NULL, exe, MAX_PATH))
		return 0;
	p = strrchr(exe, '\\');
	if (!p)
		return 0;
	strcpy(p + 1, "d3d9.dll");
	return GetFileAttributesA(exe) != INVALID_FILE_ATTRIBUTES;
}

static void __attribute__((thiscall)) nat_getsetting(void *self, FFrame *stack, void *result)
{
	int id = 0, v = 0;
	(void)self;
	fn_Step(stack, stack->object, &id);
	stack->code++;
	if (id == 1)
		v = g_msaa;
	else if (id == 2)
		v = ini_get_int("D3DDrv.D3DRenderDevice", "LevelOfAnisotropy", 1);
	else if (id == 3)
		v = dxvk_present();
	*(int *)result = v;
}

static void __attribute__((thiscall)) nat_setsetting(void *self, FFrame *stack, void *result)
{
	int id = 0, val = 0;
	char s[16];
	(void)self; (void)result;
	fn_Step(stack, stack->object, &id);
	fn_Step(stack, stack->object, &val);
	stack->code++;
	snprintf(s, sizeof s, "%d", val);
	if (id == 1) {
		g_msaa = val;
		ini_put_file("Enhanced.EnhancedHardware", "MSAA", s);
		enh_log("setting: anti-aliasing %d", val);
	} else if (id == 2) {
		ini_put_file("D3DDrv.D3DRenderDevice", "LevelOfAnisotropy", s);
		enh_log("setting: anisotropy %d", val);
	}
}

static DWORD WINAPI hw_thread(LPVOID unused)
{
	(void)unused;
	hw_probe();
	return 0;
}

/* ---- Private fonts ------------------------------------------------------------------------------------------------
 * The engine makes some of its fonts at run time from Windows fonts by name (SAPFont.int / SAPFont.rus). A .ttf file named in the list below,
 * if it lies in the game's System folder, is added to this process only (FR_PRIVATE): the font need not be installed in Windows. */
static void load_private_fonts(void)
{
	static const char *files[] = { "Shrekrusbyme.ttf", NULL };
	char exe[MAX_PATH], path[MAX_PATH], *p;
	int i;
	if (!GetModuleFileNameA(NULL, exe, MAX_PATH))
		return;
	p = strrchr(exe, 0x5c);
	if (!p)
		return;
	*p = 0;
	for (i = 0; files[i]; i++) {
		HMODULE gdi = LoadLibraryA("gdi32.dll");
		int (WINAPI *add)(LPCSTR, DWORD, void *) = gdi ? (void *)GetProcAddress(gdi, "AddFontResourceExA") : NULL;
		snprintf(path, sizeof path, "%s%c%s", exe, 0x5c, files[i]);
		if (add && GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES)
			enh_log("private font %s: %d", files[i], add(path, 0x10, NULL));
	}
}

/* ---- 3520 EnhNativeFont(Canvas C, string FontName, int Height): UCanvas.CreateNativeFont for a canvas that is not a typed Canvas in the mod's
 * compile environment (the older engine classes the mod is built against have no such member). The script passes the canvas as the first parameter,
 * the function reads it and hands the rest of the parameters to the engine's own exec function of the canvas. */
typedef void (__attribute__((thiscall)) *CanvasFontFn)(void *, FFrame *, void *);
static CanvasFontFn fn_execCreateNativeFont;

static void __attribute__((thiscall)) nat_canvasfont(void *self, FFrame *stack, void *result)
{
	void *canvas = NULL;
	(void)self;
	fn_Step(stack, stack->object, &canvas);
	if (!fn_execCreateNativeFont) {
		HMODULE eng = GetModuleHandleA("Engine.dll");
		if (eng)
			fn_execCreateNativeFont = (CanvasFontFn)GetProcAddress(eng, "?execCreateNativeFont@UCanvas@@QAEXAAUFFrame@@QAX@Z");
	}
	if (canvas && fn_execCreateNativeFont) {
		fn_execCreateNativeFont(canvas, stack, result);
	} else {
		*(void **)result = NULL;
		stack->code++;
	}
}

/* ---- Network: byte counters, and (tests only) packet loss and lag --------------------------------------------------------
 * IpDrv.dll sends and receives the game's UDP through WSOCK32 (sendto / recvfrom, imported by ordinal). Once IpDrv.dll is loaded a thread
 * replaces those two entries of its import table. Every second, while there is traffic, enhnative.log gets one "[NET]" line per process:
 * payload bytes and packets sent and received, the largest packet, packets over 1000 bytes and packets the simulation dropped.
 * SHREK2_NETSIM="loss=5,lag=80,jitter=20" (environment of the process, never read from an ini) makes the OUTGOING packets of this process get
 * lost by 5 %, arrive 80 ms late, plus up to 20 ms of random extra delay (so some arrive out of order). With the variable set in both
 * processes of a test every direction gets the value (a round trip is twice the lag). */
typedef int (WINAPI *SendToFn)(UINT_PTR s, const char *buf, int len, int flags, const void *to, int tolen);
typedef int (WINAPI *RecvFromFn)(UINT_PTR s, char *buf, int len, int flags, void *from, int *fromlen);
static SendToFn real_sendto;
static RecvFromFn real_recvfrom;
static volatile LONG n_outB, n_outP, n_inB, n_inP, n_drop, n_big, n_maxout;
static int g_simLoss, g_simLag, g_simJitter;   /* loss in hundredths of a percent, times in ms */

typedef struct { UINT_PTR s; int flags, tolen, len; unsigned char to[32]; unsigned char data[1600]; LONGLONG due; int used; } NetDelay;
#define NET_QUEUE 512
static NetDelay g_nq[NET_QUEUE];
static CRITICAL_SECTION g_nqcs;
static LARGE_INTEGER g_qpf;

static LONGLONG net_now_us(void)
{
	LARGE_INTEGER t;
	QueryPerformanceCounter(&t);
	return t.QuadPart * 1000000 / g_qpf.QuadPart;
}

static int WINAPI my_sendto(UINT_PTR s, const char *buf, int len, int flags, const void *to, int tolen)
{
	InterlockedExchangeAdd(&n_outB, len);
	InterlockedIncrement(&n_outP);
	if (len > 1000)
		InterlockedIncrement(&n_big);
	if (len > n_maxout)
		n_maxout = len;
	if (g_simLoss > 0 && rand() % 10000 < g_simLoss) {
		InterlockedIncrement(&n_drop);
		return len;
	}
	if (g_simLag > 0 && len <= (int)sizeof g_nq[0].data && tolen <= (int)sizeof g_nq[0].to) {
		int i;
		EnterCriticalSection(&g_nqcs);
		for (i = 0; i < NET_QUEUE && g_nq[i].used; i++)
			;
		if (i < NET_QUEUE) {
			g_nq[i].s = s;
			g_nq[i].flags = flags;
			g_nq[i].tolen = tolen;
			g_nq[i].len = len;
			memcpy(g_nq[i].to, to, tolen);
			memcpy(g_nq[i].data, buf, len);
			g_nq[i].due = net_now_us() + 1000LL * (g_simLag + (g_simJitter > 0 ? rand() % (g_simJitter + 1) : 0));
			g_nq[i].used = 1;
			LeaveCriticalSection(&g_nqcs);
			return len;
		}
		LeaveCriticalSection(&g_nqcs);   /* queue full: send at once */
	}
	return real_sendto(s, buf, len, flags, to, tolen);
}

static int WINAPI my_recvfrom(UINT_PTR s, char *buf, int len, int flags, void *from, int *fromlen)
{
	int r = real_recvfrom(s, buf, len, flags, from, fromlen);
	if (r > 0) {
		InterlockedExchangeAdd(&n_inB, r);
		InterlockedIncrement(&n_inP);
	}
	return r;
}

static DWORD WINAPI net_delay_thread(LPVOID unused)
{
	typedef UINT (WINAPI *TimeFn)(UINT);
	HMODULE mm = LoadLibraryA("winmm.dll");
	TimeFn tbp = mm ? (TimeFn)GetProcAddress(mm, "timeBeginPeriod") : NULL;
	(void)unused;
	if (tbp)
		tbp(1);
	for (;;) {
		int i, best;
		LONGLONG now = net_now_us();
		EnterCriticalSection(&g_nqcs);
		for (;;) {   /* the earliest due packet first */
			best = -1;
			for (i = 0; i < NET_QUEUE; i++)
				if (g_nq[i].used && g_nq[i].due <= now && (best < 0 || g_nq[i].due < g_nq[best].due))
					best = i;
			if (best < 0)
				break;
			real_sendto(g_nq[best].s, (const char *)g_nq[best].data, g_nq[best].len, g_nq[best].flags, g_nq[best].to, g_nq[best].tolen);
			g_nq[best].used = 0;
		}
		LeaveCriticalSection(&g_nqcs);
		Sleep(1);
	}
	return 0;
}

static int net_patch_iat(HMODULE mod, void *f_send, void *f_recv)
{
	BYTE *base = (BYTE *)mod;
	IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
	IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + dos->e_lfanew);
	IMAGE_DATA_DIRECTORY *dir = &nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
	IMAGE_IMPORT_DESCRIPTOR *imp;
	int n = 0;
	if (!dir->VirtualAddress)
		return 0;
	for (imp = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir->VirtualAddress); imp->Name; imp++) {
		IMAGE_THUNK_DATA *thunk;
		if (_stricmp((char *)(base + imp->Name), "wsock32.dll") != 0 && _stricmp((char *)(base + imp->Name), "ws2_32.dll") != 0)
			continue;
		for (thunk = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk); thunk->u1.Function; thunk++) {
			void *repl = NULL;
			DWORD old;
			if (thunk->u1.Function == (DWORD_PTR)f_send)
				repl = (void *)my_sendto;
			else if (thunk->u1.Function == (DWORD_PTR)f_recv)
				repl = (void *)my_recvfrom;
			if (!repl)
				continue;
			if (VirtualProtect(&thunk->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) {
				thunk->u1.Function = (DWORD_PTR)repl;
				VirtualProtect(&thunk->u1.Function, sizeof(void *), old, &old);
				n++;
			}
		}
	}
	return n;
}

static DWORD WINAPI net_main(LPVOID unused)
{
	int i;
	HMODULE ip = NULL, ws = NULL;
	(void)unused;
	for (i = 0; i < 6000; i++) {   /* the engine loads IpDrv.dll when it starts a network driver */
		ip = GetModuleHandleA("IpDrv.dll");
		ws = GetModuleHandleA("wsock32.dll");
		if (ip && ws)
			break;
		Sleep(100);
	}
	if (!ip || !ws)
		return 0;
	real_sendto = (SendToFn)GetProcAddress(ws, "sendto");
	real_recvfrom = (RecvFromFn)GetProcAddress(ws, "recvfrom");
	if (!real_sendto || !real_recvfrom) {
		enh_log("net: sendto/recvfrom not found in wsock32.dll");
		return 0;
	}
	i = net_patch_iat(ip, (void *)real_sendto, (void *)real_recvfrom);
	enh_log("net: IpDrv.dll import table patched (%d entries), simulation: loss %d.%02d %%, lag %d ms, jitter %d ms", i, g_simLoss / 100, g_simLoss % 100, g_simLag, g_simJitter);
	if (i == 0)
		return 0;
	for (;;) {
		long ob, op, ib, ip2, dr, bg, mx;
		Sleep(1000);
		ob = InterlockedExchange(&n_outB, 0);
		op = InterlockedExchange(&n_outP, 0);
		ib = InterlockedExchange(&n_inB, 0);
		ip2 = InterlockedExchange(&n_inP, 0);
		dr = InterlockedExchange(&n_drop, 0);
		bg = InterlockedExchange(&n_big, 0);
		mx = InterlockedExchange(&n_maxout, 0);
		if (op || ip2)
			enh_log("[NET] pid %lu out %ld B/s %ld pkt/s (max %ld, over 1000: %ld, dropped %ld) in %ld B/s %ld pkt/s", GetCurrentProcessId(), ob, op, mx, bg, dr, ib, ip2);
	}
	return 0;
}

static void net_init(void)
{
	char v[160], *tok;
	InitializeCriticalSection(&g_nqcs);
	QueryPerformanceFrequency(&g_qpf);
	if (GetEnvironmentVariableA("SHREK2_NETSIM", v, sizeof v) > 0) {
		for (tok = strtok(v, ", "); tok; tok = strtok(NULL, ", ")) {
			if (strncmp(tok, "loss=", 5) == 0)
				g_simLoss = (int)(atof(tok + 5) * 100.0 + 0.5);
			else if (strncmp(tok, "lag=", 4) == 0)
				g_simLag = atoi(tok + 4);
			else if (strncmp(tok, "jitter=", 7) == 0)
				g_simJitter = atoi(tok + 7);
		}
		srand((unsigned)GetTickCount() ^ GetCurrentProcessId());
		if (g_simLag > 0)
			CreateThread(NULL, 0, net_delay_thread, NULL, 0, NULL);
	}
	CreateThread(NULL, 0, net_main, NULL, 0, NULL);
}

static void native_init(void)
{
	/* Game.exe imports d3d8.dll, so this runs before the engine reads Game.ini: the tuning applies to this very start. DXGI must not be
	 * started inside DllMain (loader lock): a thread gets the GPU name and the video memory. */
	load_private_fonts();
	hw_probe_quick();
	hw_tune();
	net_init();
	CreateThread(NULL, 0, pf_main, NULL, 0, NULL);
	CreateThread(NULL, 0, hw_thread, NULL, 0, NULL);
	HMODULE core = GetModuleHandleA("Core.dll");
	void **table;
	void *undef;
	if (!core) {
		enh_log("Core.dll is not loaded yet");
		return;
	}
	table = (void **)GetProcAddress(core, "?GNatives@@3PAP8UObject@@AEXAAUFFrame@@QAX@ZA");
	undef = (void *)GetProcAddress(core, "?execUndefined@UObject@@QAEXAAUFFrame@@QAX@Z");
	if (!table) {
		enh_log("GNatives not found");
		return;
	}
	enh_log("GNatives at %p, execUndefined %p", (void *)table, undef);
	register_native(table, 3500, nat_version, undef);
	register_native(table, 3501, nat_animextra, undef);
	register_native(table, 3502, nat_animsyncon, undef);
	register_native(table, 3503, nat_drawoffset, undef);
	register_native(table, 3504, nat_calib, undef);
	register_native(table, 3510, nat_hwinfo, undef);
	register_native(table, 3511, nat_getsetting, undef);
	register_native(table, 3512, nat_setsetting, undef);
	register_native(table, 3520, nat_canvasfont, undef);
	{
		HMODULE eng = GetModuleHandleA("Engine.dll");
		if (eng)
			fn_GetAnimRateOnChannel = (GetRateFn)GetProcAddress(eng, "?GetAnimRateOnChannel@USkeletalMeshInstance@@QAEMH@Z");
		{
			HMODULE c2 = GetModuleHandleA("Core.dll");
			fn_Step = (StepFn)GetProcAddress(c2, "?Step@FFrame@@QAEXPAVUObject@@QAX@Z");
			fn_IsA = (IsAFn)GetProcAddress(c2, "?IsA@UObject@@QBEHPAVUClass@@@Z");
		}
		if (eng) {
			fn_IsAnimLooping = (IntChFn)GetProcAddress(eng, "?IsAnimLooping@USkeletalMeshInstance@@UAEHH@Z");
			fn_GetBlendAlpha = (FloatChFn)GetProcAddress(eng, "?GetBlendAlpha@USkeletalMeshInstance@@QAEMH@Z");
			pSkelClass = (void *)GetProcAddress(eng, "?PrivateStaticClass@USkeletalMeshInstance@@0VUClass@@A");
		}
		fn_GetName = (GetNameFn)GetProcAddress(GetModuleHandleA("Core.dll"), "?GetName@UObject@@QBEPBGXZ");
		hook_thunk("Engine.dll", "?ReplicateAnim@AActor@@QAEXHVFName@@MMMMH@Z", (void *)hook_ReplicateAnim, (void **)&orig_ReplicateAnim);
		hook_thunk("Engine.dll", "?eventPlayerCalcView@APlayerController@@QAEXAAPAVAActor@@AAVFVector@@AAVFRotator@@@Z", (void *)hook_PlayerCalcView, (void **)&orig_PlayerCalcView);
		hook_thunk("Engine.dll", "?PlayReplicatedAnim@AActor@@QAEXXZ", (void *)hook_PlayReplicatedAnim, (void **)&orig_PlayReplicatedAnim);
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
		native_init();
	}
	return TRUE;
}
