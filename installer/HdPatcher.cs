// HD textures for the Russian 1C install, from the player's own copy of the ShrekHD pack (LocalMips_0.tfc + "Shrek 2.TFCMapping").
// Stock UE2.5 packages (version 129) cannot point at an external mip file, so the pack's ready mips are written into the texture exports of the .utx
// files: the new export bytes are appended to the package, the export table is rewritten at the end and the header points to it. Everything else in the
// file stays as it was. The original of every package that is changed is kept as <name>.enhanced-backup.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

class HdPatcher
{
    const char BS = '\\';

    class Export { public int Cls, Sup, Pkg, Name; public uint Flags; public int Size, Off; }
    class Mip { public int Off, S1, S2, W, H; }
    class Entry { public string Name; public List<Mip> Mips = new List<Mip>(); }
    class Prop { public string Name; public int Size, VPos; }

    class Pkg
    {
        public byte[] B;
        public List<string> Names = new List<string>();
        public List<int[]> Imports = new List<int[]>();   // package, class, outer, name
        public List<Export> Exports = new List<Export>();

        public static int Ci(byte[] b, ref int p)
        {
            int v = b[p++];
            int neg = v & 0x80;
            int r = v & 0x3f;
            if ((v & 0x40) != 0)
            {
                int sh = 6;
                while (true)
                {
                    int c = b[p++];
                    r |= (c & 0x7f) << sh;
                    sh += 7;
                    if ((c & 0x80) == 0) break;
                }
            }
            return neg != 0 ? -r : r;
        }

        public Pkg(string path)
        {
            B = File.ReadAllBytes(path);
            if (BitConverter.ToUInt32(B, 0) != 0x9E2A83C1) throw new Exception(path + " is not an Unreal package");
            int ver = BitConverter.ToUInt16(B, 4);
            int nc = BitConverter.ToInt32(B, 12), no = BitConverter.ToInt32(B, 16), ec = BitConverter.ToInt32(B, 20), eo = BitConverter.ToInt32(B, 24);
            int ic = BitConverter.ToInt32(B, 28), io = BitConverter.ToInt32(B, 32);
            if (ver < 64) throw new Exception(path + ": package version " + ver + " is not the one this installer knows");
            int p = no;
            for (int i = 0; i < nc; i++)
            {
                int l = Ci(B, ref p);
                string n = l > 0 ? Encoding.GetEncoding(28591).GetString(B, p, l - 1) : "";
                p += l + 4;
                Names.Add(n);
            }
            p = io;
            for (int i = 0; i < ic; i++)
            {
                int pk = Ci(B, ref p), cl = Ci(B, ref p);
                int outer = BitConverter.ToInt32(B, p); p += 4;
                int nm = Ci(B, ref p);
                Imports.Add(new int[] { pk, cl, outer, nm });
            }
            p = eo;
            for (int i = 0; i < ec; i++)
            {
                Export e = new Export();
                e.Cls = Ci(B, ref p); e.Sup = Ci(B, ref p);
                e.Pkg = BitConverter.ToInt32(B, p); p += 4;
                e.Name = Ci(B, ref p);
                e.Flags = BitConverter.ToUInt32(B, p); p += 4;
                e.Size = Ci(B, ref p);
                if (e.Size > 0) e.Off = Ci(B, ref p);
                Exports.Add(e);
            }
        }

        public string ClassName(int idx)
        {
            if (idx < 0) return Names[Imports[-idx - 1][3]];
            if (idx > 0) return Names[Exports[idx - 1].Name];
            return "Class";
        }

        public string Path(int i)
        {
            Export e = Exports[i];
            List<string> parts = new List<string>();
            parts.Add(Names[e.Name]);
            int o = e.Pkg;
            while (o > 0) { Export e2 = Exports[o - 1]; parts.Add(Names[e2.Name]); o = e2.Pkg; }
            parts.Reverse();
            return string.Join(BS.ToString(), parts.ToArray());
        }
    }

    static byte[] Wci(int v)
    {
        bool neg = v < 0;
        int a = Math.Abs(v);
        int first = (neg ? 0x80 : 0) | (a & 0x3f);
        a >>= 6;
        List<byte> o = new List<byte>();
        if (a != 0) first |= 0x40;
        o.Add((byte)first);
        while (a != 0)
        {
            int c = a & 0x7f;
            a >>= 7;
            if (a != 0) c |= 0x80;
            o.Add((byte)c);
        }
        return o.ToArray();
    }

    static List<Prop> ParseProps(Pkg P, byte[] raw, out int end)
    {
        int[] sizes = { 1, 2, 4, 12, 16 };
        List<Prop> props = new List<Prop>();
        int p = 0;
        while (true)
        {
            int n = Pkg.Ci(raw, ref p);
            string name = P.Names[n];
            if (name == "None") { end = p; return props; }
            int info = raw[p++];
            int typ = info & 0xF, sc = (info >> 4) & 7;
            bool arr = (info & 0x80) != 0;
            if (typ == 10) Pkg.Ci(raw, ref p);
            int size;
            if (sc < 5) size = sizes[sc];
            else if (sc == 5) size = raw[p++];
            else if (sc == 6) { size = BitConverter.ToUInt16(raw, p); p += 2; }
            else { size = BitConverter.ToInt32(raw, p); p += 4; }
            if (typ == 3) size = 0;
            if (arr && typ != 3)
            {
                int a = raw[p];
                if (a < 0x80) p += 1;
                else if (a < 0xC0) p += 2;
                else p += 4;
            }
            Prop pr = new Prop();
            pr.Name = name; pr.Size = size; pr.VPos = p;
            props.Add(pr);
            p += size;
        }
    }

    static Prop Find(List<Prop> pr, string name)
    {
        foreach (Prop x in pr) if (x.Name == name) return x;
        return null;
    }

    static int GetProp(byte[] raw, List<Prop> pr, string name)
    {
        Prop x = Find(pr, name);
        if (x == null) return -1;
        return x.Size == 1 ? raw[x.VPos] : BitConverter.ToInt32(raw, x.VPos);
    }

    static void SetProp(byte[] raw, List<Prop> pr, string name, int val)
    {
        Prop x = Find(pr, name);
        if (x == null) return;
        if (x.Size == 1) raw[x.VPos] = (byte)val;
        else Array.Copy(BitConverter.GetBytes((uint)val), 0, raw, x.VPos, 4);
    }

    static int Log2(int v) { int n = 0; while (v > 1) { v >>= 1; n++; } return n; }

    static Dictionary<string, List<Entry>> LoadMapping(string path)
    {
        byte[] d = File.ReadAllBytes(path);
        int cnt = BitConverter.ToInt32(d, 8);
        int p = 12;
        Dictionary<string, List<Entry>> by = new Dictionary<string, List<Entry>>();
        for (int i = 0; i < cnt; i++)
        {
            int l = BitConverter.ToInt32(d, p); p += 4;
            Entry e = new Entry();
            e.Name = Encoding.GetEncoding(28591).GetString(d, p, l - 1); p += l;
            int n = BitConverter.ToInt32(d, p + 4); p += 8;
            int l2 = BitConverter.ToInt32(d, p); p += 4;
            p += l2;
            p += 4;
            for (int k = 0; k < n; k++)
            {
                Mip m = new Mip();
                m.Off = BitConverter.ToInt32(d, p + 4); m.S1 = BitConverter.ToInt32(d, p + 8); m.S2 = BitConverter.ToInt32(d, p + 12);
                m.W = BitConverter.ToInt32(d, p + 16); m.H = BitConverter.ToInt32(d, p + 20);
                p += 24;
                e.Mips.Add(m);
            }
            List<Entry> list;
            if (!by.TryGetValue(e.Name, out list)) { list = new List<Entry>(); by[e.Name] = list; }
            list.Add(e);
        }
        if (p != d.Length) throw new Exception("The mapping file of the pack is not in the format this installer knows");
        return by;
    }

    // the export of one texture: its properties (sizes and format changed), then the mips of the pack
    static byte[] BuildExport(Pkg P, Export e, Entry ent, FileStream tfc, long absStart, out string why)
    {
        why = null;
        byte[] raw = new byte[e.Size];
        Array.Copy(P.B, e.Off, raw, 0, e.Size);
        int pEnd;
        List<Prop> pr = ParseProps(P, raw, out pEnd);
        int fmt0 = GetProp(raw, pr, "Format");
        if (fmt0 != 3 && fmt0 != 7 && fmt0 != 8 && fmt0 != 5) { why = "format " + fmt0; return null; }
        Mip m0 = ent.Mips[0];
        int w = m0.W, h = m0.H, nf;
        if (m0.S1 * 2 == w * h) nf = 3;
        else if (m0.S1 == w * h) nf = 8;
        else if (m0.S1 == 4 * w * h) nf = 5;
        else { why = "bpp"; return null; }
        foreach (string nm in new string[] { "USize", "VSize", "UBits", "VBits", "Format" })
            if (Find(pr, nm) == null) { why = "no prop " + nm; return null; }
        byte[] props = new byte[pEnd];
        Array.Copy(raw, props, pEnd);
        SetProp(props, pr, "USize", w); SetProp(props, pr, "VSize", h);
        SetProp(props, pr, "UClamp", w); SetProp(props, pr, "VClamp", h);
        SetProp(props, pr, "UBits", Log2(w)); SetProp(props, pr, "VBits", Log2(h));
        SetProp(props, pr, "Format", nf);
        MemoryStream o = new MemoryStream();
        o.Write(props, 0, props.Length);
        byte[] cnt = Wci(ent.Mips.Count);
        o.Write(cnt, 0, cnt.Length);
        for (int i = 0; i < ent.Mips.Count; i++)
        {
            Mip m = ent.Mips[i];
            byte[] data = new byte[m.S1];
            tfc.Position = m.Off;
            int got = 0;
            while (got < data.Length) { int r = tfc.Read(data, got, data.Length - got); if (r <= 0) break; got += r; }
            if (got != data.Length) { why = "short read in the mip file"; return null; }
            int u = Math.Max(w >> i, 1), v = Math.Max(h >> i, 1);
            long skipAt = o.Length;
            o.Write(new byte[4], 0, 4);
            byte[] c = Wci(m.S1);
            o.Write(c, 0, c.Length);
            o.Write(data, 0, data.Length);
            long after = absStart + o.Length;
            long save = o.Position;
            o.Position = skipAt;
            o.Write(BitConverter.GetBytes((uint)after), 0, 4);
            o.Position = save;
            o.Write(BitConverter.GetBytes((uint)u), 0, 4);
            o.Write(BitConverter.GetBytes((uint)v), 0, 4);
            o.WriteByte((byte)(u > 0 ? Log2(u) : 0));
            o.WriteByte((byte)Log2(v));
        }
        return o.ToArray();
    }

    // Patches every .utx in texDir. packDir holds "Shrek 2.TFCMapping" and LocalMips_0.tfc. Returns the number of textures written.
    public static int Apply(string texDir, string packDir, Action<string> log, Action<string> beforeChange)
    {
        string mapPath = Path.Combine(packDir, "Shrek 2.TFCMapping");
        string tfcPath = Path.Combine(packDir, "LocalMips_0.tfc");
        if (!File.Exists(mapPath) || !File.Exists(tfcPath)) throw new Exception("The pack must contain \"Shrek 2.TFCMapping\" and LocalMips_0.tfc");
        Dictionary<string, List<Entry>> by = LoadMapping(mapPath);
        int total = 0, skipped = 0;
        using (FileStream tfc = File.OpenRead(tfcPath))
        {
            string[] files = Directory.GetFiles(texDir, "*.utx");
            Array.Sort(files, StringComparer.OrdinalIgnoreCase);
            foreach (string file in files)
            {
                Pkg P = new Pkg(file);
                List<int> tex = new List<int>();
                Dictionary<string, int> paths = new Dictionary<string, int>();
                for (int i = 0; i < P.Exports.Count; i++)
                {
                    if (P.ClassName(P.Exports[i].Cls) != "Texture") continue;
                    tex.Add(i);
                    string k = P.Path(i);
                    int n; paths.TryGetValue(k, out n); paths[k] = n + 1;
                }
                long baseLen = P.B.Length;
                MemoryStream buf = new MemoryStream();
                Dictionary<int, long[]> blobs = new Dictionary<int, long[]>();
                foreach (int i in tex)
                {
                    string path = P.Path(i);
                    List<Entry> ent;
                    if (!by.TryGetValue(path, out ent)) continue;
                    if (ent.Count > 1 || paths[path] > 1) { skipped++; continue; }
                    string why;
                    byte[] blob = BuildExport(P, P.Exports[i], ent[0], tfc, baseLen + buf.Length, out why);
                    if (blob == null) { skipped++; continue; }
                    blobs[i] = new long[] { baseLen + buf.Length, blob.Length };
                    buf.Write(blob, 0, blob.Length);
                }
                if (blobs.Count == 0) continue;
                long tabPos = baseLen + buf.Length;
                MemoryStream tab = new MemoryStream();
                for (int i = 0; i < P.Exports.Count; i++)
                {
                    Export e = P.Exports[i];
                    long off = e.Off, size = e.Size;
                    if (blobs.ContainsKey(i)) { off = blobs[i][0]; size = blobs[i][1]; }
                    byte[] t;
                    t = Wci(e.Cls); tab.Write(t, 0, t.Length);
                    t = Wci(e.Sup); tab.Write(t, 0, t.Length);
                    t = BitConverter.GetBytes(e.Pkg); tab.Write(t, 0, 4);
                    t = Wci(e.Name); tab.Write(t, 0, t.Length);
                    t = BitConverter.GetBytes(e.Flags); tab.Write(t, 0, 4);
                    t = Wci((int)size); tab.Write(t, 0, t.Length);
                    if (size > 0) { t = Wci((int)off); tab.Write(t, 0, t.Length); }
                }
                string backup = file + ".enhanced-backup";
                if (beforeChange != null) beforeChange(backup);
                if (!File.Exists(backup)) File.Copy(file, backup);
                Array.Copy(BitConverter.GetBytes((uint)tabPos), 0, P.B, 24, 4);
                string tmp = file + ".enhanced-tmp";
                try
                {
                    using (FileStream fs = File.Create(tmp))
                    {
                        fs.Write(P.B, 0, P.B.Length);
                        buf.WriteTo(fs);
                        tab.WriteTo(fs);
                    }
                    if (beforeChange != null) beforeChange(file);
                    Installer.ClearReadOnly(tmp);
                    if (File.Exists(file))
                    {
                        Installer.ClearReadOnly(file);
                        File.Replace(tmp, file, null);
                    }
                    else File.Move(tmp, file);
                }
                finally { Installer.SafeDelete(tmp); }
                total += blobs.Count;
                log(Path.GetFileName(file) + ": " + blobs.Count + " textures");
            }
        }
        log("HD textures: " + total + " written" + (skipped > 0 ? ", " + skipped + " left as they were" : ""));
        return total;
    }
}
