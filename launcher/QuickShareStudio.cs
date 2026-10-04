using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace QuickShareLauncher
{
    public class Program
    {
        private static HttpListener _listener;
        private static string _webRoot;
        private static int _port;
        private static NotifyIcon _trayIcon;
        private static Process _appProcess;
        private static bool _isRunning = true;
        private static Mutex _singleInstanceMutex;

        private static void Log(string msg)
        {
            try
            {
                string logPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launcher.log");
                File.AppendAllText(logPath, DateTime.Now + ": " + msg + "\n");
            }
            catch { }
        }

        private static string GetActivePortFilePath()
        {
            string appData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "QuickShareStudio"
            );
            if (!Directory.Exists(appData)) Directory.CreateDirectory(appData);
            return Path.Combine(appData, "active_port.txt");
        }

        private static void SaveActivePort(int port)
        {
            try
            {
                File.WriteAllText(GetActivePortFilePath(), port.ToString());
            }
            catch { }
        }

        private static int ReadActivePort()
        {
            try
            {
                string path = GetActivePortFilePath();
                if (File.Exists(path))
                {
                    string txt = File.ReadAllText(path).Trim();
                    int p;
                    if (int.TryParse(txt, out p)) return p;
                }
            }
            catch { }
            return 52830;
        }

        private static void CleanActivePort()
        {
            try
            {
                string path = GetActivePortFilePath();
                if (File.Exists(path)) File.Delete(path);
            }
            catch { }
        }

        [STAThread]
        public static void Main(string[] args)
        {
            bool createdNew;
            _singleInstanceMutex = new Mutex(true, "QuickShareStudio_Desktop_SingleInstance_Mutex_v1", out createdNew);

            if (!createdNew)
            {
                // App is already running in the background or system tray.
                // Re-open / focus the app window for the user without showing any error.
                Log("Existing instance detected. Launching app window for existing instance.");
                _port = ReadActivePort();
                LaunchApp();
                return;
            }

            try
            {
                Log("Main starting...");
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                // 1. Locate web directory
                _webRoot = ResolveWebRoot();
                Log("_webRoot resolved to: " + _webRoot);
                if (string.IsNullOrEmpty(_webRoot) || !File.Exists(Path.Combine(_webRoot, "index.html")))
                {
                    Log("Web bundle not found!");
                    MessageBox.Show(
                        "QuickShare Studio web bundle was not found.\n\n" +
                        "Expected location:\n- " + Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "web") + "\n- or build\\web in the QuickShare project directory.",
                        "QuickShare Studio",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return;
                }

                // 2. Start local HTTP server with automatic port discovery
                bool started = StartHttpServer(52830);
                if (!started)
                {
                    Log("Failed to bind HttpListener to any available port.");
                    MessageBox.Show(
                        "Could not start the QuickShare Studio local service.\nAll candidate ports are currently in use or restricted.",
                        "QuickShare Studio",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return;
                }

                // Spawn worker thread for serving requests
                Thread serverThread = new Thread(ServerWorker);
                serverThread.IsBackground = true;
                serverThread.Start();

                // 3. Setup System Tray Icon
                SetupTrayIcon();
                Log("Tray icon setup complete");

                // 4. Launch dedicated native window
                LaunchApp();
                Log("LaunchApp called");

                // 5. Run message loop for system tray
                Log("Starting message loop with ApplicationContext...");
                Application.Run(new ApplicationContext());
                Log("Message loop ended.");

                // 6. Cleanup
                Shutdown();
            }
            catch (Exception ex)
            {
                try
                {
                    string fatalPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launcher_fatal.log");
                    File.WriteAllText(fatalPath, ex.ToString());
                }
                catch { }
            }
            finally
            {
                try
                {
                    if (_singleInstanceMutex != null)
                    {
                        _singleInstanceMutex.ReleaseMutex();
                        _singleInstanceMutex.Close();
                    }
                }
                catch { }
            }
        }

        private static bool IsValidWebRoot(string dir)
        {
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return false;
            bool hasIndex = File.Exists(Path.Combine(dir, "index.html"));
            bool hasBundle = File.Exists(Path.Combine(dir, "flutter_bootstrap.js")) || 
                             File.Exists(Path.Combine(dir, "main.dart.js"));
            return hasIndex && hasBundle;
        }

        private static string ResolveWebRoot()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;

            // Candidate 1: Adjacent web/ folder (installed app distribution: BaseDirectory\web)
            string c1 = Path.Combine(baseDir, "web");
            if (IsValidWebRoot(c1)) return c1;

            // Candidate 2: Adjacent build/web folder (when running in project root)
            string c2 = Path.Combine(baseDir, "build", "web");
            if (IsValidWebRoot(c2)) return c2;

            // Candidate 3: Subfolder in project directory
            string c3 = @"C:\Users\Abhijeet\Desktop\QUICK SHARE\build\web";
            if (IsValidWebRoot(c3)) return c3;

            string c3Alt = @"C:\Users\Abhijeet\Desktop\QuickShare\build\web";
            if (IsValidWebRoot(c3Alt)) return c3Alt;

            // Candidate 4: Installed Programs directory
            string localProg = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "QuickShare Studio", "web"
            );
            if (IsValidWebRoot(localProg)) return localProg;

            return null;
        }

        private static bool StartHttpServer(int startingPort)
        {
            List<int> candidatePorts = new List<int>();
            for (int p = startingPort; p < startingPort + 100; p++)
            {
                candidatePorts.Add(p);
            }
            for (int p = 8080; p < 8150; p++)
            {
                candidatePorts.Add(p);
            }

            foreach (int p in candidatePorts)
            {
                HttpListener listener = null;
                try
                {
                    listener = new HttpListener();
                    listener.Prefixes.Add("http://127.0.0.1:" + p + "/");
                    listener.Start();

                    _listener = listener;
                    _port = p;
                    Log("HttpListener started successfully on port " + _port);
                    SaveActivePort(_port);
                    return true;
                }
                catch (Exception ex)
                {
                    Log("Port " + p + " is not available: " + ex.Message);
                    if (listener != null)
                    {
                        try { listener.Close(); } catch { }
                    }
                }
            }

            return false;
        }

        private static void SetupTrayIcon()
        {
            _trayIcon = new NotifyIcon();
            _trayIcon.Text = "QuickShare Studio (Running on port " + _port + ")";

            // Try loading application icon
            try
            {
                string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app_icon.ico");
                if (File.Exists(iconPath))
                {
                    _trayIcon.Icon = new Icon(iconPath);
                }
                else
                {
                    _trayIcon.Icon = SystemIcons.Application;
                }
            }
            catch
            {
                _trayIcon.Icon = SystemIcons.Application;
            }

            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add("Open QuickShare Studio", delegate { LaunchApp(); });
            menu.MenuItems.Add("Open in Browser", delegate {
                Process.Start("http://127.0.0.1:" + _port + "/index.html");
            });
            menu.MenuItems.Add("-");
            menu.MenuItems.Add("Exit QuickShare Studio", delegate {
                Shutdown();
                Application.Exit();
            });

            _trayIcon.ContextMenu = menu;
            _trayIcon.Visible = true;
            _trayIcon.DoubleClick += delegate { LaunchApp(); };
        }

        private static void LaunchApp()
        {
            string url = "http://127.0.0.1:" + _port + "/index.html";

            // Paths to Chrome and Edge
            string chromePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                @"Google\Chrome\Application\chrome.exe"
            );
            if (!File.Exists(chromePath))
            {
                chromePath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                    @"Google\Chrome\Application\chrome.exe"
                );
            }

            string edgePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                @"Microsoft\Edge\Application\msedge.exe"
            );
            if (!File.Exists(edgePath))
            {
                edgePath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                    @"Microsoft\Edge\Application\msedge.exe"
                );
            }

            string profileDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "QuickShareStudio", "AppProfile"
            );

            try
            {
                if (!Directory.Exists(profileDir))
                {
                    Directory.CreateDirectory(profileDir);
                }
            }
            catch { }

            // Target app browser executable
            string browserExe = null;
            if (File.Exists(chromePath))
            {
                browserExe = chromePath;
            }
            else if (File.Exists(edgePath))
            {
                browserExe = edgePath;
            }

            if (!string.IsNullOrEmpty(browserExe))
            {
                string args = string.Format(
                    "--app={0} --window-size=1366,850 \"--user-data-dir={1}\"",
                    url, profileDir
                );

                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo(browserExe, args);
                    psi.UseShellExecute = false;
                    _appProcess = Process.Start(psi);
                    return;
                }
                catch
                {
                    // Fall through to default browser
                }
            }

            // Fallback: default browser
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not launch browser: " + ex.Message);
            }
        }

        private static void ServerWorker()
        {
            while (_isRunning && _listener != null && _listener.IsListening)
            {
                try
                {
                    HttpListenerContext context = _listener.GetContext();
                    ThreadPool.QueueUserWorkItem(ProcessRequest, context);
                }
                catch
                {
                    if (!_isRunning) break;
                }
            }
        }

        private static void ProcessRequest(object state)
        {
            HttpListenerContext context = (HttpListenerContext)state;
            try
            {
                string rawUrl = context.Request.Url.AbsolutePath;
                if (string.IsNullOrEmpty(rawUrl) || rawUrl == "/")
                {
                    rawUrl = "/index.html";
                }

                // Strip leading slash and decode
                string relativePath = Uri.UnescapeDataString(rawUrl.TrimStart('/'));
                relativePath = relativePath.Replace('/', Path.DirectorySeparatorChar);

                string fullPath = Path.Combine(_webRoot, relativePath);

                // Path traversal protection
                string canonicalWebRoot = Path.GetFullPath(_webRoot);
                string canonicalTarget = Path.GetFullPath(fullPath);
                if (!canonicalTarget.StartsWith(canonicalWebRoot, StringComparison.OrdinalIgnoreCase))
                {
                    context.Response.StatusCode = 403;
                    context.Response.Close();
                    return;
                }

                if (!File.Exists(fullPath))
                {
                    // Fallback to index.html for SPA page navigation routes without a file extension
                    if (string.IsNullOrEmpty(Path.GetExtension(fullPath)))
                    {
                        fullPath = Path.Combine(_webRoot, "index.html");
                    }
                }

                if (File.Exists(fullPath))
                {
                    byte[] bytes = File.ReadAllBytes(fullPath);
                    context.Response.StatusCode = 200;
                    context.Response.ContentType = GetContentType(fullPath);
                    context.Response.ContentLength64 = bytes.Length;

                    // Essential headers for WASM and local assets
                    context.Response.Headers.Add("Access-Control-Allow-Origin", "*");
                    context.Response.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate");

                    context.Response.OutputStream.Write(bytes, 0, bytes.Length);
                }
                else
                {
                    context.Response.StatusCode = 404;
                }
            }
            catch
            {
                try { context.Response.StatusCode = 500; } catch { }
            }
            finally
            {
                try { context.Response.Close(); } catch { }
            }
        }

        private static string GetContentType(string path)
        {
            string ext = Path.GetExtension(path).ToLowerInvariant();
            switch (ext)
            {
                case ".html": return "text/html; charset=utf-8";
                case ".js":
                case ".mjs": return "application/javascript; charset=utf-8";
                case ".wasm": return "application/wasm";
                case ".json": return "application/json; charset=utf-8";
                case ".css": return "text/css; charset=utf-8";
                case ".png": return "image/png";
                case ".jpg":
                case ".jpeg": return "image/jpeg";
                case ".gif": return "image/gif";
                case ".svg": return "image/svg+xml";
                case ".ico": return "image/x-icon";
                case ".ttf": return "font/ttf";
                case ".otf": return "font/otf";
                case ".woff": return "font/woff";
                case ".woff2": return "font/woff2";
                case ".pdf": return "application/pdf";
                case ".zip": return "application/zip";
                case ".exe": return "application/octet-stream";
                default: return "application/octet-stream";
            }
        }

        private static void Shutdown()
        {
            _isRunning = false;
            CleanActivePort();

            try
            {
                if (_trayIcon != null)
                {
                    _trayIcon.Visible = false;
                    _trayIcon.Dispose();
                }
            }
            catch { }

            try
            {
                if (_listener != null && _listener.IsListening)
                {
                    _listener.Stop();
                    _listener.Close();
                }
            }
            catch { }
        }
    }
}
