$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Desktop = [Environment]::GetFolderPath("Desktop")
if (-not $Desktop) {
  $Desktop = Join-Path $env:USERPROFILE "Desktop"
}

$PackageScript = Join-Path $PSScriptRoot "create-local-installer-package.ps1"
$PackageZip = Join-Path $Desktop "Financeiro-Pro-Instalador-Local.zip"
$InstallerExe = Join-Path $Desktop "Financeiro-Pro-Instalador.exe"
$StageRoot = Join-Path $env:TEMP "financeiro-pro-exe-installer"
$SourcePath = Join-Path $StageRoot "FinanceiroProInstaller.cs"

Write-Host "Preparando pacote local do Financeiro Pro..."
& $PackageScript

if (-not (Test-Path $PackageZip)) {
  throw "Pacote base nao encontrado: $PackageZip"
}

Remove-Item $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null

$cscCandidates = @(
  (Join-Path $env:SystemRoot "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
  (Join-Path $env:SystemRoot "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) {
  throw "Compilador do Windows nao encontrado para gerar o instalador .exe."
}

function Remove-GeneratedDesktopFile([string]$FileName) {
  $desktopCandidates = @(
    $Desktop,
    (Join-Path $env:USERPROFILE "Desktop"),
    (Join-Path $env:USERPROFILE "OneDrive\Desktop")
  ) | Where-Object { $_ } | Select-Object -Unique

  foreach ($desktopPath in $desktopCandidates) {
    Remove-Item (Join-Path $desktopPath $FileName) -Force -ErrorAction SilentlyContinue
  }
}

$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;

class FinanceiroProInstaller
{
    static int Main()
    {
        Console.Title = "Instalador Financeiro Pro";

        try
        {
            string installDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "FinanceiroPro"
            );

            Console.WriteLine("Instalando Financeiro Pro...");
            Console.WriteLine("Pasta do programa: " + installDir);
            Console.WriteLine();

            RequireCommand("node.exe", "Node.js");
            RequireCommand("npm.cmd", "npm");

            Directory.CreateDirectory(installDir);

            string extractRoot = Path.Combine(Path.GetTempPath(), "financeiro-pro-install-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(extractRoot);

            try
            {
                ExtractPayload(extractRoot);
                CopyDirectory(extractRoot, installDir);

                string installScript = Path.Combine(installDir, "scripts", "install-local-server.ps1");
                if (!File.Exists(installScript))
                {
                    throw new FileNotFoundException("Arquivo de instalacao nao encontrado.", installScript);
                }

                Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + installScript + "\"", installDir);

                Console.WriteLine();
                Console.WriteLine("Financeiro Pro instalado com sucesso.");
                Console.WriteLine("Use o atalho Financeiro Pro na Area de Trabalho.");
                Console.WriteLine("Usuario inicial: admin.financeiro");
                Console.WriteLine("Senha inicial: FinanceiroLocal@2026");
                Console.WriteLine();
                Console.WriteLine("Pressione ENTER para fechar.");
                Console.ReadLine();
                return 0;
            }
            finally
            {
                try { Directory.Delete(extractRoot, true); } catch { }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine();
            Console.WriteLine("NAO FOI POSSIVEL INSTALAR.");
            Console.WriteLine(ex.Message);
            Console.WriteLine();
            Console.WriteLine("Pressione ENTER para fechar.");
            Console.ReadLine();
            return 1;
        }
    }

    static void RequireCommand(string command, string friendlyName)
    {
        int exitCode = RunHidden("where.exe", command);
        if (exitCode != 0)
        {
            try { Process.Start(new ProcessStartInfo("https://nodejs.org/") { UseShellExecute = true }); } catch { }
            throw new Exception(friendlyName + " nao encontrado. Instale o Node.js LTS e execute este instalador novamente.");
        }
    }

    static int RunHidden(string fileName, string arguments)
    {
        ProcessStartInfo info = new ProcessStartInfo(fileName, arguments);
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        Process process = Process.Start(info);
        process.WaitForExit();
        return process.ExitCode;
    }

    static void Run(string fileName, string arguments, string workingDirectory)
    {
        ProcessStartInfo info = new ProcessStartInfo(fileName, arguments);
        info.WorkingDirectory = workingDirectory;
        info.UseShellExecute = false;
        Process process = Process.Start(info);
        process.WaitForExit();
        if (process.ExitCode != 0)
        {
            throw new Exception("Instalacao interrompida. Codigo: " + process.ExitCode);
        }
    }

    static void ExtractPayload(string destination)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        string resourceName = null;
        foreach (string name in assembly.GetManifestResourceNames())
        {
            if (name.EndsWith("SetupPayload.zip", StringComparison.OrdinalIgnoreCase))
            {
                resourceName = name;
                break;
            }
        }

        if (resourceName == null)
        {
            throw new Exception("Pacote interno do instalador nao encontrado.");
        }

        string zipPath = Path.Combine(Path.GetTempPath(), "financeiro-pro-payload-" + Guid.NewGuid().ToString("N") + ".zip");
        try
        {
            using (Stream input = assembly.GetManifestResourceStream(resourceName))
            using (FileStream output = File.Create(zipPath))
            {
                input.CopyTo(output);
            }

            ZipFile.ExtractToDirectory(zipPath, destination);
        }
        finally
        {
            try { File.Delete(zipPath); } catch { }
        }
    }

    static void CopyDirectory(string sourceDir, string targetDir)
    {
        Directory.CreateDirectory(targetDir);

        foreach (string dir in Directory.GetDirectories(sourceDir, "*", SearchOption.AllDirectories))
        {
            string target = Path.Combine(targetDir, dir.Substring(sourceDir.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
            Directory.CreateDirectory(target);
        }

        foreach (string file in Directory.GetFiles(sourceDir, "*", SearchOption.AllDirectories))
        {
            string relative = file.Substring(sourceDir.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string target = Path.Combine(targetDir, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target));
            File.Copy(file, target, true);
        }
    }
}
'@

Set-Content -Path $SourcePath -Encoding ASCII -Value $source

Remove-Item $InstallerExe -Force -ErrorAction SilentlyContinue
Write-Host "Gerando instalador .exe..."
& $csc /nologo /target:exe /out:$InstallerExe /resource:$PackageZip,SetupPayload.zip /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll $SourcePath

if (-not (Test-Path $InstallerExe)) {
  throw "Nao foi possivel gerar o instalador .exe."
}

Remove-GeneratedDesktopFile "Financeiro-Pro-Setup.exe"
Remove-GeneratedDesktopFile "Financeiro-Pro-Setup.cmd"
Remove-GeneratedDesktopFile "Financeiro-Pro-Setup.ps1"
Remove-GeneratedDesktopFile "INSTALAR-FINANCEIRO-PRO.cmd"
Remove-GeneratedDesktopFile "~Financeiro-Pro-Setup.CAB"
Remove-Item $PackageZip -Force -ErrorAction SilentlyContinue

Write-Host "Instalador criado em: $InstallerExe"
Write-Host "Ele instala em AppData\Local\FinanceiroPro e cria o atalho Financeiro Pro na Area de Trabalho."
