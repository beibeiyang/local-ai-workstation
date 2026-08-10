# Security

This box is going to run increasingly capable, increasingly autonomous agents. Start with limited permissions and widen them deliberately, once you understand exactly what each layer can do — not by default.

## Network exposure

-   Never forward router ports 22, 11434 (Ollama), 3000 (Open WebUI), or an agent gateway port to the public internet.
-   Use SSH keys for access; only disable SSH password authentication after key-based login is confirmed working.
-   For access away from home, use Tailscale and keep the same SSH tunnels — do not port-forward through the router as an alternative. See [Taking it on the road](architecture.md#taking-it-on-the-road-tailscale) in the architecture doc for how that fits together.
-   Ollama and Open WebUI reach the Mac only through SSH local port forwarding (see [`config/ssh-config.example`](../config/ssh-config.example)), never through a router-forwarded port.
-   Know which of the two is actually loopback-bound. Open WebUI is (`127.0.0.1:3000:8080` in [`config/docker-compose.yml`](../config/docker-compose.yml)). Ollama is not: [`scripts/bootstrap-windows.ps1`](../scripts/bootstrap-windows.ps1) sets `OLLAMA_HOST=0.0.0.0:11434` so WSL2 and Docker can reach it, and constrains it with a firewall rule limited to the **Private** profile and `LocalSubnet`. On any network you don't control, make sure Windows has that connection marked **Public** — the rule is intentionally absent there, and Ollama has no authentication of its own.

## Agent permissions — what not to grant on day one

Do not give a new autonomous agent (OpenCode, Hermes, OpenClaw, or anything else) any of the following until you've watched it operate with less:

-   Your entire Windows home directory.
-   Personal email or calendar.
-   AWS administrator credentials, or any long-lived cloud admin credentials.
-   Production databases.
-   GitHub organization-wide tokens.
-   The ability to merge or deploy without human review.

For the first week, scope agent file access to a single project directory, e.g. `~/src/current-project`, not `~/src` as a whole and not the Windows filesystem under `/mnt/c`.

## Per-project hygiene

-   One GitHub repository per product.
-   One `.env` per repository, never committed.
-   Short-lived, least-privilege credentials — not personal or org-wide tokens.
-   Separate development resources (databases, buckets, API keys) from production ones.

## Example: OpenCode permission config

[`config/opencode.json.example`](../config/opencode.json.example) ships with a conservative default: shell commands default to `ask`, destructive commands (`rm *`, `git push*`) are denied outright, `.env` files are excluded from reads even though other files default to allowed, and external directories are denied. Treat this as a floor, not a ceiling — tighten further for anything touching production.

## NVIDIA driver boundary

Not a credentials issue, but a system-integrity one: install the NVIDIA driver once, on Windows. Do not `apt install nvidia-driver` inside Ubuntu/WSL — WSL exposes the Windows GPU driver to Linux, and installing a second Linux-native driver can break that arrangement. See [`architecture.md`](architecture.md) for why.