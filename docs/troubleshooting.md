# Troubleshooting

Two real failures came up running [`scripts/bootstrap-windows.ps1`](../scripts/bootstrap-windows.ps1) on an actual
Windows 11 machine. Both are fixed in the version of the script in this
repo; this doc explains what happened and how to recognize it if it recurs.
For what that script does and when to run it, see
[`windows-bootstrap.md`](windows-bootstrap.md).

## WinGet: `Failed when searching source: msstore` / `0x8a15005e`

### Symptom

```text
Installing Git...
Failed when searching source: msstore
An unexpected error occurred while executing the command:
0x8a15005e : The server certificate did not match any of the expected values.

The following packages were found among the working sources.
Please specify one of them using the --source option to proceed.
Name Id      Source
-------------------
Git  Git.Git winget
WARNING: Git could not be installed automatically. Continue with the rest of the setup and install it manually.
```

This repeats for every package WinGet tries to install (PowerShell, Git,
GitHub CLI, Docker Desktop, Ollama, Tailscale, ...).

### Root cause

WinGet checks the Microsoft Store source in addition to the `winget`
community source. Certificate validation against `msstore` was failing, and
that unrelated failure aborted the whole install — even though the package
was found fine on the `winget` source.

### Fix

Pin every install to the working source explicitly:

```powershell
winget install `
  --id Git.Git `
  --exact `
  --source winget `
  --silent `
  --disable-interactivity `
  --accept-package-agreements `
  --accept-source-agreements
```

[`scripts/bootstrap-windows.ps1`](../scripts/bootstrap-windows.ps1) in this repo already does this. Verify the
source works before rerunning:

```powershell
winget source list
winget search --id Git.Git --exact --source winget
```

The Microsoft Store source itself can be repaired later, separately:

```powershell
winget source reset --force
winget source update
```

## Bootstrap appears stuck at `Enable OpenSSH Server`

### Symptom

The script prints `==> Enable OpenSSH Server` and then hangs indefinitely —
no error, no progress.

### Root cause

The original script enumerated *every* Windows optional capability before
filtering for OpenSSH. That enumeration is slow and can look identical to a
frozen script.

### Fix

1. In the stuck PowerShell window, press `Ctrl+C`.
2. Check OpenSSH's actual state directly:
   ```powershell
   Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   ```
   - `State : Installed` — it actually finished; the script just looked frozen.
   - `State : NotPresent` — it did not install; continue below.
   - `State : InstallPending` — restart Windows before continuing.
3. [`scripts/bootstrap-windows.ps1`](../scripts/bootstrap-windows.ps1) now queries only the one capability it
   needs (`OpenSSH.Server~~~~0.0.1.0`) instead of enumerating all of them, so
   this shouldn't recur. If it still gets stuck, install OpenSSH through the
   GUI instead:
   ```text
   Settings → System → Optional Features → View features
   → search "OpenSSH Server" → Install
   ```
   Then:
   ```powershell
   Set-Service -Name sshd -StartupType Automatic
   Start-Service sshd
   Get-Service sshd
   ```
   Expect `Status: Running  Name: sshd`. Also confirm the firewall rule
   exists:
   ```powershell
   Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
   ```
   If that returns nothing:
   ```powershell
   New-NetFirewallRule `
     -Name "OpenSSH-Server-In-TCP" `
     -DisplayName "OpenSSH Server (sshd)" `
     -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
   ```
4. Rerun the bootstrap script — it's designed to be rerun and will skip
   already-installed packages and configured features. To finish everything
   else first and deal with SSH later, use the escape hatch:
   ```powershell
   .\bootstrap-windows.ps1 -MacPublicKey 'YOUR_KEY' -SkipOpenSSH
   ```

## Hermes: which provider / endpoint to pick

If [`scripts/bootstrap-wsl.sh`](../scripts/bootstrap-wsl.sh) prompts you to choose a model provider for Hermes,
select **Custom endpoint (enter URL manually)** — not "Ollama Cloud" (that's
Ollama's *hosted* service, unrelated to the Ollama running on this machine).

Ollama runs on **Windows**; Hermes runs inside **WSL**. Do not enter
`http://localhost:11434/v1` — from WSL's perspective that's not where Ollama
is. Use the Windows host gateway IP that [`scripts/bootstrap-wsl.sh`](../scripts/bootstrap-wsl.sh) already exported:

```bash
echo "$OPENAI_BASE_URL"
curl -fsS "$OLLAMA_BASE_URL/api/tags" | jq -r '.models[].name'
```

Enter that URL as the API base, `ollama` as the API key (Ollama doesn't
check it, but the field can't be blank), and the exact model name the
`curl` call returned. If Hermes insists on a minimum context length of
`64000` and you don't want to raise the Ollama context that high yet,
cancel the Hermes provider setup rather than doing so — see
[`models.md`](models.md) for why.

For the terminal backend prompt, choose **Local — run directly on this
machine**. Hermes is already running inside WSL, so "local" means commands
execute there, where your repos, Ollama access, Git, Python, Node, and
Docker CLI already are. Reach for Docker-backed isolation later, for
untrusted agents or experiments.

## OpenCode: `localhost:11434` may not reach Ollama from WSL

[`config/opencode.json.example`](../config/opencode.json.example) points `baseURL` at
`http://localhost:11434/v1`, same as OpenCode's own quick-start docs. This
works only if WSL2 is using mirrored networking (or Ollama happens to be
reachable through `localhost` in your setup). If OpenCode can't reach
Ollama, apply the same fix used for Hermes above: use the Windows host
gateway IP instead of `localhost`:

```bash
echo "$OLLAMA_BASE_URL"
```

and set `baseURL` in `opencode.json` to that value with `/v1` appended.
