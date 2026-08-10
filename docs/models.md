# Which local models to run

Don't pull every interesting model. Model collecting wastes SSD space and
makes evaluation unfocused. Pick one primary coder, one alternative
evaluator, and use hosted APIs for frontier-scale models.

| Model | Practical role | Recommendation |
|---|---|---:|
| `qwen3.5:9b` | Coding, tools, planning, general agent work | **Default model now** |
| `gemma4:12b` | Second opinion, documents and images | **Install now** |
| `gpt-oss:20b` | More capable reasoning/tool use | Test after a RAM upgrade |
| `qwen3.6:27b` | Larger coding/reasoning model | Likely CPU/RAM spill; skip initially |
| `qwen3-coder:30b` | Larger agentic coding model | Likely slow on 16GB VRAM |
| `qwen3-coder-next` | Very large coding model | Not appropriate to run locally |
| Kimi K3 | Frontier-scale multimodal model | Use a hosted API |

[`scripts/pull-models.sh`](../scripts/pull-models.sh) installs the two starter models by default
(conservative for a 16GB-system-RAM machine). After a RAM upgrade, or for a
deliberate one-off test:

```bash
FULL=1 ./pull-models.sh
ollama run gpt-oss:20b
ollama ps
```

## Reading `ollama ps`

For a model sized to fit the hardware, you want it reported as fully or
almost fully GPU-resident. A CPU/GPU split usually means: reduce context
size, unload another model, or drop to a smaller quantization.

## Why not Kimi K3 locally

Kimi K3 is reported as a roughly 2.8-trillion-parameter mixture-of-experts
model with about 104 billion activated parameters. Even an unrealistic raw
4-bit representation of *all* 2.8 trillion weights would need approximately:

```text
2.8 trillion × 4 bits ÷ 8 ≈ 1.4 TB
```

That's before quantization metadata, runtime buffers, or KV cache. It
doesn't fit on a 16GB RTX 5070 Ti, and it doesn't fit comfortably on a 1TB
SSD either. Use Kimi K3 (or any similarly frontier-scale model) through a
hosted provider, and route specific hard tasks to it from your coding agent
rather than trying to run it locally.

## Coding agent: OpenCode, Hermes, or OpenClaw?

Recommended order:

1. **OpenCode now** — a coding agent built for working inside a repository:
   planning, editing, testing, refactoring. It runs naturally over SSH,
   supports local Ollama and many cloud providers, and uses project
   instructions via `AGENTS.md`. This matches an SSH-from-Mac,
   work-inside-one-repo workflow directly.
2. **Hermes later** — broader than a coding agent: persistent memory, skill
   creation, web browsing, delegation, scheduled work, messaging gateways,
   multiple execution backends. It currently wants at least a 64K model
   context for its agentic workflows, which is a real cost on a 16GB-VRAM
   box — better evaluated after a RAM upgrade or with a hybrid local/cloud
   model setup. Has stronger built-in security controls than a typical
   general agent (protected credential paths, optional write sandboxes,
   container execution, command approval, gateway allowlists).
3. **OpenClaw only when there's a concrete need** for an always-on
   assistant reachable from a phone or messaging app (WhatsApp, Telegram,
   Slack, Signal, Teams, ...). It's a persistent gateway service with a
   larger security surface (channel auth, user pairing, more secrets) — not
   the best first tool for sitting down and actively developing software.
   Sandboxed tool execution exists but must be deliberately enabled, or
   tools run directly on the host.

Don't start more than one of these on day one. When several experimental
layers are running and something fails, it's hard to tell whether the
problem is the model, the tool, permissions, or the framework.

[`scripts/pull-models.sh`](../scripts/pull-models.sh) and [`scripts/bootstrap-wsl.sh`](../scripts/bootstrap-wsl.sh) install Hermes by
default but not OpenClaw. Install OpenClaw explicitly once the base stack
(Ollama, SSH, model inference, Hermes) is confirmed working:

```bash
INSTALL_OPENCLAW=1 ./bootstrap-wsl.sh
openclaw onboard --install-daemon
```
