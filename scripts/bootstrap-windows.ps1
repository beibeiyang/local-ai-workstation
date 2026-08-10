#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$MacPublicKey = "",
    [switch]$InstallSteam,
    [switch]$SkipDocker,
    [switch]$SkipTailscale,
    [switch]$SkipOllama,
    [switch]$SkipOpenSSH
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Name = $Id
    )

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Warning "winget is unavailable. Install/update App Installer from Microsoft Store, then rerun this script."
        return
    }

    # Pin package queries to the community source. A broken Microsoft Store
    # source must not prevent packages that exist in the winget source from installing.
    $installed = winget list --id $Id --exact --source winget --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and ($installed -join "`n") -match [regex]::Escape($Id)) {
        Write-Host "$Name is already installed."
        return
    }

    Write-Host "Installing $Name..."
    winget install --id $Id --exact --source winget --silent --disable-interactivity `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "$Name could not be installed automatically. Continue with the rest of the setup and install it manually."
    }
}

if (-not (Test-Administrator)) {
    throw "Run this script from an Administrator PowerShell window."
}

Write-Step "Create AI storage directories"
$aiRoot = "C:\AI"
$modelDir = Join-Path $aiRoot "models\ollama"
$projectMirror = Join-Path $aiRoot "shared"
New-Item -ItemType Directory -Force -Path $modelDir, $projectMirror | Out-Null

Write-Step "Install core Windows developer tools"
Install-WingetPackage -Id "Microsoft.WindowsTerminal" -Name "Windows Terminal"
Install-WingetPackage -Id "Microsoft.PowerShell" -Name "PowerShell 7"
Install-WingetPackage -Id "Git.Git" -Name "Git"
Install-WingetPackage -Id "GitHub.cli" -Name "GitHub CLI"
Install-WingetPackage -Id "Microsoft.VisualStudioCode" -Name "Visual Studio Code"

if (-not $SkipDocker) {
    Install-WingetPackage -Id "Docker.DockerDesktop" -Name "Docker Desktop"
}
if (-not $SkipOllama) {
    Install-WingetPackage -Id "Ollama.Ollama" -Name "Ollama"
}
if (-not $SkipTailscale) {
    Install-WingetPackage -Id "Tailscale.Tailscale" -Name "Tailscale"
}
if ($InstallSteam) {
    Install-WingetPackage -Id "Valve.Steam" -Name "Steam"
}

if (-not $SkipOpenSSH) {
    Write-Step "Enable OpenSSH Server"
    $sshCapabilityName = "OpenSSH.Server~~~~0.0.1.0"
    # Query only the one capability we need. Enumerating every capability can look hung.
    $sshCapability = Get-WindowsCapability -Online -Name $sshCapabilityName
    Write-Host "OpenSSH Server state: $($sshCapability.State)"

    if ($sshCapability.State -ne "Installed") {
        Write-Host "Installing the Windows OpenSSH optional feature..."
        try { Start-Service wuauserv -ErrorAction SilentlyContinue } catch { }
        try { Start-Service bits -ErrorAction SilentlyContinue } catch { }
        Add-WindowsCapability -Online -Name $sshCapabilityName | Out-Host
        $sshCapability = Get-WindowsCapability -Online -Name $sshCapabilityName
    }

    if ($sshCapability.State -ne "Installed") {
        throw "OpenSSH Server did not install. Install it from Settings > System > Optional Features, then rerun this script."
    }

    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }

    if ($MacPublicKey.Trim()) {
    Write-Step "Install the supplied Mac SSH public key"
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $currentUserIsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($currentUserIsAdmin) {
        $authorizedKeys = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
        New-Item -ItemType File -Force -Path $authorizedKeys | Out-Null
        $existing = Get-Content $authorizedKeys -ErrorAction SilentlyContinue
        if ($existing -notcontains $MacPublicKey.Trim()) {
            Add-Content -Path $authorizedKeys -Value $MacPublicKey.Trim()
        }
        icacls.exe $authorizedKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
    }
    else {
        $sshDir = Join-Path $env:USERPROFILE ".ssh"
        $authorizedKeys = Join-Path $sshDir "authorized_keys"
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
        New-Item -ItemType File -Force -Path $authorizedKeys | Out-Null
        $existing = Get-Content $authorizedKeys -ErrorAction SilentlyContinue
        if ($existing -notcontains $MacPublicKey.Trim()) {
            Add-Content -Path $authorizedKeys -Value $MacPublicKey.Trim()
        }
        icacls.exe $sshDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
    }
        Restart-Service sshd
        Write-Host "SSH key installed at $authorizedKeys"
    }
    else {
        Write-Warning "No Mac public key supplied. Rerun with -MacPublicKey 'ssh-ed25519 AAAA...' after generating a key on the Mac."
    }
}
else {
    Write-Warning "OpenSSH setup skipped. SSH key installation was also skipped."
}

Write-Step "Enable WSL2 and Ubuntu 24.04"
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

try { wsl.exe --update | Out-Host } catch { Write-Warning "WSL update will complete after reboot." }
try { wsl.exe --set-default-version 2 | Out-Host } catch { Write-Warning "WSL default version will be set after reboot." }

$installedDistros = @()
try { $installedDistros = @(wsl.exe --list --quiet 2>$null) } catch { }
if (-not ($installedDistros | Where-Object { $_.Trim() -eq "Ubuntu-24.04" })) {
    try {
        wsl.exe --install --distribution Ubuntu-24.04 --no-launch | Out-Host
    }
    catch {
        Write-Warning "Ubuntu installation may require a reboot first. Reboot, rerun this script, then launch Ubuntu-24.04 once."
    }
}

Write-Step "Tune WSL resource limits for the installed system RAM"
$totalRamGB = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$logicalCpu = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

if ($totalRamGB -le 24) {
    $wslMemory = 8
    $wslSwap = 16
}
elseif ($totalRamGB -le 40) {
    $wslMemory = 24
    $wslSwap = 24
}
else {
    $wslMemory = [math]::Min(48, [math]::Floor($totalRamGB * 0.75))
    $wslSwap = 32
}
$wslProcessors = [math]::Max(4, [math]::Min(12, $logicalCpu - 2))

$wslConfig = @"
[wsl2]
memory=${wslMemory}GB
processors=$wslProcessors
swap=${wslSwap}GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@
Set-Content -Path (Join-Path $env:USERPROFILE ".wslconfig") -Value $wslConfig -Encoding ASCII

Write-Step "Configure Ollama for Windows-to-WSL access"
[Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $modelDir, "User")
# Ollama must listen beyond Windows loopback for WSL2 and Docker Desktop to reach it.
# Do not expose port 11434 through your router. Use an SSH tunnel for remote access.
[Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0:11434", "User")
# Conservative defaults for a 16 GB VRAM / 16 GB system-RAM machine. These prevent
# concurrent model copies from exhausting memory; increase them only after a RAM upgrade.
[Environment]::SetEnvironmentVariable("OLLAMA_MAX_LOADED_MODELS", "1", "User")
[Environment]::SetEnvironmentVariable("OLLAMA_NUM_PARALLEL", "1", "User")
[Environment]::SetEnvironmentVariable("OLLAMA_CONTEXT_LENGTH", "8192", "User")
[Environment]::SetEnvironmentVariable("OLLAMA_FLASH_ATTENTION", "1", "User")
[Environment]::SetEnvironmentVariable("OLLAMA_KV_CACHE_TYPE", "q8_0", "User")

# Permit Ollama only on Private networks. The rule is intentionally absent on Public profiles.
$ollamaRuleName = "Local AI - Ollama Private"
Get-NetFirewallRule -DisplayName $ollamaRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName $ollamaRuleName -Direction Inbound -Protocol TCP -LocalPort 11434 `
    -Action Allow -Profile Private -RemoteAddress LocalSubnet | Out-Null

Write-Step "Configure always-on behavior while plugged in"
powercfg.exe /change standby-timeout-ac 0 | Out-Null
powercfg.exe /change monitor-timeout-ac 15 | Out-Null
powercfg.exe /hibernate on | Out-Null

Write-Step "Write setup summary"
$summaryPath = Join-Path $aiRoot "SETUP-NEXT-STEPS.txt"
$summary = @"
Local AI workstation bootstrap completed.

NEXT STEPS
1. Open NVIDIA App and install the current Studio Driver. Reboot.
2. Launch Ubuntu 24.04 once, create the Linux username/password, then run bootstrap-wsl.sh inside WSL.
3. Launch Ollama once from the Windows Start menu so it reads OLLAMA_MODELS and OLLAMA_HOST.
4. Launch Docker Desktop, enable the WSL2 engine, and enable Ubuntu-24.04 integration.
5. Sign in to Tailscale on both this desktop and the Mac if you need access away from home.
6. Test from Windows: nvidia-smi ; ollama list ; wsl -d Ubuntu-24.04 nvidia-smi
7. From the Mac, use SSH key authentication and tunnel ports 11434 and 3000 rather than exposing them publicly.

WSL limits selected automatically:
- Physical RAM detected: ${totalRamGB}GB
- WSL memory: ${wslMemory}GB
- WSL swap: ${wslSwap}GB
- WSL processors: $wslProcessors

Ollama models directory: $modelDir
Shared Windows directory: $projectMirror
"@
Set-Content -Path $summaryPath -Value $summary -Encoding UTF8
Get-Content $summaryPath | Write-Host

Write-Host "`nBootstrap complete. Reboot Windows before continuing." -ForegroundColor Green
