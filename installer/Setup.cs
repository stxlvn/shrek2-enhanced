// Shrek 2 Enhanced: setup program. Finds the installed Russian (1C) edition of Shrek 2, lets the player choose the set of textures, and puts the mod
// into the game's folder (Installer.cs). The files of the mod lie in the folder "files" next to this program; nothing is downloaded.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

class Setup : Form
{
    static bool ru = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ru";
    static string T(string en, string rus) { return ru ? rus : en; }

    const int PicW = 468;   // the picture (514 x 595) scaled to the window's height of 542 px

    ComboBox games = new ComboBox();
    Label status = new Label();
    RadioButton texRu = new RadioButton();
    RadioButton texHd = new RadioButton();
    TextBox hdPath = new TextBox();
    Button hdBrowse = new Button();
    CheckBox layer = new CheckBox();
    Button install = new Button();
    Button remove = new Button();
    Button browse = new Button();
    TextBox log = new TextBox();

    static string FilesDir() { return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "files"); }

    static string DocsDir()
    {
        string d = Environment.GetEnvironmentVariable("SHREK2_SETUP_DOCS");
        return string.IsNullOrEmpty(d) ? Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) : d;
    }

    static bool IsAdmin()
    {
        try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
        catch { return false; }
    }

    static bool Writable(string gameDir)
    {
        try
        {
            string t = Path.Combine(Path.Combine(gameDir, "System"), ".enhanced-write-test");
            File.WriteAllBytes(t, new byte[0]);
            File.Delete(t);
            return true;
        }
        catch { return false; }
    }

    // Command line (silent install, also used by the tests): Setup.exe /silent /dir "<game folder>" [/textures ru|enhd] [/hdpack <zip or folder>] [/uninstall]   (/nolayer is refused: the mod cannot start without the layer) [/log file]
    // Setup.exe /find /log file   writes the Shrek 2 folders found on this PC.
    static int Headless(string[] a)
    {
        string dir = "", tex = "ru", logFile = "", mode = "", hdpack = "";
        bool nolayer = false, un = false;
        for (int i = 0; i < a.Length; i++)
        {
            string x = a[i].ToLowerInvariant();
            if (x == "/hdpack" && i + 1 < a.Length) hdpack = a[++i];
            else if (x == "/dir" && i + 1 < a.Length) dir = a[++i];
            else if (x == "/textures" && i + 1 < a.Length) tex = a[++i].ToLowerInvariant();
            else if (x == "/log" && i + 1 < a.Length) logFile = a[++i];
            else if (x == "/nolayer") nolayer = true;
            else if (x == "/uninstall") un = true;
            else if (x == "/find") mode = "find";
            else if (x == "/silent") mode = "silent";
        }
        StringBuilder log = new StringBuilder();
        int code = 0;
        if (mode == "find")
        {
            foreach (string p in Find()) log.AppendLine(p);
        }
        else
        {
            if (dir == "") { log.AppendLine("Silent mode requires an explicit /dir; nothing was changed."); code = 2; }
            else if (!IsGame(dir)) { log.AppendLine("Shrek 2 not found; give /dir"); code = 2; }
            else
            {
                Installer ins = new Installer();
                ins.GameDir = dir.TrimEnd('\\');
                ins.DocsDir = DocsDir();
                ins.Files = FilesDir();
                ins.Log = delegate (string s) { log.AppendLine(s); };
                try
                {
                    if (un) ins.Uninstall();
                    else ins.Install(tex, hdpack, !nolayer);
                }
                catch (Exception ex) { log.AppendLine("Error: " + ex.Message); code = 1; }
            }
        }
        if (logFile != "") File.WriteAllText(logFile, log.ToString() + "exit " + code + "\r\n");
        return code;
    }

    [STAThread]
    static int Main(string[] a)
    {
        foreach (string x in a) if (x.ToLowerInvariant() == "/silent" || x.ToLowerInvariant() == "/find") return Headless(a);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        if (a.Length == 2 && a[0].ToLowerInvariant() == "/shot")
        {
            // a picture of the window without showing it (tests)
            Setup f = new Setup();
            f.StartPosition = FormStartPosition.Manual;
            f.Location = new Point(-20000, -20000);
            f.ShowInTaskbar = false;
            f.Show();
            Application.DoEvents();
            using (Bitmap bmp = new Bitmap(f.ClientSize.Width, f.ClientSize.Height))
            {
                f.DrawToBitmap(bmp, new Rectangle(0, 0, bmp.Width, bmp.Height));
                bmp.Save(a[1], System.Drawing.Imaging.ImageFormat.Png);
            }
            return 0;
        }
        // Program Files is not writable for an ordinary program: one restart with the rights of an administrator, only when the game is there
        if (!IsAdmin())
        {
            List<string> found = Find();
            if (found.Count > 0 && !Writable(found[0]))
            {
                try
                {
                    System.Diagnostics.ProcessStartInfo psi = new System.Diagnostics.ProcessStartInfo(Application.ExecutablePath);
                    psi.UseShellExecute = true;
                    psi.Verb = "runas";
                    System.Diagnostics.Process.Start(psi);
                    return 0;
                }
                catch { }   // the person said no to the question of Windows: the window opens anyway and says what is needed
            }
        }
        Application.Run(new Setup());
        return 0;
    }

    Setup()
    {
        Text = "Shrek 2 Enhanced";
        ClientSize = new Size(640 + PicW, 542);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 9f);
        MakeBackground();

        Label head = new Label();
        head.Text = "Shrek 2 Enhanced";
        head.Font = new Font("Segoe UI", 20f, FontStyle.Bold);
        head.ForeColor = Color.FromArgb(255, 36, 70, 24);
        head.BackColor = Color.Transparent;
        head.SetBounds(16, 10, 600, 34);
        Controls.Add(head);

        Label l1 = new Label();
        l1.Text = T("Shrek 2 folder (the one that contains System):", "Папка с игрой Shrek 2 (та, где лежит папка System):");
        l1.SetBounds(16, 54, 600, 18);
        Controls.Add(l1);
        games.DropDownStyle = ComboBoxStyle.DropDown;
        games.SetBounds(16, 76, 500, 24);
        games.TextChanged += delegate { Check(); };
        Controls.Add(games);
        browse.Text = T("Browse...", "Обзор...");
        browse.SetBounds(526, 75, 98, 26);
        browse.Click += delegate { Browse(); };
        Controls.Add(browse);
        status.SetBounds(16, 104, 608, 36);
        Controls.Add(status);

        GroupBox gb = new GroupBox();
        gb.Text = T("Textures", "Текстуры");
        gb.SetBounds(16, 146, 608, 146);
        Controls.Add(gb);
        texRu.Text = T("Russian: the game's own textures (posters, signs, story book and loading tiles stay in Russian)", "Русские: родные текстуры игры (плакаты, вывески, книга и экраны загрузки остаются на русском)");
        texRu.Checked = true;
        texRu.SetBounds(14, 24, 580, 36);
        texHd.Text = T("English HD: the English textures in high resolution, from your own copy of the ShrekHD pack (about 1.7 GB are read; the game's files grow by about 2 GB)", "Английские HD: английские текстуры в высоком разрешении, из вашей копии пака ShrekHD (читается около 1,7 ГБ, файлы игры вырастут примерно на 2 ГБ)");
        texHd.SetBounds(14, 62, 580, 36);
        texHd.CheckedChanged += delegate { hdPath.Enabled = hdBrowse.Enabled = texHd.Checked; };
        hdPath.SetBounds(34, 104, 460, 24);
        hdPath.Enabled = false;
        hdBrowse.Text = T("Pack...", "Пак...");
        hdBrowse.SetBounds(502, 103, 92, 26);
        hdBrowse.Enabled = false;
        hdBrowse.Click += delegate { BrowsePack(); };
        gb.Controls.Add(texRu);
        gb.Controls.Add(texHd);
        gb.Controls.Add(hdPath);
        gb.Controls.Add(hdBrowse);

        layer.Text = T("The engine layer (d3d8.dll) is always installed: the mod's scripts need it (smooth animation for the second player, hardware tuning, faster loading)", "Слой движка (d3d8.dll) ставится всегда: он нужен скриптам мода (плавная анимация второго игрока, подбор настроек под железо, быстрая загрузка)");
        layer.Checked = true;
        layer.Enabled = false;
        layer.SetBounds(20, 300, 604, 34);
        Controls.Add(layer);

        Label note = new Label();
        note.Text = T("All players of one co-op game should install the same set of textures.", "Все игроки одной кооперативной игры должны ставить один и тот же набор текстур.");
        note.ForeColor = Color.DimGray;
        note.SetBounds(20, 336, 604, 18);
        Controls.Add(note);

        install.Text = T("Install", "Установить");
        install.SetBounds(16, 362, 130, 32);
        install.Click += delegate { Run(false); };
        Controls.Add(install);
        remove.Text = T("Remove", "Удалить");
        remove.SetBounds(156, 362, 130, 32);
        remove.Click += delegate { Run(true); };
        Controls.Add(remove);

        log.Multiline = true;
        log.ReadOnly = true;
        log.ScrollBars = ScrollBars.Vertical;
        log.SetBounds(16, 404, 608, 122);
        log.Font = new Font("Consolas", 9f);
        Controls.Add(log);

        // the picture takes the left strip of the window; the controls were laid out for a 640 px wide window and move to the right of it
        foreach (Control c in Controls)
        {
            c.Left += PicW;
            if (c is Label || c is GroupBox || c is CheckBox) c.BackColor = Color.Transparent;
        }
        texRu.BackColor = Color.Transparent;
        texHd.BackColor = Color.Transparent;
        foreach (string p in Find()) games.Items.Add(p);
        if (games.Items.Count > 0) games.SelectedIndex = 0;
        Check();
    }

    // The picture (a frame of Shrek with its caption) fills the left strip of the window, the controls stand on a pale page to the right of it.
    void MakeBackground()
    {
        try
        {
            using (Stream s = typeof(Setup).Assembly.GetManifestResourceStream("bg.png"))
            using (Image src = Image.FromStream(s))
            {
                Bitmap bmp = new Bitmap(ClientSize.Width, ClientSize.Height);
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.FromArgb(255, 250, 244, 222));
                    g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    g.DrawImage(src, 0, 0, PicW, bmp.Height);
                    using (Pen edge = new Pen(Color.FromArgb(255, 70, 100, 40), 3))
                        g.DrawLine(edge, PicW, 0, PicW, bmp.Height);
                }
                BackgroundImage = bmp;
                BackgroundImageLayout = ImageLayout.None;
            }
        }
        catch { }
    }

    static bool IsGame(string dir)
    {
        try { return !string.IsNullOrEmpty(dir) && File.Exists(Path.Combine(dir, "System\\Engine.dll")) && File.Exists(Path.Combine(dir, "System\\Game.exe")); }
        catch { return false; }
    }

    static List<string> Find()
    {
        List<string> found = new List<string>();
        List<string> tries = new List<string>();
        foreach (RegistryView view in new RegistryView[] { RegistryView.Registry32, RegistryView.Registry64 })
        {
            try
            {
                using (RegistryKey hk = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
                {
                    foreach (string sub in new string[] { "SOFTWARE\\Activision\\Shrek 2", "SOFTWARE\\WOW6432Node\\Activision\\Shrek 2" })
                    {
                        using (RegistryKey k = hk.OpenSubKey(sub))
                            if (k != null) tries.Add(Convert.ToString(k.GetValue("InstallPath")));
                    }
                }
            }
            catch { }
        }
        string[] rel = { "Activision\\Shrek 2", "Shrek 2", "Games\\Shrek 2", "1C\\Shrek 2", "Игры\\Shrek 2", "Игры\\Shrek 2 (1C)", "Games\\Shrek 2 (1C)" };
        foreach (DriveInfo d in DriveInfo.GetDrives())
        {
            if (d.DriveType != DriveType.Fixed || !d.IsReady) continue;
            foreach (string r in rel)
            {
                tries.Add(Path.Combine(d.Name, r));
                tries.Add(Path.Combine(Path.Combine(d.Name, "Program Files (x86)"), r));
                tries.Add(Path.Combine(Path.Combine(d.Name, "Program Files"), r));
            }
        }
        foreach (string t in tries)
        {
            if (string.IsNullOrEmpty(t)) continue;
            string p = t.TrimEnd('\\');
            if (IsGame(p) && !found.Contains(p)) found.Add(p);
        }
        return found;
    }

    void Browse()
    {
        FolderBrowserDialog d = new FolderBrowserDialog();
        d.Description = T("Choose the Shrek 2 folder (it contains the System folder)", "Выберите папку игры Shrek 2 (в ней лежит папка System)");
        if (d.ShowDialog(this) == DialogResult.OK) games.Text = d.SelectedPath;
    }

    void BrowsePack()
    {
        OpenFileDialog d = new OpenFileDialog();
        d.Title = T("Choose ShrekHD.zip (or type the folder it was unpacked to)", "Выберите ShrekHD.zip (или впишите папку, куда он распакован)");
        d.Filter = "ShrekHD (*.zip)|*.zip|*.*|*.*";
        if (d.ShowDialog(this) == DialogResult.OK) hdPath.Text = d.FileName;
    }

    void Check()
    {
        string dir = games.Text.Trim().TrimEnd('\\');
        bool ready = false;
        bool installed = false;
        if (!IsGame(dir))
        {
            status.ForeColor = Color.Firebrick;
            status.Text = games.Items.Count == 0
                ? T("Shrek 2 was not found on this PC. Press Browse and choose its folder.", "Shrek 2 на этом компьютере не найден. Нажмите «Обзор» и укажите папку игры.")
                : T("This folder does not contain a Shrek 2 installation (System\\Engine.dll is missing).", "В этой папке нет игры Shrek 2 (нет System\\Engine.dll).");
        }
        else
        {
            string h = Installer.Sha(Path.Combine(dir, "System\\Engine.dll"));
            installed = File.Exists(Path.Combine(dir, "System\\Enhanced.u"));
            if (h == Installer.StockEngine || h == Installer.PatchedEngine)
            {
                ready = true;
                status.ForeColor = Color.DarkGreen;
                status.Text = installed
                    ? T("Shrek 2 (Russian 1C edition) found. Shrek 2 Enhanced is already installed here: Install updates it, Remove puts the original files back.", "Shrek 2 (русское издание 1C) найден. Shrek 2 Enhanced уже установлен: «Установить» обновит его, «Удалить» вернёт исходные файлы.")
                    : T("Shrek 2 (Russian 1C edition) found.", "Shrek 2 (русское издание 1C) найден.");
            }
            else
            {
                status.ForeColor = Color.Firebrick;
                status.Text = T("This is not the Russian 1C edition of Shrek 2 (Engine.dll differs). Nothing will be changed.", "Это не русское издание 1C (Engine.dll отличается). Ничего менять не будем.");
            }
        }
        install.Enabled = ready;
        remove.Enabled = ready && installed;
    }

    void Add(string s)
    {
        if (InvokeRequired) { BeginInvoke(new Action<string>(Add), s); return; }
        log.AppendText(s + "\r\n");
    }

    void Run(bool uninstall)
    {
        string dir = games.Text.Trim().TrimEnd('\\');
        bool hd = !uninstall && texHd.Checked;
        string pack = hdPath.Text.Trim().Trim('"');
        if (hd && !HdPack.Ok(pack))
        {
            MessageBox.Show(this, T("The HD pack was not found there. Give the ShrekHD.zip file (or the folder it was unpacked to; it must hold \"Shrek 2.TFCMapping\" and LocalMips_0.tfc).", "Пак HD там не найден. Укажите файл ShrekHD.zip (или папку, куда он распакован: в ней должны лежать «Shrek 2.TFCMapping» и LocalMips_0.tfc)."), "Shrek 2 Enhanced");
            return;
        }
        if (!Writable(dir))
        {
            MessageBox.Show(this, T("The game's folder cannot be written to. Close this window and start the setup again with a right click, Run as administrator.", "В папку игры нельзя писать. Закройте окно и запустите установщик правой кнопкой мыши: «Запуск от имени администратора»."), "Shrek 2 Enhanced");
            return;
        }
        bool withLayer = true;   // the mod cannot start without the layer
        install.Enabled = false; remove.Enabled = false; browse.Enabled = false; games.Enabled = false; texHd.Enabled = false; texRu.Enabled = false; hdBrowse.Enabled = false; hdPath.Enabled = false;
        log.Clear();
        Add(uninstall ? T("Removing...", "Удаление...") : T("Installing...", "Установка..."));
        Installer ins = new Installer();
        ins.GameDir = dir;
        ins.DocsDir = DocsDir();
        ins.Files = FilesDir();
        ins.Log = new Action<string>(Add);
        Thread t = new Thread(delegate ()
        {
            bool ok = true;
            try
            {
                if (uninstall) ins.Uninstall();
                else ins.Install(hd ? "enhd" : "ru", pack, withLayer);
            }
            catch (Exception ex)
            {
                ok = false;
                Add(T("Error: ", "Ошибка: ") + ex.Message);
            }
            Done(ok);
        });
        t.IsBackground = true;
        t.Start();
    }

    void Done(bool ok)
    {
        if (InvokeRequired) { BeginInvoke(new Action<bool>(Done), ok); return; }
        Add(ok ? T("Done.", "Готово.") : T("Failed.", "Не получилось."));
        browse.Enabled = true; games.Enabled = true; texHd.Enabled = true; texRu.Enabled = true;
        hdPath.Enabled = hdBrowse.Enabled = texHd.Checked;
        Check();
    }
}
