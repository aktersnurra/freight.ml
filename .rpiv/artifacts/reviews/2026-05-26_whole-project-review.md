---
repository: freight
branch: detached / jj working copy @ abf0f20c
commit: 7a1c2df6
scope: whole-project
date: 2026-05-26T22:00:15+02:00
reviewer: pi
status: needs_changes
verification: "dune runtest failed; dune build @install passed"
---

# Whole Project Review

This is a broad code health review of the Freight OCaml/Neovim project, not a diff review. Lenses covered OCaml core API design, Eio/runtime/RPC behavior, Neovim plugin integration, tests, packaging, and documentation.

## 🔴 Critical

### C1 — `FreightRun` sends each request twice

Evidence:
- `bin/handlers.ml:122` — `let run_result = Freight_effect.run_curl invocation in`
- `bin/handlers.ml:123` — `let verbose_result = Freight_effect.run_curl_verbose invocation in`

The verbose path runs a second `curl` subprocess with the same invocation rather than deriving verbose output from the original execution. Mutating requests (`POST`, `PUT`, etc.) can therefore execute side effects twice.

## 🟡 Important

### I1 — Neovim RPC errors can strand callers forever

Evidence:
- `bin/nvim_rpc.ml:37` — `| Msgpck.String s -> failwith ("nvim rpc error: " ^ s)`
- `bin/nvim_rpc.ml:41` — `Eio.Promise.resolve resolver value`

`resolve_pending` raises before resolving the promise when Neovim returns an RPC error. The reader fiber only catches EOF, so a caller awaiting the pending promise can block indefinitely.

### I2 — Tests do not currently pass in this environment

Evidence:
- `test/dune:9` — `(libraries freight qcheck-core qcheck-core.runner)`
- Verification command: `opam exec -- dune runtest`
- Failure: `Error: Library "qcheck-core.runner" not found.`

The non-QCheck tests ran successfully, but the full test alias fails before `test_qcheck` can build.

### I3 — Package metadata omits required dependency and OCaml lower bound

Evidence:
- `freight.opam:14` — `"ocaml"`
- `freight.opam:16` — `"angstrom"`
- `bin/dune:12` — `(libraries freight freight_plugin msgpck eio eio_main eio_posix cstruct)`

The executable links `cstruct`, but package metadata does not declare it directly. The opam file also permits unconstrained OCaml even though the implementation uses OCaml 5 effects.

### I4 — Scratch buffer wipeout builds an Ex command from unescaped request names

Evidence:
- `bin/scratch.ml:14` — `[ Msgpck.String (Printf.sprintf "silent! bwipeout %s" name) ]);`
- `lib/parser.ml:31` — `let name = String.sub trimmed 7 (String.length trimmed - 7) |> trim in`

Request names flow into an Ex command without escaping. Names containing spaces or command separators can break the command and may execute unintended Ex syntax.

### I5 — Relative body file paths are resolved against Neovim cwd, not request file directory

Evidence:
- `lib/parser.ml:85` — `Ast.Body_file (String.sub trimmed 1 (String.length trimmed - 1) |> trim)`
- `lib/executor.ml:14` — `| _ -> [ "--data-binary"; "@" ^ path ])`
- `bin/freight_runtime.ml:29` — `("curl" :: invocation.Freight.Executor.args)`

`< ./body.json` is passed to curl unchanged, and the runtime does not set the subprocess cwd to the `.http` buffer directory. This makes request files less portable and surprising.

### I6 — Malformed headers are silently dropped

Evidence:
- `lib/parser.ml:102` — `let header_lines, body_lines = split_at_blank rest in`
- `lib/parser.ml:103` — `let headers = List.filter_map parse_header header_lines in`

The parser accepts a header section with invalid header lines and discards those lines instead of returning `Ast.parse_error`.

### I7 — Concurrent request completions race on global state

Evidence:
- `bin/handlers.ml:121` — `Freight_effect.fork "FreightRun" @@ fun () ->`
- `bin/handlers.ml:142` — `Freight.Chaining.inject ~name:req_name response state.State.env;`
- `bin/handlers.ml:143` — `state.State.last_response <- Some response;`

Multiple `FreightRun` jobs can complete out of order; completion order determines `last_response`, env injection, verbose output, and history ordering.

## 🔵 Suggestions

### S1 — Parser error locations are misleading

Evidence:
- `lib/parser.ml:15` — `let make_error ?(line = 1) ?(snippet = "") message =`
- `lib/parser.ml:120` — `match parse_block block with`

The public parse error exposes `line`, but block parsing does not preserve the original line number, so many errors report line 1.

### S2 — Public AST allows invalid domain values

Evidence:
- `lib/ast.mli:18` — `type request = {`
- `lib/ast.mli:21` — `url : string;`
- `lib/ast.mli:27` — `status : int;`

The public records allow invalid URLs, status codes, durations, and headers. This is manageable in a small codebase, but it weakens the `.mli` as the design boundary.

### S3 — Plugin command surface is only partially available before process startup

Evidence:
- `plugin/freight.lua:8` — `vim.api.nvim_create_user_command("FreightStart", function()`
- `plugin/freight.lua:16` — `pattern = { "*.http", "*.rest" },`
- `bin/main.ml:20` — `cmd "FreightRun"         `None     "FreightRun";`

Only `:FreightStart` is registered by Lua; other commands are registered by the running OCaml process. In buffers not covered by autostart, `:FreightRun` can be unavailable.

### S4 — README command table is behind implementation

Evidence:
- `bin/main.ml:24` — `cmd "FreightHelp"        `None     "FreightHelp";`
- `bin/main.ml:25` — `cmd "FreightHistory"     `None     "FreightHistory";`
- `README.md:68` — ``| `:FreightView <Body\|Headers\|All>` | Switch the response buffer view (also mapped to `B`, `H`, `A` keys) |``

Implemented help/history commands and `FreightView Verbose` are not reflected in the README command table.

## Strengths

- Clear separation between core library (`lib/`) and editor/runtime integration (`bin/`, `lua/`, `plugin/`).
- Core parser/resolver APIs generally use `result` rather than exceptions.
- `Env.t` is abstract in the public interface.
- Handler tests use a fake effect interpreter, which is a good fit for the effect-based runtime design.
- CI exists and runs tests on push/PR.

## Verification

Commands run:

- `opam exec -- dune runtest` — failed because `qcheck-core.runner` was not found; other OUnit suites completed successfully.
- `opam exec -- dune build @install` — passed with no output.

