// Launcher.cs - the KenshiCoop-Setup.exe stub (built by installer/build_setup.ps1
// with the C# compiler that ships with Windows' .NET Framework 4.x).
//
// Setup.ps1 and payload.zip are embedded resources. The stub unpacks them into a
// private temp folder, runs Setup.ps1 in Windows PowerShell 5.1 (STA, no console
// window), waits for the setup window to close and deletes the folder.
// Replaces an IExpress package: on Windows 11 build 26200 IExpress stubs exit 0
// without ever running their command. C# 5 syntax: csc.exe 4.x is C# 5.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("KenshiCoop Setup")]
[assembly: AssemblyProduct("KenshiCoop")]

static class KenshiCoopSetup
{
    const string Title = "KenshiCoop Setup";

    static void Extract(string name, string dir)
    {
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
        {
            if (s == null) throw new InvalidOperationException("Setup is damaged: " + name + " is missing.");
            using (FileStream f = File.Create(Path.Combine(dir, name))) s.CopyTo(f);
        }
    }

    [STAThread]
    static int Main()
    {
        string dir = Path.Combine(Path.GetTempPath(), "KenshiCoopSetup-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(dir);
            Extract("Setup.ps1", dir);
            Extract("payload.zip", dir);

            string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                     @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(ps))
            {
                MessageBox.Show("Windows PowerShell was not found on this PC, so the setup cannot run.",
                                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 2;
            }
            ProcessStartInfo si = new ProcessStartInfo(ps,
                "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + Path.Combine(dir, "Setup.ps1") + "\"");
            si.UseShellExecute = false;
            si.CreateNoWindow = true;
            si.WorkingDirectory = dir;
            using (Process p = Process.Start(si))
            {
                p.WaitForExit();
                if (p.ExitCode != 0)
                {
                    MessageBox.Show("The setup stopped unexpectedly (code " + p.ExitCode + ").\r\n\r\n" +
                                    "Nothing was changed after that point. Please send Brandon a screenshot of this message.",
                                    Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                return p.ExitCode;
            }
        }
        catch (Exception e)
        {
            MessageBox.Show("The setup could not start:\r\n\r\n" + e.Message, Title,
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch { }
        }
    }
}
