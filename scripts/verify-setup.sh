#!/usr/bin/env bash
# Run from inside Ubuntu/WSL after bootstrap-wsl.sh and pull-models.sh.
# Mirrors the validation checklist in the README: local WSL checks, then a
# reminder of what to check back on Windows and from the Mac.
set -uo pipefail

pass() { printf '  [OK]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; ok=1; }
info() { printf '  [--]   %s\n' "$1"; }

ok=0

echo "== Inside WSL =="

if command -v ai-healthcheck >/dev/null 2>&1; then
  if ai-healthcheck >/tmp/ai-healthcheck.log 2>&1; then
    pass "ai-healthcheck"
  else
    fail "ai-healthcheck (see /tmp/ai-healthcheck.log)"
  fi
else
  fail "ai-healthcheck not found (did bootstrap-wsl.sh run and did you source ~/.bashrc?)"
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  pass "nvidia-smi reachable from WSL"
else
  fail "nvidia-smi not reachable from WSL (Windows NVIDIA driver / WSL GPU passthrough issue)"
fi

if command -v ollama >/dev/null 2>&1; then
  if ollama list >/dev/null 2>&1; then
    pass "ollama reachable"
    models=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    info "ollama list: ${models} model(s) installed"
  else
    fail "ollama installed but not responding (is it running on Windows?)"
  fi
else
  fail "ollama command not found"
fi

if command -v docker >/dev/null 2>&1; then
  if docker compose ps >/dev/null 2>&1; then
    pass "docker compose ps"
  else
    info "docker compose ps failed (fine if you haven't run 'docker compose up -d' in config/ yet)"
  fi
else
  fail "docker command not found (enable WSL Integration in Docker Desktop settings)"
fi

if curl -fsS -o /dev/null http://127.0.0.1:3000 2>/dev/null; then
  pass "Open WebUI reachable at http://127.0.0.1:3000"
else
  info "Open WebUI not reachable at :3000 (fine if you haven't started it yet)"
fi

echo
echo "== Not checked by this script — verify manually =="
echo "  On Windows (PowerShell):"
echo "    nvidia-smi"
echo "    ollama list"
echo "    wsl -d Ubuntu-24.04 nvidia-smi"
echo "  From the Mac (after 'ssh ai-dev' works):"
echo "    curl http://127.0.0.1:11434/api/tags"
echo "    open http://127.0.0.1:3000"

echo
if [ "$ok" -eq 0 ]; then
  echo "All local checks passed."
else
  echo "One or more checks failed. See docs/troubleshooting.md."
fi
exit "$ok"
