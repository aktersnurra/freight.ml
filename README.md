# freight.ml

![freight logo](assets/freight-logo.png)

A Neovim HTTP client plugin written in OCaml. Parses JetBrains-style `.http` files, substitutes environment variables, builds and executes `curl` invocations, and renders responses in scratch buffers — all driven by a persistent OCaml process communicating with Neovim over msgpack RPC.

## Status

The core library, command shell, and HTTP execution are implemented. `:FreightRun` parses the request at cursor, substitutes environment variables, runs curl in the background, and renders the response in a scratch buffer with `B`/`H`/`A`/`V` keymaps to toggle between body, headers, full, and verbose views. `:FreightRunAll` executes every request in the current buffer and renders grouped results that can be opened with Enter.

## Requirements

- Neovim >= 0.11
- OCaml >= 5.1
- dune >= 3.21
- curl (runtime)
- Telescope.nvim (optional; required for `:FreightEnv` without an argument)
- opam packages: `angstrom`, `yojson`, `re`, `msgpck`, `eio`, `eio_main`, `eio_posix`

## Installation

### 1. Build the binary

```sh
git clone https://github.com/aktersnurra/freight.ml
cd freight.ml
opam install . --deps-only
dune build
```

### 2. Add to Neovim

**lazy.nvim:**

```lua
{
  "aktersnurra/freight.ml",
  build = "dune build",
}
```

**vim-plug:**

```vim
Plug 'aktersnurra/freight.ml', { 'do': 'dune build' }
```

The plugin auto-starts the OCaml process when you open a `*.http` or `*.rest` file. To start it manually:

```vim
:FreightStart
```

If the binary lives somewhere other than `_build/default/bin/main.exe`, point Neovim at it:

```lua
vim.g.freight_executable = '/path/to/main.exe'
```

## Commands

| Command | Description |
| --- | --- |
| `:FreightStart` | Start the plugin process manually |
| `:FreightOpen` | Open a scratch request buffer |
| `:FreightRun` | Parse the request at cursor, execute curl in the background, render the response |
| `:FreightRunAll` | Execute every request in the current buffer and show grouped Failed/Successful results |
| `:FreightEnv [name]` | Switch to the named environment, or open a Telescope picker when no name is given |
| `:FreightInspect` | Show the curl metadata for the request at cursor |
| `:FreightView <Body\|Headers\|All\|Verbose>` | Switch the clean scratch response buffer between body, sectioned headers, sectioned all, and verbose curl output (also mapped to `B`, `H`, `A`, `V` keys) |
| `:FreightHelp` | Show Freight buffer-local help and keymaps |
| `:FreightHistory` | Show recent request history |
| `:FreightViewHistory <index>` | Open a response from request history |
| `:FreightViewRunAll <line>` | Open a result from the latest run-all summary; normally used by pressing Enter in `freight://run-all` |

## HTTP file format

freight.ml parses the JetBrains `.http` subset:

```http
# @name login
POST https://api.example.com/auth
Content-Type: application/json

{"user": "{{USER}}", "password": "{{PASSWORD}}"}

###

GET https://api.example.com/profile
Authorization: Bearer {{login.response.body.token}}
```

- `###` separates requests within a file
- `# @name <name>` tags a request for chaining
- `{{KEY}}` substitutes values from `.env` files
- `< path/to/file.json` sends a file body

## Environment files

freight.ml walks up from the `.http` file's directory and merges, in order:

1. `.env`
2. `.env.<active_env>` (if an active environment is set)
3. `.env.local`

Later files win. Unknown `{{variables}}` are left unchanged.

```sh
# .env
BASE_URL=https://api.example.com

# .env.local (gitignore this)
PASSWORD=hunter2
```

## Response chaining

Named request responses are injected into the environment under `name.response.body.*` and `name.response.headers.*`:

```http
# @name login
POST {{BASE_URL}}/auth
Content-Type: application/json

{"user": "me"}

###

GET {{BASE_URL}}/profile
Authorization: Bearer {{login.response.body.token}}
```

## Architecture

freight.ml uses three cleanly separated layers:

**Pure library** (`lib/`) — parsing, environment substitution, curl argument building, response parsing and rendering, response chaining. No IO dependencies beyond Stdlib file reads for `.env` loading.

**Effect boundary** (`bin/freight_effect.ml`) — domain-level OCaml 5 effect handlers with typed wrappers. Handler code performs effects like `current_buffer`, `run_curl`, and `load_env` without knowing which runtime interprets them.

**Eio runtime** (`bin/freight_runtime.ml`, `bin/nvim_rpc.ml`) — the production effect interpreter backed by Eio for concurrency, subprocess execution, and msgpack RPC over stdin/stdout.

This separation means handler logic reads like ordinary OCaml:

```ocaml
let freight_run state =
  let buf, source, cursor_line = current_source () in
  match resolve_request state source cursor_line buf with
  | Error (`Parse err) -> (* show error *)
  | Error `No_request -> (* show error *)
  | Ok request ->
    let loading_buf = Freight_effect.show_scratch ~name ~filetype ~lines in
    Freight_effect.fork "FreightRun" @@ fun () ->
      match Freight_effect.run_curl invocation with
      | Error msg -> (* update scratch with error *)
      | Ok raw -> (* parse response, update scratch, set keymaps *)
```

No `Deferred.t`, no `let%bind`, no `don't_wait_for`. A fake test interpreter can run the same handler code without Neovim, curl, or Eio.

## Development

```sh
# Build
dune build

# Run all tests
dune build @test/runtest

# Run only the property-based tests
dune exec test/test_qcheck.exe

# Run with more QCheck examples
dune exec test/test_qcheck.exe -- --verbose
```

CI runs on every push and pull request via GitHub Actions (OCaml 5.2, ubuntu-latest).

## Project layout

```
lib/        Pure OCaml library (no Eio/Async dependency)
  ast.ml        Core domain types: method_, request, response, parse_error
  parser.ml     Angstrom parser for .http files
  env.ml        .env file loading and {{variable}} substitution
  executor.ml   Pure curl invocation builder
  resolve.ml    Request resolution: cursor selection + env substitution
  response.ml   Curl output parsing and response rendering
  chaining.ml   JSON path extraction and env injection for named requests
  buffer.ml     Neovim buffer name helpers

bin/        Neovim plugin executable
  freight_effect.ml   OCaml 5 effect definitions + typed wrappers
  freight_runtime.ml  Production Eio effect interpreter
  nvim_rpc.ml         Msgpack RPC transport over Eio
  main.ml             Entry point, command registration, dispatch loop
  handlers.ml         Direct-style command handlers (open/run/env/inspect/view)
  scratch.ml          Scratch buffer operations
  request_view.ml     Pure rendering for inspect/error/env display
  state.ml            Mutable plugin state

test/
  test_freight.ml       OUnit2 example-based tests (51 tests)
  test_qcheck.ml        QCheck2 property-based tests (30 properties)
  test_handlers.ml      Handler integration tests via fake effect interpreter
  test_runtime_fake.ml  Deterministic effect interpreter for testing

plugin/freight.lua    Neovim command definitions and autostart autocmd
lua/freight.lua       Job management and RPC channel helpers
```
