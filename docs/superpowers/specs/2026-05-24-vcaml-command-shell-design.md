# freight.ml VCaml Command Shell Design

Date: 2026-05-24

## Goal

Build the first real VCaml executable milestone for freight.ml: a persistent Neovim plugin shell that registers commands, owns plugin state, creates scratch buffers, and proves the OCaml core library can be driven from Neovim without executing HTTP requests yet.

## Context

The pure core library milestone is complete and merged in PR #1. The library exposes parsing, environment substitution, curl argument construction, response helpers, chaining, and buffer-name helpers without VCaml, Async, or Core dependencies.

This milestone begins the executable layer. It may depend on VCaml, Async, and Core, but `lib/` must remain pure.

## Architecture

### Dependency boundary

- `lib/` remains unchanged unless a small helper is required for bin integration.
- `bin/` depends on `freight`, `vcaml`, `async`, and `core`.
- Process execution remains out of scope; no curl subprocess is launched in this milestone.

### Plugin state

The plugin process owns mutable state:

```ocaml
type state = {
  mutable active_env : string option;
  mutable response_history : string list;
  mutable env : Freight.Env.t;
}
```

`response_history` stores response or diagnostic buffer names for now. Later milestones can switch it to richer response metadata.

### Command surface

Register these global commands:

- `:FreightOpen`
  - Create a scratch buffer for writing `.http` requests.
  - Set `filetype=http`.
  - Prefer a simple split/current-window replacement over complex window choreography.

- `:FreightEnv [name]`
  - Set `state.active_env` to `Some name`, or clear it when no name is provided.
  - Reload env files from the current buffer's file directory when available.
  - Show the result in a freight scratch/info buffer rather than relying only on echo.

- `:FreightInspect`
  - If current buffer has `freight_curl_cmd`, display it in a freight scratch/info buffer.
  - If no metadata exists, display a friendly diagnostic in the same mechanism.

- `:FreightRun`
  - Read current buffer contents.
  - Parse using `Freight.Parser.parse_string`.
  - Select a request using the current conservative `request_at_cursor` behavior.
  - Substitute current env values.
  - Build curl args with `Freight.Executor.to_curl`.
  - Render an inspect buffer showing request name, method, URL, headers, body kind, and curl argv.
  - Do not execute curl.

### Autocmd

Register a `BufEnter` autocmd for `*.http,*.rest` that sets `filetype=http` when not already set.

### Scratch buffers

Use a common helper in `bin/` for freight scratch buffers:

1. Create scratch buffer.
2. Set name such as `freight://inspect` or `freight://error`.
3. Open it in a split or current window.
4. Set lines.
5. Set `modifiable=false` after writing.
6. Set suitable filetype (`text` for diagnostics/inspect in this milestone).

### Error handling

Errors should be inspectable in `freight://error` scratch buffers:

- Parse errors show message, line, and snippet.
- Env loading errors are not expected from the current pure API; unknown substitutions remain unchanged.
- Missing current buffer/file context shows a concise diagnostic.
- `FreightInspect` without metadata shows a diagnostic, not an exception.

## Not in scope

- Curl subprocess execution.
- Rendering real HTTP responses in Neovim.
- Response history navigation commands.
- Chaining across sequential real request execution.
- Full cursor-range parser fix.
- Rich floating-window UI.

## Acceptance criteria

- `bin/` builds with VCaml, Async, and Core dependencies.
- `lib/` has no VCaml, Async, or Core dependency.
- The plugin registers `FreightOpen`, `FreightEnv`, `FreightInspect`, and `FreightRun`.
- `FreightOpen` creates a usable scratch HTTP buffer.
- `FreightRun` on a valid `.http` buffer creates an inspect buffer showing parsed request and curl args without executing curl.
- `FreightRun` on invalid input creates `freight://error` with parse details.
- `FreightEnv` updates active environment state and reports the active environment.
- `FreightInspect` reports current curl metadata when available or a friendly diagnostic otherwise.
- `dune build` succeeds.
