# Dynamic ($env) + Generated Values Implementation Plan

> **For agentic workers:** Steps use `- [ ]` checkboxes. TDD throughout. Warnings-are-errors (`-w @A-…`). jj + GPG-in-sandbox (retry describe/new with sandbox off). Trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

**Goal:** Two new resolver sources — `{{$env.NAME}}` (OS environment) with plain
`{{VAR}}` OS-env fallback, and generated values `{{$uuid}}` / `{{$timestamp}}` /
`{{$isoTimestamp}}` / `{{$randomInt[:a:b]}}`. `$exec` is intentionally out of
scope. Plus parser round-trip property tests (independent hardening).

**Architecture:** The pure `Resolver` (`lib/resolver.ml`) already takes an ordered
`source` list; new sources prepend without touching existing code. `$env`/plain
fallback need `Sys.getenv_opt`; generated values need a clock and RNG. `lib/`
stays pure, so these sources are constructed in `bin/handlers` as closures over
new `Freight_effect` effects (`Get_env`, `Now`, `Random_int`), then prepended to
the resolver in `build_resolver` and the run-all inline resolver. Each new effect
needs a real handler (`freight_runtime.ml`) and a fake (`test_runtime_fake.ml`).

**Tech stack:** OCaml, dune, OUnit2/qcheck, effects-based handlers with a fake.

**Resolver precedence (first wins):**
`[ generated ; dynamic($env) ; response_store ; env_with_os_fallback ]`
— generated/`$env` take precedence over `.env`; a plain `{{VAR}}` falls back to
OS env only when absent from `.env` and the store.

---

## Task 1: pure generated-values source (deterministic core)

Generated values are impure (clock/RNG), but the *formatting* is pure. Put the
pure formatting in `lib/`, injected with primitives, so it is unit-testable
without effects.

**Files:** create `lib/generated.ml` + `.mli`; `test/test_freight.ml`.

- [ ] mli:

```ocaml
type env = {
  now : unit -> float;            (** Unix seconds, e.g. Unix.gettimeofday *)
  random_int : int -> int;        (** uniform in [0, bound) *)
}

val source : env -> Resolver.source
(** Resolves [$uuid], [$timestamp], [$isoTimestamp], [$randomInt],
    [$randomInt:a:b]. Returns [None] for any other reference. *)
```

- [ ] Failing tests with a deterministic `env` (fixed `now`, counter `random_int`):
  - `$timestamp` = integer seconds of `now`.
  - `$isoTimestamp` matches `^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$`.
  - `$randomInt` in `[0,1000)`; `$randomInt:5:10` in `[5,10)`.
  - `$uuid` matches `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`.
  - unknown `$foo` → `None`.
- [ ] Implement:
  - Match the ref text: `"$timestamp"`, `"$isoTimestamp"`, `"$uuid"`,
    `"$randomInt"`, or `"$randomInt:a:b"` (split on `:`).
  - `$timestamp` → `string_of_int (int_of_float (env.now ()))`.
  - `$isoTimestamp` → format `env.now ()` as UTC via `Unix.gmtime`… but `lib/` is
    pure and must not depend on `unix`. **Instead** compute the ISO string from the
    epoch seconds with plain arithmetic (days→y/m/d) OR accept a
    `gmtime : float -> Unix.tm`-free approach. Simplest: pass the calendar break-down
    in `env` too. Add `iso_of_epoch : float -> string` to `env`:

```ocaml
type env = {
  now : unit -> float;
  random_int : int -> int;
  iso_of_epoch : float -> string;  (** e.g. via Unix.gmtime in bin/ *)
}
```

  (This keeps `lib/generated.ml` free of `unix`; the ISO formatting lives in the
  effect layer.) Update the mli test env accordingly (tests pass a stub
  `iso_of_epoch`).
  - `$uuid` → 16 bytes from `env.random_int 256`, set version nibble to 4 and
    variant to `8..b`, format `8-4-4-4-12` hex.
  - `$randomInt` → `env.random_int 1000`; `$randomInt:a:b` → `a + env.random_int (b-a)`
    (guard `b>a`; else `None`).
- [ ] Tests pass; commit `feat(generated): pure generated-value source`.

---

## Task 2: effects for OS access (Get_env, Now, Random_int, iso)

**Files:** `bin/freight_effect.ml` + `.mli`, `bin/freight_runtime.ml`,
`test/test_runtime_fake.ml`.

- [ ] Add effects + wrappers in `freight_effect`:

```ocaml
| Get_env    : string -> string option Effect.t
| Now        : unit -> float Effect.t
| Random_int : int -> int Effect.t
```

with `val get_env : string -> string option`, `val now : unit -> float`,
`val random_int : int -> int`.

- [ ] Real handlers in `freight_runtime.ml`:
  - `Get_env s` → `Sys.getenv_opt s`
  - `Now ()` → `Unix.gettimeofday ()`
  - `Random_int n` → `Random.int n` (seed once at process start:
    `Random.self_init ()` in `main.ml`'s startup — add that).
- [ ] Fake handlers + config in `test_runtime_fake.ml`:
  - config fields: `env_vars : (string*string) list`, `now : float`,
    `random_ints : int list` (a script; cycle or default 0).
  - `Get_env s` → `List.assoc_opt s env_vars`; `Now ()` → `now`; `Random_int _`
    pops the next scripted int (default 0 when exhausted).
- [ ] Build clean; commit `feat(effect): add Get_env/Now/Random_int effects`.

Note: `iso_of_epoch` is not an effect — it's a pure `float -> string` computed in
`bin/handlers` via `Unix.gmtime`, passed into the `Generated.env` record.

---

## Task 3: env source with OS fallback

**Files:** `lib/env.ml` + `.mli` OR a small combinator in `bin/handlers`.

Decision: keep `lib/` pure. `Env.source` stays as-is (`.env` only). The OS
fallback is a *separate* source built in `bin/handlers` from `Get_env`:

- [ ] In `bin/handlers`, add:

```ocaml
let env_source env = Freight.Env.source env
let os_env_source () : Freight.Resolver.source = fun ref -> Freight_effect.get_env ref
let dollar_env_source () : Freight.Resolver.source = fun ref ->
  match String.length ref > 5 && String.sub ref 0 5 = "$env." with
  | true -> Freight_effect.get_env (String.sub ref 5 (String.length ref - 5))
  | false -> None
```

  (`$env.NAME` reads OS var `NAME`; the bare-`{{VAR}}` OS fallback is `os_env_source`
  placed LAST so `.env` wins over the shell.)

No lib change needed. Test coverage comes via handler tests (Task 5).

---

## Task 4: wire sources into the resolver

**Files:** `bin/handlers.ml`.

- [ ] Build a shared `generated_env ()` in handlers:

```ocaml
let generated_env () : Freight.Generated.env =
  { now = Freight_effect.now
  ; random_int = Freight_effect.random_int
  ; iso_of_epoch = (fun t ->
      let tm = Unix.gmtime t in
      Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
        (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec)
  }
```

- [ ] In `build_resolver`, prepend generated + `$env`, append OS fallback:

```ocaml
let build_resolver state buf =
  let env = resolve_env state buf in
  Freight.Resolver.make
    [ Freight.Generated.source (generated_env ())
    ; dollar_env_source ()
    ; Freight.Response_store.source state.State.responses
    ; Freight.Env.source env
    ; os_env_source ()
    ]
```

- [ ] Mirror the same list in the run-all inline resolver (use `base_env`).
- [ ] Build clean; commit `feat(run): resolve $env and generated values`.

---

## Task 5: handler tests

**Files:** `test/test_handlers.ml`.

- [ ] `$env.API_KEY` set in fake `env_vars` → request runs with the value
  substituted in the URL/header (assert on `Run_curl` args). Unset → unresolved,
  no curl (mirrors the existing unresolved test).
- [ ] Bare `{{TOKEN}}` absent from `.env` (config.env empty) but present in
  `env_vars` → resolves (OS fallback).
- [ ] `{{$uuid}}` in a URL → curl runs; assert the arg matches the uuid regex
  (scripted `random_ints` make it deterministic).
- [ ] Build + full `dune runtest` green; commit `test(run): $env and generated value handler tests`.

---

## Task 6: parser round-trip property tests + docs

**Files:** `test/test_qcheck.ml`; `README.md`.

- [ ] Property: for a generated valid request (method + url + headers), the
  rendered `.http` text re-parses to an equal request. Use existing qcheck
  generators; keep it to the shapes the renderer supports. If no renderer exists,
  scope this to: `parse_string` of a hand-built canonical `.http` for a generated
  request round-trips its method/url/headers (skip if the effort exceeds value —
  note it and move on).
- [ ] README: document `{{$env.NAME}}`, the OS fallback, and the generated values
  under a "Dynamic values" subsection near Environment files.
- [ ] Commit `test(parser): round-trip properties` + `docs: dynamic and generated values`.

---

## Self-review

- `lib/generated.ml` has no `unix` dep (ISO formatting injected via `env`).
- Each new effect has real + fake handlers; `Random.self_init` seeded once.
- Resolver precedence: generated/$env before .env; OS fallback last.
- `$exec` is NOT implemented (out of scope by decision).
- Unknown `$foo` stays literal → unresolved → fail-fast (existing behaviour).
