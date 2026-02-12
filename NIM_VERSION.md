# PicoClaw Nim Reimplementation

This is a feature-complete, performance-optimized Nim reimplementation of the PicoClaw project.

## Features

* **Ultra-lightweight**: Binary size ~600KB (Go version ~24MB).
* **Minimal RAM**: Uses Nim's ARC memory management for deterministic behavior and low overhead.
* **Feature Parity**: Replicates all original PicoClaw features including:
    * CLI commands and flags.
    * Agent workflow and iteration loop.
    * Multiple LLM providers (OpenAI-compatible, Anthropic, Codex).
    * Gateway integrations (Telegram, Discord, QQ, DingTalk, etc.).
    * Tool system (Filesystem, Shell, Web, etc.).
    * Cron and Heartbeat services.
    * Migration from OpenClaw.

## Build Instructions

### Prerequisites
* Nim 2.0 or higher.

### Compilation
To build the production-ready optimized binary:
```bash
make build
```
The binary will be located at `src/picoclaw`.

### Debug Build
```bash
make debug
```

## Migration Guide from Go PicoClaw

1. **Binary replacement**: Simply replace your existing `picoclaw` binary with the Nim-compiled version.
2. **Configuration**: The Nim version uses the same `~/.picoclaw/config.json` and workspace layout. No changes are required to your existing setup.
3. **Environment Variables**: All `PICOCLAW_*` environment variables are supported identically.

## Optimizations

* **Memory Management**: Compiled with `--mm:arc` to eliminate GC pauses.
* **Binary Size**: Compiled with `-d:danger`, `--opt:size`, and LTO for maximum reduction.
* **Cold Start**: Significantly faster cold start due to minimal runtime overhead.
