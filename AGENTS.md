# Working on this repo

Instructions for coding agents (and humans) making changes here. This is a
documentation-first repo: the scripts are small, the prose around them is the
product.

## The one rule that matters

**Every factual claim in the docs must be verifiable in `scripts/` or `config/`.**
Ports, environment variables, pinned versions, model tags, filesystem paths — read
the source file and quote what it actually does. Do not write from memory or from
how the tool usually behaves. Past failure: the docs claimed Ollama was bound to
`127.0.0.1` when [`scripts/bootstrap-windows.ps1`](scripts/bootstrap-windows.ps1)
sets `OLLAMA_HOST=0.0.0.0:11434` and constrains it with a firewall rule instead.

If a doc and a script disagree, say so — don't silently "fix" the doc to match the
script or vice versa. Which one is wrong is a decision for the maintainer.

## Conventions

-   **Versions are pinned deliberately.** `Ubuntu-24.04`, `node@24`, `python@3.12`,
    PowerShell `5.1`, and the model tags in
    [`scripts/pull-models.sh`](scripts/pull-models.sh) are load-bearing. Don't bump
    them as a drive-by. See
    [the version inventory](docs/architecture.md#tools-and-versions-this-repo-targets)
    for what's pinned vs. installed-at-current.
-   **Keep the instructions vendor-neutral.** The steps work on any Windows 11 +
    WSL2 + NVIDIA machine, so don't make the guide read as specific to one vendor's
    hardware. *Exception:* the README's "The hardware" section names the exact
    machine the author uses, on purpose. Leave it.
-   **Link in-repo file references.** Write
    ``[`config/ssh-config.example`](config/ssh-config.example)``, never a bare code
    span. Paths are relative to the linking file (`../` from inside `docs/`).
-   **Diagrams are Mermaid**, in fenced `mermaid` blocks — not committed images.
    Prose that says "see the diagram" should still make sense without it.
-   **Security posture is the point, not a detail.** Nothing gets forwarded at the
    router; remote access is SSH tunnels, or Tailscale when away from home. A change
    that widens exposure needs to say so explicitly in
    [`docs/security.md`](docs/security.md).

## Before you commit

-   Render every Mermaid block you touched and look at it:
    `npx -p @mermaid-js/mermaid-cli mmdc -i diagram.mmd -o out.png`. A block that
    parses can still lay out badly.
-   Check that relative links and `#anchors` resolve — renaming a heading breaks
    inbound anchors elsewhere in the repo.
-   Re-read changed prose against the script it describes, one more time.
