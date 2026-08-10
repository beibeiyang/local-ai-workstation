#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_HERMES="${INSTALL_HERMES:-1}"
INSTALL_OPENCLAW="${INSTALL_OPENCLAW:-0}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as your normal WSL user, not root." >&2
  exit 1
fi

step "Enable systemd in WSL"
sudo install -d -m 0755 /etc
if ! grep -q '^systemd=true' /etc/wsl.conf 2>/dev/null; then
  sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true
EOF
  warn "systemd was enabled. After this script, run 'wsl --shutdown' in Windows PowerShell, then reopen Ubuntu."
fi

step "Update Ubuntu and install development essentials"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential ca-certificates curl wget git gh jq unzip zip \
  ripgrep fd-find fzf tmux htop btop nvtop tree shellcheck direnv \
  sqlite3 openssh-client net-tools iproute2 dnsutils socat \
  python3 python3-venv python3-pip pipx

mkdir -p "$HOME/src" "$HOME/ai" "$HOME/bin" "$HOME/logs" "$HOME/.config/local-ai"
ln -sf "$(command -v fdfind)" "$HOME/bin/fd" 2>/dev/null || true

git config --global init.defaultBranch main
git config --global pull.rebase false

step "Install uv for isolated Python tooling"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

step "Install mise and managed Node.js/Python runtimes"
if ! command -v mise >/dev/null 2>&1; then
  curl https://mise.run | sh
fi
if [[ -x "$HOME/.local/bin/mise" ]]; then
  eval "$("$HOME/.local/bin/mise" activate bash)"
  "$HOME/.local/bin/mise" use --global node@24 python@3.12
fi

step "Create dynamic connection settings for Windows Ollama"
cat > "$HOME/bin/windows-host-ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ip route show default | awk '{print $3; exit}'
EOF
chmod +x "$HOME/bin/windows-host-ip"

cat > "$HOME/.config/local-ai/env.sh" <<'EOF'
# Windows hosts Ollama; WSL discovers the current Windows-side gateway at shell startup.
_WINDOWS_HOST_IP="$(ip route show default | awk '{print $3; exit}')"
export OLLAMA_BASE_URL="http://${_WINDOWS_HOST_IP}:11434"
export OPENAI_BASE_URL="${OLLAMA_BASE_URL}/v1"
export OPENAI_API_KEY="ollama"
unset _WINDOWS_HOST_IP
EOF

if ! grep -q 'local-ai/env.sh' "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'

# Local AI workstation settings
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
[[ -s "$HOME/.config/local-ai/env.sh" ]] && source "$HOME/.config/local-ai/env.sh"
eval "$(direnv hook bash)"
if [[ -x "$HOME/.local/bin/mise" ]]; then eval "$("$HOME/.local/bin/mise" activate bash)"; fi
EOF
fi
# shellcheck disable=SC1090
source "$HOME/.config/local-ai/env.sh"

step "Add workstation health check"
cat > "$HOME/bin/ai-healthcheck" <<'EOF'
#!/usr/bin/env bash
set -u
printf '\n--- WSL ---\n'
uname -a
printf '\n--- GPU visible in WSL ---\n'
nvidia-smi || true
printf '\n--- Windows Ollama endpoint ---\n'
WINDOWS_HOST_IP="$(ip route show default | awk '{print $3; exit}')"
curl -fsS "http://${WINDOWS_HOST_IP}:11434/api/tags" | jq . || {
  echo "Ollama is not reachable. Launch Ollama on Windows and verify OLLAMA_HOST=0.0.0.0:11434."
}
printf '\n--- Docker Desktop integration ---\n'
docker version 2>/dev/null || echo "Docker is not available in this WSL distro yet. Enable Ubuntu integration in Docker Desktop."
printf '\n--- Agent CLIs ---\n'
command -v hermes >/dev/null && hermes --version || echo "Hermes not installed"
command -v openclaw >/dev/null && openclaw --version || echo "OpenClaw not installed"
EOF
chmod +x "$HOME/bin/ai-healthcheck"

step "Configure tmux for persistent remote sessions"
cat > "$HOME/.tmux.conf" <<'EOF'
set -g mouse on
set -g history-limit 100000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g allow-rename off
EOF

if [[ "$INSTALL_HERMES" == "1" ]]; then
  step "Install Hermes Agent"
  if ! command -v hermes >/dev/null 2>&1; then
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  else
    echo "Hermes is already installed."
  fi
fi

if [[ "$INSTALL_OPENCLAW" == "1" ]]; then
  step "Install OpenClaw"
  if ! command -v openclaw >/dev/null 2>&1; then
    curl -fsSL https://openclaw.ai/install.sh | bash
  else
    echo "OpenClaw is already installed."
  fi
else
  warn "OpenClaw was intentionally not installed. After the base stack works, install with: INSTALL_OPENCLAW=1 ./bootstrap-wsl.sh"
fi

step "Finish"
cat <<EOF
WSL setup is complete.

Next commands:
  source ~/.bashrc
  ai-healthcheck
  tmux new -s ai

Hermes onboarding:
  hermes setup

OpenClaw onboarding after installation:
  openclaw onboard --install-daemon

Projects belong under ~/src, not /mnt/c, for better Linux filesystem performance.
EOF
