# AGENTS.md

Operating contract for AI agents working in `freight.ml`. Read this before editing.
The `README.md` explains the product and the three-layer architecture — this file
covers the non-obvious things that will bite you if you don't know them.

## What this is

freight.ml is a Neovim REST client: an OCaml process speaks msgpack-RPC to nvim,
parses `.http`/`.rest` files, builds `curl` invocations, runs them, and renders
responses in scratch buffers. Handler logic is written against OCaml 5 **effects**
so the same code runs under the real Eio runtime and under a fake test interpreter.

## Layout

- `lib/` — pure library (`freight`). No IO except Stdlib file reads for `.env`.
  - `parser.ml` (`.http` → `Ast`), `ast.ml` (request/response/body/save types),
    `env.ml` (`.env` loading + `{{var}}`), `resolver.ml` (ordered source chain for
    substitution), `json_path.ml` (JSONPath subset for chaining), `response_store.ml`
    (named responses as a resolver source), `resolve.ml` (request-level substitution
    + cursor resolution), `executor.ml` (request → curl args), `response.ml`
    (curl output → `Ast.response` + rendering), `buffer.ml` (buffer names/filetypes).
- `bin/` — the plugin (`freight_plugin` library + `main` executable).
  - `freight_effect.ml` — the effect definitions + typed wrappers (the boundary).
  - `freight_runtime.ml` — the real Eio interpreter (subprocess, RPC, filesystem).
  - `handlers.ml` — command handlers (`freight_run`, `freight_run_all`, …). Ordinary
    OCaml; performs effects, never touches Eio/nvim directly.
  - `state.ml` — mutable session state (history, response store, active env, buffers).
- `test/` — `test_freight.ml` (OUnit2, lib), `test_qcheck.ml` (property tests),
  `test_handlers.ml` + `test_runtime_fake.ml` (handlers run against a fake effect
  interpreter that records calls).
- `lua/`, `plugin/` — the nvim side (Lua): launches the process, registers commands.

## Build & test

```sh
dune build                       # builds; ignore "duplicate -lunwind libraries" warnings
dune runtest                     # all suites
dune exec test/test_freight.exe  # lib + parser + resolver + json_path + chaining
dune exec test/test_handlers.exe # handler behaviour via the fake runtime
dune exec test/test_qcheck.exe   # property tests (prints "success (ran N tests)")
```

Filter noise with `2>&1 | grep -v "duplicate libraries"`. OUnit only prints
failures, so `Ran: N tests ... OK` means everything passed.

## Non-obvious rules (these have caused real bugs)

- **Warnings are errors.** Every library sets `-w @A-4-33-40-41-42-43-34-44`. Unused
  vars/opens, non-exhaustive matches, and ambiguous doc comments all fail the build.
  After a refactor, delete now-dead bindings or the build breaks.
- **`lib/buffer.ml` shadows stdlib `Buffer`.** Inside `lib/`, use `Stdlib.Buffer.*`
  if you need the stdlib buffer.
- **`.mli` doc-comment placement.** A `(** … *)` sandwiched between two `val`s with
  no blank line is an "ambiguous documentation comment" error. Put a blank line
  before AND after each doc comment.
- **Render JSON scalars with Yojson, not `string_of_*`.** `string_of_float 9.0` is
  `"9."` (invalid JSON). See `Json_path.scalar_to_string` — floats go through
  `Yojson.Safe.to_string`.
- **dune ignores directories starting with `_`.** Don't scaffold throwaway dune
  targets in `_foo/`; dune won't see them. Use a normal name and delete after.
- **Effects come in pairs.** Any new `Freight_effect` effect needs: the variant +
  wrapper in `freight_effect.ml`/`.mli`, a real handler in `freight_runtime.ml`, AND
  a fake handler + config field in `test/test_runtime_fake.ml`. Miss the fake and
  handler tests won't compile.

## Substitution model (`{{var}}`)

- A `Resolver.t` is an ordered list of `source : string -> string option`. First
  source that resolves a ref wins; unresolved refs are left **literal** and reported
  by `Resolver.unresolved` so the handler can **fail fast** before invoking curl.
- Substitution is a **single pass** — resolved values are not re-scanned.
- Response chaining lives in `State.responses` (a `Response_store`), exposed as a
  resolver source. `{{name.response.body.<jsonpath>}}` supports nested objects and
  arrays (`data.items[0].id`, `.n` or `[n]`); `{{name.response.headers.<h>}}` is
  case-insensitive. Do **not** reintroduce flat-env injection of `*.response.*` keys.

## Testing conventions

- New behaviour → a test first (TDD). Lib/parse/substitution tests go in
  `test_freight.ml`; handler behaviour in `test_handlers.ml` against the fake runtime.
- Assert **behaviour, not internals.** Prefer "curl ran with URL X" over
  "`state.env` contains key Y". A white-box assertion on internal state cost this
  project a refactor snag.
- `Ast.request` literals in tests must include every field (`save_to`, etc.).

## Version control (jujutsu, NOT git)

- Use `jj`, never `git`. No staging: `jj describe -m "…"` names the current change,
  `jj new` starts the next. `jj bookmark set master -r @-` then `jj git push
  --bookmark master` to publish.
- **Commits are GPG-signed.** In a sandbox, `jj describe`/`jj new`/`jj git push` may
  fail with a GPG/`No secret key`/`.gnupg` permission error — that's the sandbox, not
  a real failure. Retry the exact command with the sandbox disabled.
- Conventional Commits (`feat(scope):`, `fix(scope):`, `refactor(scope):`). End
  commit messages with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

## Running it in Neovim (why "my fix didn't work")

nvim does not run this repo directly. A plugin manager (lazy.nvim) keeps its **own
clone**, e.g. `~/.local/share/nvim/lazy/freight.ml/`, and launches
`_build/default/bin/main.exe` from **that** copy via `jobstart`. Two consequences:

- Editing source here does nothing until that copy is updated **and rebuilt**
  (`dune build`). lazy.nvim pulls source on update but does not run dune — add
  `build = "dune build"` to the plugin spec, or rebuild the clone by hand.
- A running nvim holds the old process in memory. After a rebuild, run
  `:FreightRestart` (or restart nvim) to relaunch the new binary.

## End-to-end verification

Unit tests prove the code agrees with itself; they do not prove it agrees with a
real server or a real `curl -o`. For anything touching curl args, binary bodies, or
chaining against live JSON, verify against a real endpoint (`httpbin.org` /
`postman-echo.com`) — build a small throwaway executable that links the `freight`
library, run it, delete it. This session's "Saved 0 bytes" and float-rendering bugs
both passed unit tests and only surfaced under real conditions.
