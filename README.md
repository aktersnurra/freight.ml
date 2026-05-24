# freight.ml

A Neovim HTTP client plugin written in OCaml. Parses JetBrains-style `.http` files, substitutes environment variables, builds and executes `curl` invocations, and renders responses in scratch buffers — all driven by a persistent VCaml process communicating with Neovim over msgpack RPC.

## Status

The core library and Neovim command shell are implemented. HTTP execution (actually running curl) is not yet wired up; `:FreightRun` currently renders the parsed request and curl arguments without firing the request.

## Requirements

- Neovim ≥ 0.11
- OCaml ≥ 5.1
- dune ≥ 3.17
- curl (runtime)
- opam packages: `angstrom`, `yojson`, `re`, `vcaml`, `async`, `core`

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

```vim
let g:freight_executable = '/path/to/main.exe'
```

## Commands

| Command | Description |
|---|---|
| `:FreightStart` | Start the plugin process manually |
| `:FreightOpen` | Open a scratch buffer with `filetype=http` for writing requests |
| `:FreightRun` | Parse the current buffer, select the request at cursor, substitute env, and render the curl invocation in an inspect buffer |
| `:FreightEnv [name]` | Set the active environment (e.g. `:FreightEnv staging`). Omit the name to clear it |
| `:FreightInspect` | Show the curl metadata for the current buffer, or a diagnostic if none exists |

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

## Development

```sh
# Build
dune build

# Run all tests (OUnit2 + QCheck property-based tests)
dune build @test/runtest

# Run only the property-based tests
dune exec test/test_qcheck.exe

# Run with more QCheck examples
dune exec test/test_qcheck.exe -- --verbose
```

CI runs on every push and pull request via GitHub Actions (OCaml 5.2, ubuntu-latest).

## Project layout

```
lib/        Pure OCaml library (no VCaml/Async/Core dependency)
  ast.ml      Core domain types: method_, request, response, parse_error
  parser.ml   Angstrom parser for .http files
  env.ml      .env file loading and {{variable}} substitution
  executor.ml curl invocation builder
  response.ml curl output parsing and response rendering
  chaining.ml JSON path extraction and env injection for named requests
  buffer.ml   Neovim buffer name helpers

bin/        VCaml executable (Neovim plugin process)
  main.ml     Plugin entry point, command registration
  handlers.ml FreightOpen / FreightRun / FreightEnv / FreightInspect
  scratch.ml  Scratch buffer helpers
  state.ml    Mutable plugin state

test/
  test_freight.ml   OUnit2 example-based tests (28 tests)
  test_qcheck.ml    QCheck2 property-based tests (20 properties)

plugin/freight.vim    Vim command definitions and autostart autocmd
autoload/freight.vim  Job management and RPC channel helpers
```
