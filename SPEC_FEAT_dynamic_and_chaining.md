# Spec: dynamic variables, deep chaining, assertions, generated values

Four related enhancements to freight's variable/verification layer. They share
one substitution engine, so they are specified together and should land in the
order below (each builds on the previous).

- **#1 Dynamic variable sources** — pull values from OS env, a shell command, or
  fall back to OS env for plain `{{VAR}}`.
- **#2 Deep response chaining** — resolve nested / array paths from prior
  responses lazily.
- **#3 Assertions** — declare expected status / body / headers so run-all is a
  smoke suite.
- **#4 Generated values** — `{{$uuid}}`, `{{$timestamp}}`, `{{$randomInt}}`.

Guiding principles (unchanged from the codebase today):
- Substitution is a single left-to-right pass; results are **not** re-expanded.
- Unknown `{{...}}` are left literal and surfaced by `Env.unresolved` →
  fail-fast before curl (already implemented).
- Effects at the boundary: anything touching the OS (env, exec, clock, RNG)
  goes through a `Freight_effect` effect with a fake in tests. `lib/` stays
  pure and deterministic.

---

## Cross-cutting: the substitution model changes

Today `Env.substitute : t -> string -> string` resolves `{{key}}` from a flat
string map. Two of these features (deep chaining, generated values) cannot be
precomputed into a flat map — nested JSON is resolved on demand, and generated
values must be produced per occurrence. So the substitution engine gains a
**resolver** abstraction while keeping the flat-map fast path.

```ocaml
(* lib/resolver.mli — new *)
type t
(* Ordered chain of sources tried left-to-right for each {{ref}}. *)

type source = string -> string option
(* Given the raw reference text (without braces, trimmed), return a value
   or None to defer to the next source. *)

val of_env : Env.t -> source
val make : source list -> t
val resolve : t -> string -> string
(* Replace every {{ref}} using the source chain; unresolved refs stay literal. *)

val unresolved : t -> string -> string list
(* Sorted, deduped refs no source could resolve. *)
```

`Env.substitute env s` becomes `Resolver.resolve (Resolver.make [Resolver.of_env env]) s`.
`Resolve.substitute_request` and `Resolve.unresolved_request` take a
`Resolver.t` instead of an `Env.t`. The handler builds the resolver once per
run from: dynamic sources (#1), the response store (#2), generated values (#4),
then the plain env — in that precedence order.

The `{{...}}` regex widens from `[A-Za-z_][A-Za-z0-9_.-]*` to also allow the
prefix sigil `$`, `:` (for `$exec:`), `[` `]` and `.` for paths:
`\{\{[ \t]*([^}]+?)[ \t]*\}\}` with the inner text trimmed. Each source decides
whether it recognizes a given ref, so the regex just captures "something
between braces".

Acceptance for the refactor: all existing env/resolve/qcheck tests pass
unchanged (behavior identical for plain `{{VAR}}`); no source in the default
chain except `of_env` unless a feature below adds one.

---

## Feature #1 — dynamic variable sources

Reference forms:

| Ref | Source | Example |
|-----|--------|---------|
| `{{$env.NAME}}` | OS environment variable `NAME` | `Authorization: Bearer {{$env.API_KEY}}` |
| `{{$exec:command}}` | stdout of `command` (trimmed), **guarded** | `X-Id-Token: {{$exec:gcloud auth print-identity-token}}` |
| `{{VAR}}` (unprefixed) | `.env` files, then OS env fallback | plain, `$dotenv` passthrough |

### Effects (bin/freight_effect)

```ocaml
| Get_env  : string -> string option Effect.t          (* Sys.getenv_opt *)
| Run_shell : string -> (string, string) result Effect.t  (* stdout of a command *)
```

`Run_shell` runs the command via the OS shell (`/bin/sh -c`), captures stdout,
trims trailing newline. Errors (non-zero exit, spawn failure) → `Error msg`.

### Sources (lib + bin bridge)

`$env` and unprefixed-fallback need `Get_env`; `$exec` needs `Run_shell`. Since
`lib/` is pure, the **sources are constructed in `bin/handlers`** from closures
over the effect functions, and passed into the `Resolver.t`. `lib/resolver.ml`
stays pure — it just calls the `source` functions.

Precedence for the resolver chain (first match wins):
`[ generated (#4) ; response_store (#2) ; dynamic ($env/$exec) ; env_with_os_fallback ]`

`env_with_os_fallback`: try `Env.find`, then `Get_env`. (This is the
`$dotenv passthrough` behaviour — plain `{{DATABASE_URL}}` resolves from the
shell if not in a `.env`.)

### $exec guard (security)

Running shell commands from a `.http` file is arbitrary code execution. It is
**off by default**.

- A per-source flag `~allow_exec:bool` decides whether `$exec:` resolves.
  When disabled, `{{$exec:...}}` resolves to `None` → treated as unresolved →
  fail-fast message: *"$exec is disabled — set g:freight_allow_exec = true to
  enable running shell commands from .http files."*
- The nvim side exposes `vim.g.freight_allow_exec` (default `false`), passed to
  the process at request time (via an RPC arg or read from a config effect).
- **No implicit trust escalation.** The flag is the only gate; freight does not
  prompt-and-remember (keeps the model simple and auditable). Document the risk
  prominently in the README.
- `$exec` output is **not** re-expanded (single-pass rule), so a command that
  prints `{{X}}` cannot inject further refs.

### Failure modes

- `$env.MISSING` → unresolved → fail-fast (names `$env.MISSING`).
- `$exec` command fails → the run fails with *"$exec failed: <ref> — <stderr/msg>"*
  (distinct from "unresolved"; the ref was recognized but errored).
- `$exec` disabled → unresolved with the guard message above.

### Tests

- Resolver unit: `$env.X` resolves from a fake `Get_env`; missing → unresolved.
- `$exec:cmd` resolves from fake `Run_shell` returning `Ok "tok\n"` → `"tok"`;
  `allow_exec=false` → unresolved with guard message; `Error` → run-fail message.
- Unprefixed fallback: key absent from env but present in fake `Get_env` resolves.
- Handler: a request using `{{$env.API_KEY}}` with the fake env set runs curl
  with the value substituted; with it unset, does **not** run curl and shows the
  unresolved message (mirrors existing `test_freight_run_unresolved_var_does_not_curl`).

---

## Feature #2 — deep response chaining (lazy JSONPath)

Today `Chaining.inject` flattens only **top-level** JSON fields into
`name.response.body.<key>` env entries. Replace this with a **response store**
resolved lazily, so nested objects and arrays work without key explosion.

### Model

```ocaml
(* lib/response_store.mli — new (or fold into chaining.ml) *)
type t                                   (* name -> Ast.response *)
val empty : t
val record : name:string -> Ast.response -> t -> t
val source : t -> Resolver.source        (* resolves name.response.* refs *)
```

`source` recognizes refs matching:
`<name>.response.body(.<path>)?` and `<name>.response.headers.<header>`
where `<path>` is a dotted/bracketed JSONPath subset:

- `.field` — object key
- `[n]` — array index (0-based), also accept `.n`
- chained: `data.items[0].id`, `data.items.0.id`

Resolution: look up `name` → parse `response.body` as JSON (cache the parse
per name per resolve pass) → walk the path → scalar (`string`/`int`/`float`/
`bool`/`null`) becomes a string via the existing `scalar_to_string`. Non-scalar
leaf or missing path → `None` (unresolved). Headers unchanged (case-insensitive).

### State change

`state.env` no longer accrues `*.response.*` keys. Instead `State.t` gains
`mutable responses : Response_store.t`. `record_response` calls
`Response_store.record`. The resolver chain includes `Response_store.source`.
This keeps chaining vars out of the flat env (cleaner) and out of any
`:FreightEnv` variable listing.

Back-compat: existing behaviour (`login.response.body.token` for a top-level
`token`) still works — it's the depth-1 case.

### Tests

- `data.token` (nested), `items[0].id` and `items.0.id` (array), header lookup.
- Missing path / non-scalar leaf → unresolved (fail-fast).
- Handler: two-request sequence where the second uses
  `{{first.response.body.data.id}}` resolves after the first runs (extends the
  existing `chaining_survives_across_runs` test).
- Malformed JSON body → the ref is unresolved, not a crash.

---

## Feature #3 — assertions

Let a request declare expectations; run-all (and run) report pass/fail against
them, turning runbooks into smoke tests.

### Syntax (metadata comments, like `# @name`)

```http
# @name create
# @expect status 201
# @expect header Content-Type contains application/json
# @expect body data.id exists
# @expect body data.status == active
POST {{BASE_URL}}/widgets
...
```

Grammar per line: `# @expect <target> <predicate>`
- `status <int>` — exact status match (also allow `status 2xx` class? — v1: exact only)
- `header <name> <op> <value>` — `op` ∈ `equals` | `contains`
- `body <path> <op> [value]` — `op` ∈ `exists` | `==` | `!=` | `contains`;
  `<path>` reuses the #2 JSONPath walker

### AST

```ocaml
type assertion =
  | Expect_status of int
  | Expect_header of { name : string; op : [`Equals|`Contains]; value : string }
  | Expect_body of { path : string list; op : [`Exists|`Eq|`Neq|`Contains]; value : string option }

(* request gains: *)
  assertions : assertion list;   (* [] when none *)
```

Parser: collect `# @expect` lines in the same leading-metadata scan that
handles `# @name`. Unrecognized `@expect` forms → parse error with the line
number (consistent with existing error reporting).

### Evaluation

```ocaml
(* lib/assertion.mli *)
type failure = { assertion : Ast.assertion; detail : string }
val check : Ast.response -> Ast.assertion list -> failure list
```

Pure, reuses the JSONPath walker from #2 and the header lookup from `Response`.

### Integration

- `freight_run`: after a response, if `assertions <> []`, run `check`. Append an
  **"Assertions"** section to the response buffer: `✓`/`✗` per assertion with the
  detail on failure. A response that is otherwise 200 but fails an assertion is
  still shown (not an error), but flagged.
- `freight_run_all`: an assertion failure classifies the entry as
  `Run_all_failure` (reuses the existing failed/successful grouping) with a
  message like `assertion failed: body data.id exists`. This is the payoff —
  run-all becomes a pass/fail suite.

### Tests

- Parser: each assertion form; malformed → parse error at correct line.
- `Assertion.check`: status pass/fail, header equals/contains, body
  exists/==/contains against a sample response; nested path via JSONPath.
- Handler: run-all with a failing assertion lands in the "Failed" section;
  all-passing lands in "Successful".

---

## Feature #4 — generated values

Per-occurrence generated values. Small, self-contained, done last.

| Ref | Value |
|-----|-------|
| `{{$uuid}}` | a v4 UUID |
| `{{$timestamp}}` | Unix seconds (integer) |
| `{{$isoTimestamp}}` | ISO-8601 UTC (`2026-07-02T18:00:00Z`) |
| `{{$randomInt}}` | random int in `[0, 1000)` |
| `{{$randomInt:a:b}}` | random int in `[a, b)` |

### Effects

```ocaml
| Now : float Effect.t          (* Unix.gettimeofday *)
| Random_int : int -> int Effect.t   (* uniform [0, bound) *)
```

UUID v4 is built from `Random_int` bytes (no new dep) — 16 random bytes with
the version/variant nibbles set, formatted `8-4-4-4-12`.

### Source

A `generated` source (constructed in `bin/handlers` over the effect fns) placed
**first** in the resolver chain. Each recognized ref produces a fresh value on
each occurrence — note this means two `{{$uuid}}` in one request differ (correct
for idempotency keys). Determinism in tests comes from the fake `Random_int`/
`Now`.

### Tests

- Fake `Now`/`Random_int`: `$timestamp`, `$isoTimestamp`, `$randomInt`,
  `$randomInt:5:10` (bounds), `$uuid` shape (`^[0-9a-f]{8}-...-4[0-9a-f]{3}-...`).
- Unknown `$foo` stays literal → unresolved.

---

## Sequencing & risk

1. **Resolver refactor** (cross-cutting) — pure, behaviour-preserving, unlocks
   the rest. Highest care: keep all existing tests green.
2. **#2 deep chaining** — smallest feature-add on top of the resolver; moves
   chaining out of the flat env (also simplifies #1's precedence).
3. **#1 dynamic sources** — adds `Get_env`/`Run_shell` effects; `$exec` guard is
   the main design risk (document loudly, default off).
4. **#4 generated values** — trivial once the resolver + effects exist.
5. **#3 assertions** — independent of the resolver; can be built in parallel,
   but reuses #2's JSONPath walker, so land after #2.

Each feature ships as its own commit with tests, README updates (HTTP file
format section), and `:FreightHelp` entries where user-visible.
```
