// JRTreborn Native Launcher
// Embeds the standalone PowerShell script as compressed base64, extracts it to
// a temp file, and runs it with PowerShell.  The exe itself requests UAC
// elevation via Launcher.manifest, so the child PowerShell process inherits
// administrator rights without a second prompt.
//
// Build placeholders substituted by Build-Exe.ps1 at compile time:
//   ###VERSION###          – 4-part version string (e.g. 1.1.0.0)
//   ###EMBEDDED_SCRIPT###  – GZip-compressed, base64-encoded standalone .ps1

using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("JRTreborn")]
[assembly: AssemblyDescription("Junkware Removal Tool Reborn - Open Source Adware & PUP Remover")]
[assembly: AssemblyCompany("JRTreborn Open Source Project")]
[assembly: AssemblyProduct("JRTreborn")]
[assembly: AssemblyCopyright("Open Source (MIT)")]
[assembly: AssemblyVersion("###VERSION###")]
[assembly: AssemblyFileVersion("###VERSION###")]

class Program
{
    // GZip-compressed, base64-encoded standalone PowerShell script.
    // Substituted by Build-Exe.ps1 before compilation.
    private const string EmbeddedScript = "###EMBEDDED_SCRIPT###";

    static int Main(string[] args)
    {
        string tempScript = null;
        try
        {
            tempScript = ExtractScript();
            return RunScript(tempScript, args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("JRTreborn: launch error — " + ex.Message);
            Console.Error.WriteLine("Press any key to exit.");
            try { Console.ReadKey(true); } catch { }
            return 1;
        }
        finally
        {
            if (tempScript != null)
                TryDelete(tempScript);
        }
    }

    static string ExtractScript()
    {
        byte[] compressed = Convert.FromBase64String(EmbeddedScript);

        byte[] scriptBytes;
        using (var inMs = new MemoryStream(compressed))
        using (var gz = new GZipStream(inMs, CompressionMode.Decompress))
        using (var outMs = new MemoryStream())
        {
            gz.CopyTo(outMs);
            scriptBytes = outMs.ToArray();
        }

        // Use a fixed prefix so crash dumps are recognisable; random suffix to
        // avoid collisions if multiple instances run simultaneously.
        string path = Path.Combine(
            Path.GetTempPath(),
            "JRTreborn_" + Guid.NewGuid().ToString("N") + ".ps1");

        File.WriteAllBytes(path, scriptBytes);
        return path;
    }

    static int RunScript(string scriptPath, string[] args)
    {
        // Forward any arguments the user passed to the exe straight through to
        // the PowerShell script unchanged.
        var psArgs = new StringBuilder();
        psArgs.Append("-NoProfile -ExecutionPolicy Bypass -File \"");
        psArgs.Append(scriptPath.Replace("\"", "\\\""));
        psArgs.Append('"');

        foreach (string arg in args)
        {
            psArgs.Append(" \"");
            psArgs.Append(arg.Replace("\\", "\\\\").Replace("\"", "\\\""));
            psArgs.Append('"');
        }

        var psi = new ProcessStartInfo
        {
            FileName  = "powershell.exe",
            Arguments = psArgs.ToString(),
            UseShellExecute = false,
        };

        using (var proc = Process.Start(psi))
        {
            proc.WaitForExit();
            return proc.ExitCode;
        }
    }

    static void TryDelete(string path)
    {
        try { File.Delete(path); } catch { }
    }
}
