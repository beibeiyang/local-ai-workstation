# Running `bootstrap-windows.ps1`

[`scripts/bootstrap-windows.ps1`](../scripts/bootstrap-windows.ps1) is the first
thing you run, and the only one that runs on the Windows side. It takes a stock
Windows 11 install and leaves it ready to be SSH'd into.

## What this guide assumes

-   **Windows 11**, already installed and signed in.
-   **An account with local Administrator rights**, and that you know how to open
    an elevated PowerShell window (right-click Start → *Terminal (Admin)*, or
    right-click Windows PowerShell → *Run as administrator*). The script's first
    real action is to check for this and stop if it's missing:

    ```text
    Run this script from an Administrator PowerShell window.
    ```

    Administrator is not optional here, and not a convenience. The script enables
    a Windows optional feature (OpenSSH Server), turns on the WSL and
    Virtual Machine Platform features via `dism`, creates firewall rules, sets a
    service to start automatically, and changes the power plan. None of that is
    available to a standard user.
-   **`winget` is available** (it ships with App Installer from the Microsoft
    Store). If it's missing the script warns and skips the package installs
    rather than failing outright — install App Installer and rerun.
-   **The NVIDIA GPU is physically installed**, though its driver is *not* this
    script's job. See [below](#what-it-deliberately-leaves-to-you).
-   Roughly **15–30 minutes**, mostly download time, plus one reboot.

If you're setting up a brand-new Windows install and don't yet have an
administrator account, create one in *Settings → Accounts → Other users* (set
*Account type* to **Administrator**) and sign in as that user before continuing.

## When to run it

Once, first, before anything else in this repo:

1.  **On the Mac** — generate the SSH key, because the script wants the public
    half as an argument:
    ```bash
    ssh-keygen -t ed25519 -f ~/.ssh/ai_workstation -C "mac-to-ai-workstation"
    cat ~/.ssh/ai_workstation.pub
    ```
    You can run the script without the key and add it later, but passing it now
    saves a round trip.
2.  **On the Windows box** — get this repo onto the machine (clone it, or copy
    the folder over), then open **PowerShell as Administrator**:
    ```powershell
    Set-ExecutionPolicy -Scope Process Bypass -Force
    cd path\to\local-ai-workstation\scripts
    .\bootstrap-windows.ps1 -MacPublicKey 'PASTE_THE_FULL_SSH_PUBLIC_KEY_HERE'
    ```
    `Set-ExecutionPolicy -Scope Process` loosens script execution for this
    window only; it reverts when you close it.
3.  **Reboot.** The script says so at the end, and it matters — the WSL and
    Virtual Machine Platform features aren't active until you do.
4.  Then continue with the WSL side:
    [`scripts/bootstrap-wsl.sh`](../scripts/bootstrap-wsl.sh), run from inside
    Ubuntu.

**Rerunning is safe and expected.** Package installs are skipped when already
present, the firewall rules and directories are created only if absent, and the
SSH key is not duplicated. If a step fails — the two known ones are in
[`troubleshooting.md`](troubleshooting.md) — fix it and run the script again.

## What it does

-   **Storage** — creates `C:\AI\models\ollama` (Ollama's model store) and
    `C:\AI\shared`.
-   **Developer tools via winget** — Windows Terminal, PowerShell 7, Git,
    GitHub CLI, Visual Studio Code, plus Docker Desktop, Ollama, and Tailscale
    unless skipped.
-   **OpenSSH Server** — enables the `OpenSSH.Server~~~~0.0.1.0` capability,
    sets `sshd` to start automatically, starts it, and opens inbound TCP 22 in
    the Windows firewall.
-   **Your SSH key** — installs the key you passed. Note *where*: because you're
    running elevated, it goes to
    `C:\ProgramData\ssh\administrators_authorized_keys`, not
    `~/.ssh/authorized_keys`. That's a Windows OpenSSH rule for administrator
    accounts: for members of the Administrators group, `sshd` reads that single
    machine-wide file and ignores the per-user one. If you later add a key by
    hand and SSH still rejects it, check that you put it in the right file.
-   **WSL2 + Ubuntu 24.04** — enables the required Windows features, runs
    `wsl --update`, sets WSL 2 as the default version, and installs the
    `Ubuntu-24.04` distro without launching it.
-   **`.wslconfig`** — writes memory, swap, and processor limits scaled to the
    RAM it detects (on a 16GB box: 8GB memory, 16GB swap), plus
    `autoMemoryReclaim` and `sparseVhd`.
-   **Ollama configuration** — sets `OLLAMA_MODELS`, `OLLAMA_HOST=0.0.0.0:11434`,
    and the conservative concurrency/context defaults described in
    [the version inventory](architecture.md#services), then adds a firewall rule
    for port 11434 limited to the **Private** profile and the local subnet.
-   **Power behavior** — never sleep while on AC power, screen off after 15
    minutes, hibernate enabled. A workstation you SSH into can't be asleep.
-   **A summary file** at `C:\AI\SETUP-NEXT-STEPS.txt`, listing the manual steps
    below and the WSL limits it chose.

## What it deliberately leaves to you

These need a human, and the script prints them at the end:

1.  **Install the NVIDIA Studio Driver** via the NVIDIA App, then reboot. Install
    it once, on Windows only — see
    [why one driver, not two](architecture.md#why-one-nvidia-driver-not-two).
2.  **Launch Ubuntu 24.04 once** to create your Linux username and password.
3.  **Launch Ollama once** from the Start menu, so it picks up `OLLAMA_MODELS`
    and `OLLAMA_HOST`.
4.  **Open Docker Desktop**, enable the WSL2 engine, and turn on `Ubuntu-24.04`
    integration.
5.  **Sign in to Tailscale** on both machines, if you want access away from home.

## Options

| Flag | Effect |
|---|---|
| `-MacPublicKey '<key>'` | Installs that public key for SSH. Omitted, the script warns and skips it. |
| `-SkipOpenSSH` | Skips the OpenSSH feature, service, firewall rule — *and* the key install. Use when OpenSSH is already configured, or to work around a stuck install. |
| `-SkipDocker` | Doesn't install Docker Desktop. Open WebUI needs it. |
| `-SkipOllama` | Doesn't install Ollama. The environment variables and firewall rule are still set. |
| `-SkipTailscale` | Doesn't install Tailscale. |
| `-InstallSteam` | Installs Steam. Off by default. |

## Checking it worked

From Windows PowerShell, after the reboot:

```powershell
Get-Service sshd                      # Status: Running
wsl --list --verbose                  # Ubuntu-24.04, VERSION 2
nvidia-smi                            # after the driver is installed
ollama list                           # after launching Ollama once
```

Then move to the WSL side and finish with
[`scripts/verify-setup.sh`](../scripts/verify-setup.sh), which checks the whole
stack end to end. If anything fails, start with
[`troubleshooting.md`](troubleshooting.md) — both failures documented there came
from this script on a real machine.
