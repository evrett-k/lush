# Lush — Developer Reference

Lush is a Lua-powered interactive shell. It is a superset of Lua — any valid Lua runs natively, and shell-style syntax is transparently rewritten into Lua before execution.

## Architecture

```
src/
  main.rs      Entry point, arg parsing, script dispatch (yash + lua fallback)
  lush.rs      Engine init, precompiler, builtins, trap registry
  repl.rs      Interactive REPL, signal monitoring, highlighting, history
tests/         Integration test suite (test_all.lua)
```

## How execution works

1. **Input:** REPL line or script file.
2. **Pre-processing:**
   - Lines starting with `--` or `#` are treated as comments.
   - Shell macros (`ls`, `cd`, etc.) are rewritten as Lua function calls.
3. **Execution:**
   - Lush attempts to execute the code via the Lua VM.
   - If Lua execution fails, Lush falls back to `yash` (POSIX-compliant shell) for advanced constructs like pipes `|`, redirects `>`, `&`, or logic `&&`/`||`.

## Config

`~/.lush.lua` — loaded on startup, runs as plain Lua after builtins are registered.

```lua
use_starship = false   -- false to use built-in prompt

-- Trap Example
trap("SIGINT", function()
    print("\nCaught Ctrl+C!")
end)

function gs() git("status") end
```

## Built-in commands (Lua functions)

Lush includes native builtins: `ls(path?)`, `cd(path?)`, `cat(file)`, `mv(src, dest)`, `cp(src, dest)`, `mkdir(dir)`, `touch(file)`, `rm(path)`, `pwd()`, `clear()`, `whoami()`, `echo(str)`, `reload()`, `trap(sig, func)`, `exec(cmd, args...)`.

## Shell Integration

- **`.sh`:** Executed via internal `yash`.
- **`.fish` / `.ps1` / `.cmd` / `.bat`:** Dispatched to the respective system shell binary.
- **`.lua` / `.lush`:** Executed via the internal Lush precompiler/Lua VM.

## PATH augmentation

On startup `init_engine` adds common macOS/Linux locations to `PATH`:
- `/usr/local/bin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/sbin`
- `~/.cargo/bin`

## REPL features

- **Tab completion** — commands from PATH + builtins + filenames.
- **Ghost text hints** — history/command hints rendered in gray.
- **Syntax highlighting** — Green (known), Yellow (partial), Red (unknown).
- **Persistent history** — saved to `~/.lush_history`.
- **Signal monitoring** — `SIGINT` (Ctrl+C) is monitored via an async task; supports custom Lua `trap` hooks.

## Building & Testing

```bash
cargo build           # debug build
./tests/test_all.lua  # run master test suite
```

## CI/CD
Local testing available via `act` (GitHub Actions runner).

