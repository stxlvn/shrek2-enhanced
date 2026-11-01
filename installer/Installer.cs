// Shrek 2 Enhanced: what the setup does to the folder of the Russian (1C) edition, and what the removal undoes. Everything that is changed is
// backed up first as <name>.enhanced-backup; the removal puts the originals back. Saves and the player's settings are not touched, except the two
// lines of Game.ini that make the game start in the mod's menu.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

class Installer
{
    public const string StockEngine = "79EB368BA102740644EB6537E1CABFE7BA58DF7BBA47DC4045653CD30A2385E3";
    public const string PatchedEngine = "A3DF1867A24A7E83BCD0728BFC1D91B38EF90335093AB7378BBC7A993C060176";
    const string StockExe = "4900AA131CF35D4951943F2D6EE831841745AF8E5D657FFDCFD7FB012CBAA2EF";

    static readonly string[] ModFiles = { "Enhanced.u", "Enhanced.Rus", "Enhanced.int", "IpDrv.u" };
    static readonly string[] Launchers = { "Enhanced-Host.bat", "Enhanced-Join.bat" };
    const string Bak = ".enhanced-backup";

    class FileChange
    {
        public string Path, Snapshot;
        public bool Existed;
    }

    public string GameDir, DocsDir, Files;
    public Action<string> Log;
    string TxDir;
    readonly List<FileChange> Changes = new List<FileChange>();
    readonly Dictionary<string, bool> Seen = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
    string Sys { get { return Path.Combine(GameDir, "System"); } }
    string TexDir { get { return Path.Combine(GameDir, "Textures"); } }
    string P(string name) { return Path.Combine(Sys, name); }

    public static string Sha(string path)
    {
        using (FileStream f = File.OpenRead(path))
        using (SHA256 s = SHA256.Create())
            return BitConverter.ToString(s.ComputeHash(f)).Replace("-", "");
    }

    void BeforeChange(string path)
    {
        if (TxDir == null || Seen.ContainsKey(path)) return;
        FileChange c = new FileChange();
        c.Path = path;
        c.Existed = File.Exists(path);
        c.Snapshot = Path.Combine(TxDir, Changes.Count.ToString() + ".bin");
        if (c.Existed) System.IO.File.Copy(path, c.Snapshot);
        Changes.Add(c);
        Seen.Add(path, true);
    }

    static void CommitTemp(string tmp, string path)
    {
        if (File.Exists(path)) File.Replace(tmp, path, null);
        else File.Move(tmp, path);
    }

    void AtomicCopy(string src, string path)
    {
        BeforeChange(path);
        string tmp = path + ".enhanced-tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            System.IO.File.Copy(src, tmp, true);
            CommitTemp(tmp, path);
        }
        finally { if (File.Exists(tmp)) File.Delete(tmp); }
    }

    void AtomicWriteAllBytes(string path, byte[] data)
    {
        BeforeChange(path);
        string tmp = path + ".enhanced-tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            System.IO.File.WriteAllBytes(tmp, data);
            CommitTemp(tmp, path);
        }
        finally { if (File.Exists(tmp)) File.Delete(tmp); }
    }

    void AtomicWriteAllText(string path, string text) { AtomicWriteAllText(path, text, new UTF8Encoding(false)); }

    void AtomicWriteAllText(string path, string text, Encoding encoding)
    {
        BeforeChange(path);
        string tmp = path + ".enhanced-tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            System.IO.File.WriteAllText(tmp, text, encoding);
            CommitTemp(tmp, path);
        }
        finally { if (File.Exists(tmp)) File.Delete(tmp); }
    }

    void DeleteFile(string path)
    {
        if (!File.Exists(path)) return;
        BeforeChange(path);
        File.Delete(path);
    }

    void Rollback()
    {
        List<string> errors = new List<string>();
        for (int i = Changes.Count - 1; i >= 0; i--)
        {
            FileChange c = Changes[i];
            try
            {
                if (c.Existed) AtomicCopy(c.Snapshot, c.Path);
                else if (File.Exists(c.Path)) File.Delete(c.Path);
            }
            catch (Exception ex) { errors.Add(c.Path + ": " + ex.Message); }
        }
        if (errors.Count > 0) throw new Exception(string.Join(" | ", errors.ToArray()));
    }

    void Restore(string file, Action<string> log, string saidAs)
    {
        string b = file + Bak;
        if (File.Exists(b))
        {
            AtomicCopy(b, file);
            DeleteFile(b);
            if (saidAs != null) log(saidAs);
        }
    }

    string[] MapFiles()
    {
        return new string[] { P("Default.ini"), Path.Combine(Path.Combine(DocsDir, "Shrek 2"), "Game.ini") };
    }

    string[] FontFiles() { return new string[] { P("SAPFont.int"), P("SAPFont.rus") }; }

    // the two lines of Default.ini and Game.ini that the setup changes: original, replacement, what it says
    static readonly string[][] IniLines = {
        new string[] { "Map=HP-Test.unr", "Map=Book_FrontEnd.unr", "default map set to the front-end book" },
        new string[] { "DefaultGame=ShGame.ShGame", "DefaultGame=Enhanced.EnhancedGame", "game class set to the mod" } };

    // The layer is told by two strings inside it, not by its hash: every build of it differs, and the setup that removes the mod may be of another
    // build than the one that installed it. A d3d8.dll of anybody else (ReShade and the like) has neither string.
    static bool IsOurLayer(string path)
    {
        try
        {
            string s = Encoding.ASCII.GetString(File.ReadAllBytes(path));
            return s.Contains("enhnative.log") && s.Contains("Enhanced.EnhancedHardware");
        }
        catch { return false; }
    }

    // Game.ini is the player's own file (everything changed after the install is theirs): only the two lines of the mod are put back, whether or not
    // the setup made a backup of it. The backup is dropped.
    void RestoreGameIni(string file)
    {
        if (File.Exists(file))
        {
            string text = File.ReadAllText(file);
            string next = text;
            foreach (string[] e in IniLines)
                next = Regex.Replace(next, "(?m)^" + Regex.Escape(e[1]) + "(?=[ \\t]*\\r?$)", e[0].Replace("$", "$$"));
            if (next != text) { AtomicWriteAllText(file, next); Log(Path.GetFileName(file) + " restored (the two lines of the mod; your other settings stay)"); }
        }
        DeleteFile(file + Bak);
    }

    // ---------------------------------------------------------------- removal
    public void Uninstall()
    {
        if (!File.Exists(P("Engine.dll"))) throw new Exception("Engine.dll not found in " + Sys + ". Give the folder that contains the System folder of the game.");
        Restore(P("Engine.dll"), Log, "Engine.dll restored");
        Restore(P("Packages.md5"), Log, "Packages.md5 restored");
        Restore(P("Default.ini"), Log, "Default.ini restored");
        RestoreGameIni(Path.Combine(Path.Combine(DocsDir, "Shrek 2"), "Game.ini"));
        Restore(P("DefUser.ini"), Log, "DefUser.ini restored");
        Restore(P("Game.exe"), Log, "Game.exe restored");
        DeleteFile(P("Game.exe.manifest"));
        foreach (string f in ModFiles) DeleteFile(P(f));
        RestoreTextures();
        foreach (string f in FontFiles()) Restore(f, Log, Path.GetFileName(f) + " restored");
        RemoveLayer();
        string userIni = Path.Combine(Path.Combine(DocsDir, "Shrek 2"), "User.ini");
        if (File.Exists(userIni))
        {
            string text = File.ReadAllText(userIni);
            string clean = Regex.Replace(text, "(?ms)\\r?\\n\\[Enhanced\\.[A-Za-z]+\\].*?(?=\\r?\\n\\[|\\z)", "");
            if (clean != text) { AtomicWriteAllText(userIni, clean); Log("User.ini: the sections of the mod are removed"); }
        }
        foreach (string f in Launchers) DeleteFile(Path.Combine(GameDir, f));
        Log("Shrek 2 Enhanced is removed.");
    }

    void RestoreTextures()
    {
        if (!Directory.Exists(TexDir)) return;
        foreach (string b in Directory.GetFiles(TexDir, "*" + Bak))
        {
            string orig = b.Substring(0, b.Length - Bak.Length);
            AtomicCopy(b, orig);
            DeleteFile(b);
            Log(Path.GetFileName(orig) + " restored");
        }
    }

    void RemoveLayer()
    {
        string dll = P("d3d8.dll"), real = P("d3d8_real.dll"), mark = P("d3d8_real.dll.enhanced-made"), bak = P("d3d8.dll.enhanced-backup");
        if (File.Exists(dll))
        {
            if (!IsOurLayer(dll))
            {
                Log("d3d8.dll is not the engine layer of the mod: left alone.");
                return;
            }
            // a "backup" that is itself a layer of the mod (an update made over an older install) is not something to put back
            if (File.Exists(bak) && !IsOurLayer(bak))
            {
                AtomicCopy(bak, dll);
                DeleteFile(bak);
                Log("The d3d8.dll that preceded the mod was restored.");
            }
            else
            {
                DeleteFile(dll);
                DeleteFile(bak);
                Log("d3d8.dll (engine layer) removed");
            }
        }
        if (File.Exists(mark)) { DeleteFile(real); DeleteFile(mark); }
    }

    // ---------------------------------------------------------------- install
    // A failed install restores every file it touched, including files created during the attempt.
    public void Install(string textures, string hdPack, bool layer)
    {
        TxDir = Path.Combine(GameDir, ".enhanced-txn-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(TxDir);
        try
        {
            InstallCore(textures, hdPack, layer);
            try { Directory.Delete(TxDir, true); } catch (Exception ex) { Log("Temporary install files left: " + ex.Message); }
            TxDir = null;
        }
        catch (Exception ex)
        {
            string tx = TxDir;
            TxDir = null;
            string rollbackError = "";
            try
            {
                Rollback();
                if (Directory.Exists(tx)) Directory.Delete(tx, true);
            }
            catch (Exception rb) { rollbackError = rb.Message; }
            throw new Exception("Installation failed: " + ex.Message + (rollbackError == "" ? " All changed files were restored." : " ROLLBACK FAILED: " + rollbackError));
        }
    }

    // textures: "ru" (the game's own) or "enhd" (the 61 localized textures in English, then the HD pack over everything)
    void InstallCore(string textures, string hdPack, bool layer)
    {
        if (!File.Exists(P("Engine.dll"))) throw new Exception("Engine.dll not found in " + Sys + ". Give the folder that contains the System folder of the game.");
        if (!Directory.Exists(Files)) throw new Exception("The folder \"files\" is missing next to the setup. Unpack the whole archive first.");
        // the scripts of the mod call functions that only the layer adds (EnhNativeVersion and the others): without it the game stops at the first level start with "Unknown code token"
        if (!layer) throw new Exception("The mod cannot start without the engine layer (d3d8.dll): its scripts call functions the layer adds. Not installing without it.");
        foreach (string f in ModFiles)
            if (!File.Exists(Path.Combine(Files, f))) throw new Exception(f + " is missing next to the setup. Nothing was changed.");

        // Engine.dll: the patch of the network start (a backup is kept)
        string have = Sha(P("Engine.dll"));
        if (have == PatchedEngine) Log("Engine.dll is already patched.");
        else if (have == StockEngine)
        {
            if (!File.Exists(P("Engine.dll") + Bak)) AtomicCopy(P("Engine.dll"), P("Engine.dll") + Bak);
            byte[] data = EnginePatch.Apply(File.ReadAllBytes(P("Engine.dll")));
            AtomicWriteAllBytes(P("Engine.dll"), data);
            if (Sha(P("Engine.dll")) != PatchedEngine) throw new Exception("The patched Engine.dll did not have the expected hash.");
            Log("Engine.dll patched.");
        }
        else throw new Exception("Engine.dll of this game is not the 1C edition this installer was made for (sha256 " + have + "). Nothing was changed.");

        GameExe();

        foreach (string f in ModFiles) AtomicCopy(Path.Combine(Files, f), P(f));
        string srcMd5 = Path.Combine(Files, "Packages.md5");
        if (File.Exists(srcMd5))
        {
            if (File.Exists(P("Packages.md5")) && !File.Exists(P("Packages.md5") + Bak)) AtomicCopy(P("Packages.md5"), P("Packages.md5") + Bak);
            AtomicCopy(srcMd5, P("Packages.md5"));
        }

        IniEdits();
        DefaultKeys();
        Beacon();

        // textures: the originals first (a new choice starts from the game's own files), then the choice
        RestoreTextures();
        if (textures == "enhd")
        {
            EnglishTextures();
            HdStage(hdPack);
        }
        else Log("Textures: the game's own (Russian).");

        Fonts();
        Layer();

        AtomicWriteAllText(Path.Combine(GameDir, "Enhanced-Host.bat"), "@echo off\r\ncd /d \"%~dp0System\"\r\nstart \"\" Game.exe 1_Shreks_Swamp?Game=Enhanced.EnhancedGame?listen?EnhWait=1\r\n", Encoding.ASCII);
        AtomicWriteAllText(Path.Combine(GameDir, "Enhanced-Join.bat"), "@echo off\r\ncd /d \"%~dp0System\"\r\nset /p HOST=Host address (for example 192.168.0.5:7777): \r\nstart \"\" Game.exe %HOST%\r\n", Encoding.ASCII);
        Log("Shrek 2 Enhanced is installed. Start the game as usual: the main menu has Single player and Co-op mode (create a game, or find one on the network). The two launchers are kept for a direct start.");
    }

    // Game.exe of the 1C edition is a 32-bit program that may use only 2 GB: the large-address-aware flag lets it use 4 GB on 64-bit Windows (the HD
    // textures and the mod need the room). A manifest next to the exe makes it DPI-aware, so Windows does not stretch its window at 125 % and more.
    void GameExe()
    {
        string exe = P("Game.exe");
        if (!File.Exists(exe)) return;
        string eh = Sha(exe);
        byte[] bytes = File.ReadAllBytes(exe);
        int pe = BitConverter.ToInt32(bytes, 0x3c);
        int chars = BitConverter.ToUInt16(bytes, pe + 22);
        if ((chars & 0x20) != 0) Log("Game.exe is already large address aware.");
        else if (eh == StockExe)
        {
            if (!File.Exists(exe + Bak)) AtomicCopy(exe, exe + Bak);
            int nc = chars | 0x20;
            bytes[pe + 22] = (byte)(nc & 0xFF);
            bytes[pe + 23] = (byte)((nc >> 8) & 0xFF);
            AtomicWriteAllBytes(exe, bytes);
            Log("Game.exe: large address aware (4 GB instead of 2 GB).");
        }
        else Log("Game.exe is not the 1C edition this installer knows: the memory flag is left alone.");
        string manifest = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n" +
            "<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\"><application xmlns=\"urn:schemas-microsoft-com:asm.v3\"><windowsSettings>" +
            "<dpiAware xmlns=\"http://schemas.microsoft.com/SMI/2005/WindowsSettings\">true/pm</dpiAware>" +
            "<dpiAwareness xmlns=\"http://schemas.microsoft.com/SMI/2016/WindowsSettings\">PerMonitorV2</dpiAwareness>" +
            "</windowsSettings></application></assembly>";
        AtomicWriteAllText(P("Game.exe.manifest"), manifest + "\r\n", new UTF8Encoding(true));
        Log("Game.exe.manifest: DPI aware.");
    }

    // The engine falls back to the default map "HP-Test.unr" (not in the game) when the host goes away; with the front-end book as the default map the
    // player lands in the main menu instead. The menus of the mod live in the mod's own game class. Two files hold both lines: the install's Default.ini
    // and the player's Game.ini (made from it).
    void IniEdits()
    {
        string[][] edits = IniLines;
        foreach (string m in MapFiles())
        {
            if (!File.Exists(m)) continue;
            string text = File.ReadAllText(m);
            foreach (string[] e in edits)
            {
                if (text.Contains(e[0]))
                {
                    if (!File.Exists(m + Bak)) AtomicCopy(m, m + Bak);
                    text = text.Replace(e[0], e[1]);
                    AtomicWriteAllText(m, text);
                    Log(Path.GetFileName(m) + ": " + e[2] + ".");
                }
            }
        }
    }

    // The key bindings a NEW profile starts with (DefUser.ini of the game): the stock Enter key is "Use | Fire", so it also punched; here it is left unbound. Profiles that
    // already exist (the player's User.ini) are not touched.
    void DefaultKeys()
    {
        string f = P("DefUser.ini");
        if (!File.Exists(f)) return;
        Encoding enc = Encoding.GetEncoding(1252);
        string text = File.ReadAllText(f, enc);
        string next = Regex.Replace(text, @"(?m)^Enter=Use \| Fire[ \t]*(\r?)$", "Enter=$1");
        if (next == text) return;
        if (!File.Exists(f + Bak)) AtomicCopy(f, f + Bak);
        AtomicWriteAllText(f, next, enc);
        Log("DefUser.ini: Enter is unbound (it no longer punches) in a new profile.");
    }

    // The local-network search asks the broadcast address of every network this PC is in (Radmin VPN, Hamachi, ZeroTier and the like have an adapter of
    // their own); the addresses go into the player's User.ini.
    static List<string> Broadcasts()
    {
        SortedDictionary<string, bool> found = new SortedDictionary<string, bool>(StringComparer.Ordinal);
        foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            IPInterfaceProperties props;
            try { props = ni.GetIPProperties(); } catch { continue; }
            foreach (UnicastIPAddressInformation u in props.UnicastAddresses)
            {
                if (u.Address.AddressFamily != AddressFamily.InterNetwork || u.IPv4Mask == null) continue;
                byte[] a = u.Address.GetAddressBytes(), m = u.IPv4Mask.GetAddressBytes();
                if (a[0] == 127 || (a[0] == 169 && a[1] == 254)) continue;
                int prefix = 0;
                for (int i = 0; i < 4; i++) for (int b = 7; b >= 0; b--) if ((m[i] & (1 << b)) != 0) prefix++;
                if (prefix < 8 || prefix > 30) continue;
                long ip = ((long)a[0] << 24) | ((long)a[1] << 16) | ((long)a[2] << 8) | a[3];
                long bc = ip | ((1L << (32 - prefix)) - 1);
                found[((bc >> 24) & 255) + "." + ((bc >> 16) & 255) + "." + ((bc >> 8) & 255) + "." + (bc & 255)] = true;
            }
        }
        return new List<string>(found.Keys);
    }

    void Beacon()
    {
        string userIni = Path.Combine(Path.Combine(DocsDir, "Shrek 2"), "User.ini");
        if (!File.Exists(userIni)) return;
        string text = File.ReadAllText(userIni);
        text = Regex.Replace(text, "(?ms)\\r?\\n\\[Enhanced\\.EnhancedLanBeacon\\].*?(?=\\r?\\n\\[|\\z)", "");
        List<string> targets = Broadcasts();
        if (targets.Count == 0) return;
        StringBuilder sb = new StringBuilder(text.TrimEnd());
        sb.Append("\r\n[Enhanced.EnhancedLanBeacon]\r\n");
        for (int i = 0; i < targets.Count; i++) sb.Append((i > 0 ? "\r\n" : "") + "ExtraTargets=" + targets[i]);
        sb.Append("\r\n");
        AtomicWriteAllText(userIni, sb.ToString());
        Log("User.ini: the network search will also ask: " + string.Join(", ", targets.ToArray()));
    }

    // The 61 localized textures get their English versions. A patch holds the new export table offset and the bytes appended to the package; it is
    // applied only to the exact file it was made for (SHA-256 checked).
    void EnglishTextures()
    {
        int done = 0;
        string dir = Path.Combine(Files, "textures-en");
        if (!Directory.Exists(dir)) throw new Exception("The folder files\\textures-en is missing next to the setup.");
        foreach (string pf in Directory.GetFiles(dir, "*.patch"))
        {
            string name = Path.GetFileName(pf);
            name = name.Substring(0, name.Length - ".patch".Length);
            string target = Path.Combine(TexDir, name);
            if (!File.Exists(target)) { Log("Texture package " + name + " is not in the game: skipped."); continue; }
            byte[] p = File.ReadAllBytes(pf);
            if (p.Length < 44 || Encoding.ASCII.GetString(p, 0, 4) != "ENTX") throw new Exception(Path.GetFileName(pf) + " is not a texture patch.");
            string want = BitConverter.ToString(p, 4, 32).Replace("-", "");
            if (Sha(target) != want) { Log(name + " is not the file of the Russian edition this patch was made for: left as it is."); continue; }
            uint tab = BitConverter.ToUInt32(p, 36);
            int len = (int)BitConverter.ToUInt32(p, 40);
            if (len < 0 || len > p.Length - 44) throw new Exception(Path.GetFileName(pf) + " has an invalid payload length.");
            byte[] original = File.ReadAllBytes(target);
            if (original.Length < 28) throw new Exception(name + " is too short to be a texture package.");
            Array.Copy(BitConverter.GetBytes(tab), 0, original, 24, 4);
            MemoryStream output = new MemoryStream(original.Length + len);
            output.Write(original, 0, original.Length);
            output.Write(p, 44, len);
            AtomicCopy(target, target + Bak);
            AtomicWriteAllBytes(target, output.ToArray());
            done++;
        }
        Log("English textures: " + done + " packages patched.");
    }

    void HdStage(string pack)
    {
        string tmp = null;
        try
        {
            string dir;
            if (Directory.Exists(pack)) dir = HdPack.FindDir(pack);
            else
            {
                tmp = Path.Combine(Path.GetTempPath(), "Shrek2HD-" + Guid.NewGuid().ToString("N").Substring(0, 8));
                Directory.CreateDirectory(tmp);
                Log("Unpacking the HD pack (about 1.7 GB, a minute or two)...");
                HdPack.Extract(pack, tmp);
                dir = tmp;
            }
            if (dir == null) throw new Exception("the pack does not contain Shrek 2.TFCMapping and LocalMips_0.tfc");
            Log("Writing the HD textures into the game's packages...");
            HdPatcher.Apply(TexDir, dir, Log, BeforeChange);
        }
        finally
        {
            if (tmp != null) { try { Directory.Delete(tmp, true); } catch { } }
        }
    }

    // The headings of the mod's pages use a font entry (ShrekTitle) of SAPFont: Tahoma, or the Shrek face when the player has put Shrekrusbyme.ttf into System.
    void Fonts()
    {
        string face = File.Exists(P("Shrekrusbyme.ttf")) ? "Shrek" : "Tahoma";
        foreach (string f in FontFiles())
        {
            if (!File.Exists(f)) continue;
            string text = File.ReadAllText(f);
            text = Regex.Replace(text, "(?m)\\r?\\nShrekTitle(Size)?=.*", "");
            if (!File.Exists(f + Bak)) AtomicCopy(f, f + Bak);
            text = text.TrimEnd() + "\r\nShrekTitle=" + face + "\r\nShrekTitleSize=29";
            AtomicWriteAllText(f, text);
        }
        Log("Fonts: ShrekTitle = " + face);
    }

    // The engine layer: a Direct3D 8 library that stands in front of Windows' own (animation sync of the players, hardware tuning, prefetch,
    // anti-aliasing). The game has no d3d8.dll of its own, so the real one is a copy of the Windows one under the name d3d8_real.dll.
    void Layer()
    {
        string src = Path.Combine(Path.Combine(Files, "layer"), "d3d8.dll");
        if (!File.Exists(src)) throw new Exception("files\\layer\\d3d8.dll is missing next to the setup.");
        string dll = P("d3d8.dll"), real = P("d3d8_real.dll"), mark = P("d3d8_real.dll.enhanced-made"), bak = P("d3d8.dll.enhanced-backup");
        if (!File.Exists(real))
        {
            string win = Path.Combine(Environment.GetEnvironmentVariable("WINDIR") ?? "C:\\Windows", "SysWOW64\\d3d8.dll");
            if (!File.Exists(win)) win = Path.Combine(Environment.GetEnvironmentVariable("WINDIR") ?? "C:\\Windows", "System32\\d3d8.dll");
            if (!File.Exists(win)) throw new Exception("Windows Direct3D 8 library (d3d8.dll) not found.");
            AtomicCopy(win, real);
            AtomicWriteAllBytes(mark, new byte[0]);
        }
        if (File.Exists(bak) && IsOurLayer(bak)) DeleteFile(bak);   // left by an install of an older version of this setup
        if (File.Exists(dll) && !IsOurLayer(dll) && !File.Exists(bak)) AtomicCopy(dll, bak);
        AtomicCopy(src, dll);
        if (Sha(dll) != Sha(src)) throw new Exception("d3d8.dll was not copied intact (an antivirus may have removed it); the mod cannot start without it.");
        Log("Engine layer (d3d8.dll) installed.");
    }
}

// the three changes to Engine.dll (the same bytes as tools\patch_engine.py; every address is checked against the original code)
static class EnginePatch
{
    const long ImageBase = 0x10300000;

    static int Off(long va) { return (int)(va - ImageBase); }
    static byte Rel8(long next, long target)
    {
        long d = target - next;
        if (d < -128 || d > 127) throw new Exception("jump out of range");
        return (byte)((d + 256) % 256);
    }
    static byte[] Rel32(long next, long target) { return BitConverter.GetBytes((int)(target - next)); }
    static byte[] Hex(string s)
    {
        byte[] b = new byte[s.Length / 2];
        for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(s.Substring(2 * i, 2), 16);
        return b;
    }
    static byte[] Cat(params string[] hex)
    {
        List<byte> l = new List<byte>();
        foreach (string h in hex) l.AddRange(Hex(h));
        return l.ToArray();
    }
    static bool Same(byte[] data, int off, byte[] bytes)
    {
        for (int i = 0; i < bytes.Length; i++) if (data[off + i] != bytes[i]) return false;
        return true;
    }

    public static byte[] Apply(byte[] data)
    {
        long START = 0x10436e90, CAVE = 0x10436eb0, SKIP = 0x10436ee8, RESUME = 0x10436ea6;
        long TICK_JZ = 0x10422e3f, TICK_SKIP = 0x10422fd8, TICK_NEXT = 0x10422e45, PAD = 0x10421800;
        byte[] origStart = Cat("8b5140", "8b423c", "8b4070", "83f803", "744a", "83f801", "7545");
        byte[] origCave = Cat("683d020000", "6808467410", "6818467410", "ff151c539610");
        byte[] origJz = Hex("0f8493010000");
        if (!Same(data, Off(START), origStart) || !Same(data, Off(CAVE), origCave) || !Same(data, Off(TICK_JZ), origJz))
            throw new Exception("The code of Engine.dll is not the expected one: not patching.");
        for (int i = 0; i < 23; i++) if (data[Off(PAD) + i] != 0xcc) throw new Exception("The padding for the patch is not free: not patching.");

        // 1. the start of ULevel::TickNetClient
        List<byte> c = new List<byte>();
        long a = START;
        c.AddRange(Hex("8b5140")); c.AddRange(Hex("85d2"));
        c.Add(0x74); c.Add(Rel8(a + c.Count + 1, SKIP));
        c.AddRange(Hex("8b523c")); c.AddRange(Hex("85d2"));
        c.Add(0x74); c.Add(Rel8(a + c.Count + 1, SKIP));
        long jmpAt = a + c.Count;
        c.Add(0xe9); c.AddRange(Rel32(jmpAt + 5, CAVE));
        while (c.Count < origStart.Length) c.Add(0x90);
        Array.Copy(c.ToArray(), 0, data, Off(START), origStart.Length);

        // the cave in the body of an assert on an error path
        c = new List<byte>();
        a = CAVE;
        c.AddRange(Hex("837a7001"));
        c.Add(0x75); c.Add(Rel8(a + c.Count + 1, SKIP));
        c.AddRange(Hex("8b5144")); c.AddRange(Hex("83ba3c01000000"));
        c.Add(0x75); c.Add(Rel8(a + c.Count + 1, SKIP));
        c.Add(0xeb); c.Add(Rel8(a + c.Count + 1, RESUME));
        while (c.Count < origCave.Length) c.Add(0x90);
        Array.Copy(c.ToArray(), 0, data, Off(CAVE), origCave.Length);

        // 3. UGameEngine::Tick: no tick of the current level while a level is pending
        c = new List<byte>();
        a = PAD;
        c.Add(0x0f); c.Add(0x84); c.AddRange(Rel32(a + c.Count + 4, TICK_SKIP));
        c.AddRange(Hex("39ba3c010000"));
        c.Add(0x0f); c.Add(0x85); c.AddRange(Rel32(a + c.Count + 4, TICK_SKIP));
        c.Add(0xe9); c.AddRange(Rel32(a + c.Count + 4, TICK_NEXT));
        Array.Copy(c.ToArray(), 0, data, Off(PAD), c.Count);
        List<byte> j = new List<byte>();
        j.Add(0xe9); j.AddRange(Rel32(TICK_JZ + 5, PAD)); j.Add(0x90);
        Array.Copy(j.ToArray(), 0, data, Off(TICK_JZ), 6);
        return data;
    }
}

// the player's own copy of the HD pack: ShrekHD.zip or the folder it was unpacked to
static class HdPack
{
    public static string FindDir(string root)
    {
        if (File.Exists(Path.Combine(root, "Shrek 2.TFCMapping")) && File.Exists(Path.Combine(root, "LocalMips_0.tfc"))) return root;
        foreach (string d in Directory.GetDirectories(root))
        {
            string r = FindDir(d);
            if (r != null) return r;
        }
        return null;
    }

    public static bool Ok(string path)
    {
        try
        {
            if (string.IsNullOrEmpty(path)) return false;
            if (Directory.Exists(path)) return FindDir(path) != null;
            if (!File.Exists(path)) return false;
            using (System.IO.Compression.ZipArchive z = System.IO.Compression.ZipFile.OpenRead(path))
            {
                bool map = false, tfc = false;
                foreach (System.IO.Compression.ZipArchiveEntry e in z.Entries)
                {
                    if (e.Name == "Shrek 2.TFCMapping") map = true;
                    if (e.Name == "LocalMips_0.tfc") tfc = true;
                }
                return map && tfc;
            }
        }
        catch { return false; }
    }

    // only the two files that are needed
    public static void Extract(string zip, string dest)
    {
        using (System.IO.Compression.ZipArchive z = System.IO.Compression.ZipFile.OpenRead(zip))
        {
            foreach (System.IO.Compression.ZipArchiveEntry e in z.Entries)
                if (e.Name == "Shrek 2.TFCMapping" || e.Name == "LocalMips_0.tfc") e.ExtractToFile(Path.Combine(dest, e.Name), true);
        }
    }
}
