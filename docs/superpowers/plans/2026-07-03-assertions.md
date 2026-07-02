# Assertions (`# @expect`) Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax. TDD throughout.

**Goal:** Let a request declare expectations via `# @expect …` metadata; evaluate
them against the response so `:FreightRun` shows pass/fail and `:FreightRunAll`
classifies an assertion failure as a failed entry — turning runbooks into smoke
suites.

**Architecture:** A new `assertion` sum type on `Ast.request` (`assertions` list,
`[]` when none). The parser collects `# @expect` lines in the leading-metadata
scan (beside `# @name`); malformed forms are parse errors with a line number. A
pure `lib/assertion.ml` evaluates assertions against an `Ast.response`, reusing
`Json_path` (body paths) and case-insensitive header lookup. Handlers render an
"Assertions" section and fold failures into run-all's Failed grouping.

**Tech stack:** OCaml, dune, OUnit2/qcheck, effects-based handlers with a fake
runtime. Warnings-as-errors (`-w @A-…`) — keep it clean. jj + GPG-in-sandbox:
retry describe/new with sandbox off; trailer `Co-Authored-By: Claude Opus 4.8
<noreply@anthropic.com>`.

---

## Task 1: AST — the `assertion` type and request field

**Files:** `lib/ast.ml`, `lib/ast.mli`; tests updated as needed.

- [ ] Add to `lib/ast.ml` and `.mli` (before `type request`):

```ocaml
type header_op = Op_equals | Op_contains

type body_op = Op_exists | Op_eq | Op_neq | Op_body_contains

type assertion =
  | Expect_status of int
  | Expect_header of { header_name : string; header_op : header_op; header_value : string }
  | Expect_body of { body_path : string; body_op : body_op; body_value : string option }
```

- [ ] Add field to `type request`: `assertions : assertion list;`
- [ ] `make_request` gains `?(assertions = [])` and sets the field.
- [ ] Build → every `request` record literal in tests now needs `assertions = []`
  (or `[]` via the pun). Add it where the compiler complains.
- [ ] `dune build` clean; commit `feat(ast): add assertion type and request field`.

Note: use record-field prefixes (`header_name`, `body_path`, …) not `name`/`path`
to avoid clashing with existing `request.name` field labels under OCaml's
last-definition-wins label resolution.

---

## Task 2: Parser — collect and validate `# @expect`

**Files:** `lib/parser.ml`, `lib/parser.mli` (no sig change needed); `test/test_freight.ml`.

- [ ] Failing tests: parse a request with each assertion form; assert the parsed
  `assertions` list. Plus a malformed form (`# @expect bogus`) → parse error.

```ocaml
let test_parse_expect_status _ =
  let file = parse_ok "# @expect status 201\nGET https://x/\n" in
  match file.requests with
  | [ r ] -> assert_equal [ Freight.Ast.Expect_status 201 ] r.Freight.Ast.assertions
  | _ -> assert_failure "one request"

let test_parse_expect_header _ =
  let file = parse_ok "# @expect header Content-Type contains json\nGET https://x/\n" in
  match file.requests with
  | [ r ] ->
    assert_equal
      [ Freight.Ast.Expect_header
          { header_name = "Content-Type"; header_op = Freight.Ast.Op_contains; header_value = "json" } ]
      r.Freight.Ast.assertions
  | _ -> assert_failure "one request"

let test_parse_expect_body_exists _ =
  let file = parse_ok "# @expect body data.id exists\nGET https://x/\n" in
  match file.requests with
  | [ r ] ->
    assert_equal
      [ Freight.Ast.Expect_body { body_path = "data.id"; body_op = Freight.Ast.Op_exists; body_value = None } ]
      r.Freight.Ast.assertions
  | _ -> assert_failure "one request"

let test_parse_expect_body_eq _ =
  let file = parse_ok "# @expect body data.status == active\nGET https://x/\n" in
  match file.requests with
  | [ r ] ->
    assert_equal
      [ Freight.Ast.Expect_body { body_path = "data.status"; body_op = Freight.Ast.Op_eq; body_value = Some "active" } ]
      r.Freight.Ast.assertions
  | _ -> assert_failure "one request"

let test_parse_expect_malformed _ =
  let e = parse_error "# @expect bogus thing\nGET https://x/\n" in
  assert_equal 1 e.Freight.Ast.line
```

- [ ] Implement in `parser.ml`:
  - Add `parse_expect : string -> (assertion, string) result option` — returns
    `None` if the line is not `# @expect …`, `Some (Ok a)` if valid, `Some (Error msg)`
    if it is an `@expect` line but malformed.
  - Grammar (tokenize the remainder after `# @expect` on whitespace):
    - `status <int>` → `Expect_status` (int_of_string_opt; else error)
    - `header <name> equals <value...>` / `header <name> contains <value...>`
      → value is the rest joined with spaces
    - `body <path> exists` → `Expect_body { …; Op_exists; None }`
    - `body <path> == <value...>` → `Op_eq`, `Some value`
    - `body <path> != <value...>` → `Op_neq`, `Some value`
    - `body <path> contains <value...>` → `Op_body_contains`, `Some value`
    - anything else → `Error "malformed @expect: <line>"`
  - In `skip_leading_metadata`, thread an `assertions` accumulator (like `name`).
    Before the generic `#`-comment skip branch, try `parse_expect line`:
    `Some (Ok a)` → recurse with `a :: assertions`; `Some (Error msg)` →
    `make_error ~line:line_number ~snippet:line msg`; `None` → fall through.
  - Build the request with `assertions = List.rev assertions`.
- [ ] Tests pass; `dune build` clean; commit `feat(parser): parse # @expect assertions`.

---

## Task 3: Evaluator — `lib/assertion.ml`

**Files:** create `lib/assertion.ml` + `.mli`; `test/test_freight.ml`.

- [ ] mli:

```ocaml
type failure = { assertion : Ast.assertion; detail : string }

val check : Ast.response -> Ast.assertion list -> failure list
(** Returns one failure per unmet assertion, in order; [] when all pass. *)

val describe : Ast.assertion -> string
(** Human-readable one-liner, e.g. "status 201" / "body data.id exists". *)
```

- [ ] Failing tests: status pass/fail; header equals/contains; body exists / == /
  != / contains, including a nested path; `describe` output.
- [ ] Implement:
  - `Expect_status n` → pass iff `response.status = n`; detail
    `Printf.sprintf "expected status %d, got %d" n response.status`.
  - `Expect_header` → case-insensitive header lookup (reuse the pattern from
    `Response`/`Response_store`). `Op_equals` exact; `Op_contains` substring.
    Missing header fails with `"header <name> not present"`.
  - `Expect_body` → `Json_path.lookup (Yojson.Safe.from_string body) (Json_path.parse path)`
    (guard `Yojson.Json_error` → treat as absent). `Op_exists` passes iff `Some _`.
    `Op_eq`/`Op_neq` compare the rendered string to `value`. `Op_body_contains`
    substring. Absent path fails except it satisfies `Op_neq` (absent ≠ value).
  - Provide a small `contains` substring helper (or reuse one).
- [ ] Tests pass; commit `feat(assertion): evaluate assertions against a response`.

---

## Task 4: Handler integration — run and run-all

**Files:** `bin/handlers.ml`; `test/test_handlers.ml`.

- [ ] Failing handler tests (fake runtime):
  - `freight_run` on a response that fails an assertion → the response scratch
    contains an "Assertions" section with a `✗` line.
  - `freight_run_all` where a request has a failing assertion → that entry is a
    `Run_all_failure` (lands in the "Failed" section), message mentions the
    assertion. All-passing with assertions → "Successful".
- [ ] `freight_run`: after `record_response` + render, if
  `request.assertions <> []`, compute `Assertion.check response request.assertions`
  and append lines to the rendered response:
  - header `"Assertions"`, then per assertion `"✓ " ^ describe` or
    `"✗ " ^ describe ^ " — " ^ detail`.
  - Update the scratch with the combined lines. (Still shows the response; the
    assertions annotate it.)
- [ ] `freight_run_all`: after parsing a successful response for an entry, if the
  request has assertions and `check` is non-empty, classify as `Run_all_failure`
  with `message = "assertion failed: " ^ describe (first failure)` instead of
  success. Keep existing status≥400 handling.
- [ ] Tests pass; `dune build` clean; commit
  `feat(run): evaluate assertions and fold failures into run-all`.

---

## Task 5: Docs + help

**Files:** `README.md`, `bin/handlers.ml` (freight_help text).

- [ ] README: new "Assertions" subsection under the HTTP file format with the
  `# @expect` grammar and an example.
- [ ] Add a line to `freight_help` mentioning `# @expect`.
- [ ] `dune runtest` fully green; commit `docs(assertions): document # @expect`.

---

## Self-review checklist

- Field-label clashes: `assertion` record fields are prefixed (`header_name`,
  `body_path`) so they don't collide with `request.name` / other labels.
- Every `request` literal in tests has `assertions = []`.
- Parser: malformed `@expect` is a parse error (line number), valid ones parse;
  a plain `#` comment is still skipped.
- `Assertion.check` reuses `Json_path` and case-insensitive header lookup; guards
  malformed JSON.
- Run-all: assertion failure → Failed grouping; existing status/parse handling
  intact.
