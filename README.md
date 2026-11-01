# Shrek 2 Enhanced

A co-op mod for **Shrek 2 (PC, 2004)**, the Russian 1C edition (Unreal Engine 2.5). Players join a game from the book menu (LAN search, direct address or UPnP over the Internet), share the level and its checkpoints, and see each other's characters and animations. The mod also adds a Hor+ field of view, a resolution list, a rearranged HUD, co-op saves, and optional English and HD textures built from your own copy of the HD pack.

Status: beta. It is tested with scripted bots and a second game window; play over the Internet between real people has had little testing.

This repository holds **sources only**. It does not contain game files, textures, audio, the HD pack, the Level Editor, the Shrek title font, or any compiled binary. The game's own packages are never modified except as described under "What the setup changes".

## Layout

| Folder | What it is |
|---|---|
| `mod/Enhanced/Classes` | UnrealScript of the mod (`Enhanced.u`): game class, menus, lobby, saves, HUD, animation sync, UPnP |
| `mod/IpDrv/Classes` | the sockets package the mod's UPnP and LAN code uses (`IpDrv.u`) |
| `mod/Localization` | `Enhanced.int` and `Enhanced.Rus` (UTF-16): mod texts and the speaker table |
| `mod/Obs/Classes` | a test-only mutator that measures the stock game's jump; not shipped |
| `native/` | the engine layer, a Direct3D 8 proxy (`d3d8.dll`): animation sync natives, hardware tuning, prefetch, anti-aliasing, menu cursor scale |
| `installer/` | the setup program (WinForms, C#): patches, backups, transactional install with rollback, removal |
| `tools/` | `patch_engine.py` (the `Engine.dll` patch the setup applies in C#), and three test-rig proxies: `shfolder` (redirects My Documents), `quiet` (windows that never take focus), `mutexfix` (two game copies at once) |
| `tests/` | installer tests that run on a scratch copy of a game |

## What the setup changes

Everything it touches is backed up first as `<name>.enhanced-backup`, and "Remove" puts the originals back. In the game folder: `Engine.dll` (a three-place patch of the network start, checked against the stock SHA-256), `Game.exe` (large-address-aware flag, plus a DPI manifest), `Packages.md5`, `Default.ini`, `DefUser.ini`, `SAPFont.*`, the mod's packages, `d3d8.dll` (the engine layer; the real one is copied beside it as `d3d8_real.dll`), and the textures if you choose English or HD. In your Documents: two lines of `Game.ini` (the default map and game class), plus sections of the mod in `User.ini`. Saves are never touched. A failed install restores every file it changed.

The setup works only on the stock Russian 1C edition (it checks the hash of `Engine.dll`).

## Building

Everything builds on Windows. Nothing here is downloaded for you.

**Mod scripts** need the Shrek 2 Level Editor (it supplies `UCC.exe` and the stub packages the scripts compile against; not included):

```powershell
powershell -File scripts/build-mod.ps1 -LevelEditor "<Level Editor folder>"
```

`Enhanced.u` gets a new GUID on every build, so the game's `Packages.md5` has to be regenerated for it (`UCC Engine.MasterMD5`), or the game refuses to load the package.

**Engine layer**: [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) (i686) on `PATH`, from Git Bash (not PowerShell: the comma in `-Wl,--kill-at` is mangled):

```sh
sh native/build.sh
```

**Setup program**: the .NET Framework 4.x compiler that ships with Windows:

```powershell
powershell -File installer/build.ps1
```

The setup reads a `files` folder next to the exe: `Enhanced.u`, `Enhanced.Rus`, `Enhanced.int`, `IpDrv.u`, `Packages.md5`, `layer\d3d8.dll`, and, for English textures, `textures-en\*.patch`. An optional `installer/bg.png` is embedded as the window picture; without it the window is plain.

## Tests

`tests/test_installer.ps1` copies a game folder, a Documents folder and a built package to a temp folder, then checks rollback, byte-for-byte removal, an update with a different layer build, the player's own `Game.ini` settings, a foreign `d3d8.dll`, and (with `-HdPack`) the HD path. It also fails if the real `Documents\Shrek 2` changes.

```powershell
powershell -File tests/test_installer.ps1 -GameCopy <game copy> -DocsCopy <copy of Documents\Shrek 2> -Package <folder with the setup exe and files> [-HdPack <unpacked HD pack>]
```

Test a copy of the game, never your own install: a game started without the My Documents redirect (`tools/shfolder` or the engine layer) writes into your real saves.

## Rules this project follows

- No game assets in the repository. English and HD textures are made on your PC from your own files (the setup applies hash-checked patches, or reads your own copy of the HD pack).
- The Shrek title font is not shipped. If you put `Shrekrusbyme.ttf` into `System`, the headings use it; otherwise Tahoma.
- No anti-cheat bypass, nothing that touches other people's multiplayer games.

## Part of Co-op Anything

This mod was built with the playbook of the [Co-op Anything](https://github.com/cranebeaker/coop-anything) project (adding co-op to single-player games).

## License

None chosen yet. Until one is added, all rights are reserved by the author.
