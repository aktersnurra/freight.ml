# Resolver Refactor + Deep Response Chaining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a pluggable `Resolver` for `{{...}}` substitution and use it to
resolve nested / array paths from prior responses lazily (deep response chaining),
without changing any existing behaviour for plain `{{VAR}}`.

**Architecture:** A `Resolver.t` is an ordered list of `source` functions (each
`string -> string option`); the first source that resolves a reference wins,
otherwise the reference is left literal. `Env.substitute` becomes a thin wrapper
over a single-env resolver. Response chaining moves out of the flat env into a
`Response_store.t` on `State`, exposed to the resolver as a source that walks a
JSONPath subset (`data.items[0].id`, `.n` and `[n]`) lazily against the stored
response JSON.

**Tech Stack:** OCaml, dune, `re` (regex), `yojson` (JSON), OUnit2 + qcheck-core
(tests), effects-based runtime with a fake handler in `test_runtime_fake.ml`.

**Warnings-as-errors:** every library builds with `-w @A-4-33-40-41-42-43-34-44`,
so all code must be warning-clean (no unused vars/opens, exhaustive matches).

**How to build/test throughout:**

- Build: `dune build` (warns about duplicate `-lunwind` libs — ignore those lines).
- Run a suite: `dune exec test/test_freight.exe`, `dune exec test/test_handlers.exe`,
  `dune exec test/test_qcheck.exe`.
- All tests: `dune runtest`.

**jj (version control):** this repo uses jujutsu, not git. There is **no staging**.
`jj describe -m "..."` names the current change; `jj new` starts the next one.
GPG signing requires the real filesystem — if a `jj describe`/`jj new` fails with a
GPG/`No secret key` error, that is a sandbox restriction, retry with the sandbox
disabled. End every commit message with:
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

## File Structure

- **Create `lib/resolver.ml` / `lib/resolver.mli`** — the source-chain resolver.
  One responsibility: turn `{{ref}}` into values via an ordered source list.
- **Create `lib/json_path.ml` / `lib/json_path.mli`** — parse a path string
  (`data.items[0].id`) into steps and walk a `Yojson.Safe.t`. Pure, shared by
  chaining now and assertions later.
- **Create `lib/response_store.ml` / `lib/response_store.mli`** — `name -> response`
  map exposed as a resolver `source` for `name.response.body(.path)?` /
  `name.response.headers.<h>`.
- **Modify `lib/env.ml` / `lib/env.mli`** — `substitute`/`unresolved` reimplemented
  over `Resolver` (behaviour identical); keep the public signatures.
- **Modify `lib/resolve.ml` / `lib/resolve.mli`** — `substitute_request` /
  `unresolved_request` take a `Resolver.t` instead of `Env.t`; add resolver-typed
  variants, keep env-typed wrappers used by tests where convenient.
- **Modify `bin/state.ml` / `bin/state.mli`** — add `mutable responses : Response_store.t`.
- **Modify `bin/handlers.ml`** — build a `Resolver.t` per run from the response
  store + env; `record_response` records into the store instead of injecting into
  the flat env.
- **Modify `lib/chaining.ml` / `lib/chaining.mli`** — becomes just the response
  store's building blocks (or is deleted once `Response_store` subsumes it). This
  plan folds chaining into `Response_store` and removes `Chaining.inject`.

---

## Task 1: JSON path parser and walker

**Files:**

- Create: `lib/json_path.ml`, `lib/json_path.mli`
- Modify: `lib/dune` (no change needed — `freight` library globs modules; verify)
- Test: `test/test_freight.ml` (append cases + register in suite)

- [ ] **Step 1: Write the failing tests**

Append to `test/test_freight.ml` just before the `let suite =` definition:

```ocaml
let test_json_path_parse_dotted _ =
  assert_equal [ Freight.Json_path.Field "data"; Field "id" ]
    (Freight.Json_path.parse "data.id")

let test_json_path_parse_index_bracket _ =
  assert_equal
    [ Freight.Json_path.Field "items"; Index 0; Field "id" ]
    (Freight.Json_path.parse "items[0].id")

let test_json_path_parse_index_dotted _ =
  assert_equal
    [ Freight.Json_path.Field "items"; Index 2; Field "id" ]
    (Freight.Json_path.parse "items.2.id")

let test_json_path_lookup_nested _ =
  let json = Yojson.Safe.from_string {|{"data":{"id":"abc"}}|} in
  assert_equal (Some "abc")
    (Freight.Json_path.lookup json (Freight.Json_path.parse "data.id"))

let test_json_path_lookup_array _ =
  let json = Yojson.Safe.from_string {|{"items":[{"id":7},{"id":8}]}|} in
  assert_equal (Some "8")
    (Freight.Json_path.lookup json (Freight.Json_path.parse "items[1].id"))

let test_json_path_lookup_missing _ =
  let json = Yojson.Safe.from_string {|{"data":{"id":"abc"}}|} in
  assert_equal None
    (Freight.Json_path.lookup json (Freight.Json_path.parse "data.missing"))

let test_json_path_lookup_non_scalar_leaf _ =
  let json = Yojson.Safe.from_string {|{"data":{"id":"abc"}}|} in
  assert_equal None
    (Freight.Json_path.lookup json (Freight.Json_path.parse "data"))
```

Register them inside the `suite` test list (add these lines among the others):

```ocaml
         "json_path_parse_dotted" >:: test_json_path_parse_dotted;
         "json_path_parse_index_bracket" >:: test_json_path_parse_index_bracket;
         "json_path_parse_index_dotted" >:: test_json_path_parse_index_dotted;
         "json_path_lookup_nested" >:: test_json_path_lookup_nested;
         "json_path_lookup_array" >:: test_json_path_lookup_array;
         "json_path_lookup_missing" >:: test_json_path_lookup_missing;
         "json_path_lookup_non_scalar_leaf" >:: test_json_path_lookup_non_scalar_leaf;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune build 2>&1 | grep -v "duplicate libraries"`
Expected: FAIL — `Unbound module Freight.Json_path`.

- [ ] **Step 3: Write the mli**

Create `lib/json_path.mli`:

```ocaml
type step =
  | Field of string
  | Index of int

val parse : string -> step list
(** Parse a dotted/bracketed path. [.field], [[n]] and [.n] are all accepted:
    ["data.items[0].id"] and ["data.items.0.id"] both parse to the same steps. *)

val lookup : Yojson.Safe.t -> step list -> string option
(** Walk [json] along the steps. Returns the scalar leaf rendered as a string
    (string/int/float/bool/null), or [None] if the path is missing or the leaf
    is a non-scalar (object/array). *)
```

- [ ] **Step 4: Write the implementation**

Create `lib/json_path.ml`:

```ocaml
type step =
  | Field of string
  | Index of int

(* Split "data.items[0].id" -> ["data";"items";"[0]";"id"] then classify.
   We first replace "[n]" with ".[n]" so a single split on '.' separates
   bracket segments too, then drop empties. *)
let parse path =
  let buf = Buffer.create (String.length path + 8) in
  String.iter
    (fun c ->
      if c = '[' then Buffer.add_string buf ".["
      else Buffer.add_char buf c)
    path;
  Buffer.contents buf
  |> String.split_on_char '.'
  |> List.filter (fun s -> s <> "")
  |> List.map (fun segment ->
         let n = String.length segment in
         if n >= 2 && segment.[0] = '[' && segment.[n - 1] = ']' then
           Index (int_of_string (String.sub segment 1 (n - 2)))
         else
           match int_of_string_opt segment with
           | Some i -> Index i
           | None -> Field segment)

let scalar_to_string = function
  | `String s -> Some s
  | `Int i -> Some (string_of_int i)
  | `Intlit s -> Some s
  | `Float f -> Some (string_of_float f)
  | `Bool b -> Some (string_of_bool b)
  | `Null -> Some "null"
  | `Assoc _ | `List _ | `Tuple _ | `Variant _ -> None

let rec walk json = function
  | [] -> scalar_to_string json
  | Field key :: rest -> (
      match json with
      | `Assoc fields -> (
          match List.assoc_opt key fields with
          | Some json -> walk json rest
          | None -> None)
      | _ -> None)
  | Index i :: rest -> (
      match json with
      | `List items -> (
          match List.nth_opt items i with
          | Some json -> walk json rest
          | None -> None)
      | _ -> None)

let lookup json steps = walk json steps
```

Note: `parse` treats a bare integer segment as `Index`, matching the mli. A
JSON object with an all-digit key is not addressable this way — acceptable for v1
(document if needed).

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune exec test/test_freight.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(json): add JSONPath subset parser and walker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
jj new
```

---

## Task 2: The Resolver source chain

**Files:**

- Create: `lib/resolver.ml`, `lib/resolver.mli`
- Test: `test/test_freight.ml`

- [ ] **Step 1: Write the failing tests**

Append to `test/test_freight.ml` before `let suite =`:

```ocaml
let test_resolver_first_source_wins _ =
  let a = fun ref -> if ref = "x" then Some "A" else None in
  let b = fun ref -> if ref = "x" then Some "B" else None in
  let r = Freight.Resolver.make [ a; b ] in
  assert_equal "A" (Freight.Resolver.resolve r "{{x}}")

let test_resolver_falls_through _ =
  let a = fun ref -> if ref = "x" then Some "A" else None in
  let b = fun ref -> if ref = "y" then Some "B" else None in
  let r = Freight.Resolver.make [ a; b ] in
  assert_equal "A-B" (Freight.Resolver.resolve r "{{x}}-{{y}}")

let test_resolver_unknown_left_literal _ =
  let r = Freight.Resolver.make [ (fun _ -> None) ] in
  assert_equal "{{ missing }}" (Freight.Resolver.resolve r "{{ missing }}")

let test_resolver_trims_ref _ =
  let seen = ref "" in
  let r = Freight.Resolver.make [ (fun ref -> seen := ref; Some "v") ] in
  ignore (Freight.Resolver.resolve r "{{  spaced  }}");
  assert_equal "spaced" !seen

let test_resolver_unresolved _ =
  let a = fun ref -> if ref = "x" then Some "A" else None in
  let r = Freight.Resolver.make [ a ] in
  assert_equal [ "y"; "z" ]
    (Freight.Resolver.unresolved r "{{x}} {{z}} {{y}} {{z}}")
```

Register in the suite list:

```ocaml
         "resolver_first_source_wins" >:: test_resolver_first_source_wins;
         "resolver_falls_through" >:: test_resolver_falls_through;
         "resolver_unknown_left_literal" >:: test_resolver_unknown_left_literal;
         "resolver_trims_ref" >:: test_resolver_trims_ref;
         "resolver_unresolved" >:: test_resolver_unresolved;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune build 2>&1 | grep -v "duplicate libraries"`
Expected: FAIL — `Unbound module Freight.Resolver`.

- [ ] **Step 3: Write the mli**

Create `lib/resolver.mli`:

```ocaml
type source = string -> string option
(** Given the trimmed reference text inside [{{...}}], return a value or [None]
    to defer to the next source. *)

type t

val make : source list -> t
(** Build a resolver from an ordered source list; earlier sources win. *)

val resolve : t -> string -> string
(** Replace every [{{ref}}] using the source chain. Unresolved refs are left
    literal. Single pass: substituted values are not re-scanned. *)

val unresolved : t -> string -> string list
(** Sorted, deduped [{{ref}}]s that no source resolved. *)
```

- [ ] **Step 4: Write the implementation**

Create `lib/resolver.ml`:

```ocaml
type source = string -> string option
type t = source list

let make sources = sources

(* Capture anything between braces; each source decides if it recognizes it. *)
let variable = Re.Perl.compile_pat "\\{\\{[ \\t]*([^}]*?)[ \\t]*\\}\\}"

let first_some sources ref =
  List.fold_left
    (fun acc source -> match acc with Some _ -> acc | None -> source ref)
    None sources

let resolve sources source_text =
  Re.replace variable source_text ~f:(fun group ->
      let ref = Re.Group.get group 1 in
      match first_some sources ref with
      | Some value -> value
      | None -> Re.Group.get group 0)

let unresolved sources source_text =
  let seen = Hashtbl.create 8 in
  Re.all variable source_text
  |> List.filter_map (fun group ->
         let ref = Re.Group.get group 1 in
         match first_some sources ref with
         | Some _ -> None
         | None ->
             if Hashtbl.mem seen ref then None
             else begin
               Hashtbl.add seen ref ();
               Some ref
             end)
  |> List.sort_uniq String.compare
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune exec test/test_freight.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(resolver): add ordered source-chain substitution engine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
jj new
```

---

## Task 3: Reimplement Env.substitute over Resolver (behaviour-preserving)

**Files:**

- Modify: `lib/env.ml`
- Modify: `lib/env.mli` (add `source`)
- Test: existing env tests must stay green; add one bridging test.

- [ ] **Step 1: Write the failing test**

Append to `test/test_freight.ml` before `let suite =`:

```ocaml
let test_env_source_resolves_key _ =
  let env = Freight.Env.of_list [ ("host", "example.com") ] in
  let src = Freight.Env.source env in
  assert_equal (Some "example.com") (src "host");
  assert_equal None (src "missing")
```

Register:

```ocaml
         "env_source_resolves_key" >:: test_env_source_resolves_key;
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune build 2>&1 | grep -v "duplicate libraries"`
Expected: FAIL — `Unbound value Freight.Env.source`.

- [ ] **Step 3: Add `source` and reimplement substitute/unresolved**

In `lib/env.ml`, replace the current `substitute` and `unresolved` definitions
(the ones using the local `variable` regex) with:

```ocaml
let source env key = find env key

let substitute env s = Resolver.resolve (Resolver.make [ source env ]) s

let unresolved env s = Resolver.unresolved (Resolver.make [ source env ]) s
```

Delete the now-unused `variable` binding in `env.ml` (it moved to `resolver.ml`)
to keep the build warning-clean.

In `lib/env.mli`, add after `val add`:

```ocaml
val source : t -> Resolver.source
(** Expose the env as a resolver source: resolves a key to its value. *)
```

(Keep the existing `substitute`/`unresolved`/`to_list` signatures unchanged.)

- [ ] **Step 4: Run all lib-facing tests**

Run: `dune exec test/test_freight.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Run: `dune exec test/test_qcheck.exe 2>&1 | grep -iE "success|fail"`
Expected: `OK` and `success` — existing `env_substitute_*`, `env_unresolved`,
and qcheck substitution properties pass unchanged.

- [ ] **Step 5: Commit**

```bash
jj describe -m "refactor(env): reimplement substitute/unresolved over Resolver

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
jj new
```

---

## Task 4: Response store as a resolver source (deep chaining core)

**Files:**

- Create: `lib/response_store.ml`, `lib/response_store.mli`
- Test: `test/test_freight.ml`

- [ ] **Step 1: Write the failing tests**

Append to `test/test_freight.ml` before `let suite =`:

```ocaml
let store_response ~body ~headers =
  { Freight.Ast.status = 200
  ; status_text = "OK"
  ; headers
  ; body
  ; duration_ms = 1
  ; request =
      { Freight.Ast.name = None
      ; method_ = Freight.Ast.Get
      ; url = "https://example.com"
      ; headers = []
      ; body = Freight.Ast.Body_none
      ; save_to = None
      }
  }

let test_response_store_top_level_body _ =
  let resp = store_response ~body:{|{"token":"abc"}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "abc") (src "login.response.body.token")

let test_response_store_nested_body _ =
  let resp = store_response ~body:{|{"data":{"id":"xyz"}}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "xyz") (src "login.response.body.data.id")

let test_response_store_array_body _ =
  let resp = store_response ~body:{|{"items":[{"id":1},{"id":2}]}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"list" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "2") (src "list.response.body.items[1].id")

let test_response_store_header _ =
  let resp = store_response ~body:"" ~headers:[ ("X-Request-Id", "req-1") ] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "req-1") (src "login.response.headers.X-Request-Id")

let test_response_store_missing_path _ =
  let resp = store_response ~body:{|{"token":"abc"}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal None (src "login.response.body.nope")

let test_response_store_unknown_name _ =
  let src = Freight.Response_store.source Freight.Response_store.empty in
  assert_equal None (src "login.response.body.token")

let test_response_store_malformed_json _ =
  let resp = store_response ~body:"not json" ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal None (src "login.response.body.token")
```

Register:

```ocaml
         "response_store_top_level_body" >:: test_response_store_top_level_body;
         "response_store_nested_body" >:: test_response_store_nested_body;
         "response_store_array_body" >:: test_response_store_array_body;
         "response_store_header" >:: test_response_store_header;
         "response_store_missing_path" >:: test_response_store_missing_path;
         "response_store_unknown_name" >:: test_response_store_unknown_name;
         "response_store_malformed_json" >:: test_response_store_malformed_json;
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune build 2>&1 | grep -v "duplicate libraries"`
Expected: FAIL — `Unbound module Freight.Response_store`.

- [ ] **Step 3: Write the mli**

Create `lib/response_store.mli`:

```ocaml
type t

val empty : t

val record : name:string -> Ast.response -> t -> t
(** Store [response] under [name]. An empty [name] is ignored (unnamed
    requests cannot be chained). Re-recording a name overwrites it. *)

val source : t -> Resolver.source
(** Resolve [<name>.response.body(.<path>)?] and
    [<name>.response.headers.<header>] references. Body paths use the
    {!Json_path} subset; header lookup is case-insensitive. Returns [None] for
    unknown names, missing paths, non-scalar leaves, or malformed JSON. *)
```

- [ ] **Step 4: Write the implementation**

Create `lib/response_store.ml`:

```ocaml
module String_map = Map.Make (String)

type t = Ast.response String_map.t

let empty = String_map.empty

let record ~name response store =
  if name = "" then store else String_map.add name response store

let lower = String.lowercase_ascii

(* A reference like "login.response.body.data.id" splits into
   name="login", kind="body", rest="data.id". *)
let split_reference ref =
  match String.split_on_char '.' ref with
  | name :: "response" :: kind :: rest -> Some (name, kind, String.concat "." rest)
  | _ -> None

let body_value response path =
  match Yojson.Safe.from_string response.Ast.body with
  | json -> Json_path.lookup json (Json_path.parse path)
  | exception Yojson.Json_error _ -> None

let header_value response header =
  let header = lower header in
  List.find_map
    (fun (name, data) -> if lower name = header then Some data else None)
    response.Ast.headers

let source store ref =
  match split_reference ref with
  | Some (name, "body", path) -> (
      match String_map.find_opt name store with
      | Some response -> body_value response path
      | None -> None)
  | Some (name, "headers", header) -> (
      match String_map.find_opt name store with
      | Some response -> header_value response header
      | None -> None)
  | _ -> None
```

Note on `split_reference`: for a header named with dots this rejoins `rest`
with `.`; `body` paths also rejoin then re-split in `Json_path.parse`, which is
correct because the path grammar re-parses dots and brackets.

- [ ] **Step 5: Run to verify pass**

Run: `dune exec test/test_freight.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(chaining): add Response_store with lazy JSONPath resolution

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
jj new
```

---

## Task 5: Resolver-typed request substitution in Resolve

**Files:**

- Modify: `lib/resolve.ml`
- Modify: `lib/resolve.mli`
- Test: `test/test_freight.ml`

- [ ] **Step 1: Write the failing test**

Append to `test/test_freight.ml` before `let suite =`:

```ocaml
let test_substitute_request_with_resolver _ =
  let store = Freight.Response_store.record ~name:"login"
      (store_response ~body:{|{"data":{"id":"xyz"}}|} ~headers:[])
      Freight.Response_store.empty in
  let env = Freight.Env.of_list [ ("host", "example.com") ] in
  let resolver =
    Freight.Resolver.make
      [ Freight.Response_store.source store; Freight.Env.source env ]
  in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Post
    ; url = "https://{{host}}/items/{{login.response.body.data.id}}"
    ; headers = []
    ; body = Freight.Ast.Body_none
    ; save_to = None
    }
  in
  let resolved = Freight.Resolve.substitute_request_r resolver request in
  assert_equal "https://example.com/items/xyz" resolved.Freight.Ast.url

let test_unresolved_request_with_resolver _ =
  let resolver = Freight.Resolver.make [] in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://x/{{a}}"
    ; headers = [ ("H", "{{b}}") ]
    ; body = Freight.Ast.Body_none
    ; save_to = None
    }
  in
  assert_equal [ "a"; "b" ]
    (Freight.Resolve.unresolved_request_r resolver request)
```

Register:

```ocaml
         "substitute_request_with_resolver" >:: test_substitute_request_with_resolver;
         "unresolved_request_with_resolver" >:: test_unresolved_request_with_resolver;
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune build 2>&1 | grep -v "duplicate libraries"`
Expected: FAIL — `Unbound value Freight.Resolve.substitute_request_r`.

- [ ] **Step 3: Add resolver-typed variants**

In `lib/resolve.ml`, refactor so the core work is resolver-based and the env
versions delegate. Replace the body of `substitute_request` / `unresolved_request`
with resolver-typed cores plus env wrappers. The full new content of the
substitution section of `lib/resolve.ml`:

```ocaml
let substitute_request_r resolver (request : Ast.request) =
  let sub = Resolver.resolve resolver in
  let sub_part (part : Ast.multipart_part) =
    let content =
      match part.content with
      | Ast.Part_text value -> Ast.Part_text (sub value)
      | Ast.Part_file path -> Ast.Part_file (sub path)
    in
    { part with
      Ast.filename = Option.map sub part.filename
    ; content_type = Option.map sub part.content_type
    ; content
    }
  in
  let body =
    match request.body with
    | Ast.Body_inline s -> Ast.Body_inline (sub s)
    | Ast.Body_file path -> Ast.Body_file (sub path)
    | Ast.Body_multipart parts -> Ast.Body_multipart (List.map sub_part parts)
    | Ast.Body_none as other -> other
  in
  let save_to =
    Option.map
      (fun (save : Ast.save) ->
        { save with Ast.save_path = Option.map sub save.save_path })
      request.save_to
  in
  { request with
    url = sub request.url
  ; headers = List.map (fun (k, v) -> (k, sub v)) request.headers
  ; body
  ; save_to
  }

let substitute_request env request =
  substitute_request_r (Resolver.make [ Env.source env ]) request

let part_strings (part : Ast.multipart_part) =
  let content =
    match part.content with
    | Ast.Part_text value -> value
    | Ast.Part_file path -> path
  in
  content :: Option.to_list part.filename @ Option.to_list part.content_type

let request_strings (request : Ast.request) =
  let body =
    match request.body with
    | Ast.Body_inline s -> [ s ]
    | Ast.Body_file path -> [ path ]
    | Ast.Body_multipart parts -> List.concat_map part_strings parts
    | Ast.Body_none -> []
  in
  (request.url :: List.map snd request.headers) @ body

let unresolved_request_r resolver request =
  request_strings request
  |> List.concat_map (Resolver.unresolved resolver)
  |> List.sort_uniq String.compare

let unresolved_request env request =
  unresolved_request_r (Resolver.make [ Env.source env ]) request
```

In `lib/resolve.mli`, add after the existing `substitute_request` /
`unresolved_request` signatures:

```ocaml
val substitute_request_r : Resolver.t -> Ast.request -> Ast.request
(** Like {!substitute_request} but driven by an arbitrary resolver (env +
    response store + dynamic sources). *)

val unresolved_request_r : Resolver.t -> Ast.request -> string list
(** Like {!unresolved_request} but driven by an arbitrary resolver. *)
```

- [ ] **Step 4: Run to verify pass**

Run: `dune exec test/test_freight.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Expected: `OK` — including the pre-existing `substitute_request_*` tests, which
still exercise the env wrappers.

- [ ] **Step 5: Commit**

```bash
jj describe -m "feat(resolve): resolver-typed request substitution

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
jj new
```

---

## Task 6: Wire the response store into State and handlers

**Files:**

- Modify: `bin/state.ml`, `bin/state.mli`
- Modify: `bin/handlers.ml`
- Test: `test/test_handlers.ml`

- [ ] **Step 1: Write the failing test**

This proves deep chaining end-to-end through the handler (extends the existing
`chaining_survives_across_runs` idea with a nested field). Append to
`test/test_handlers.ml` after `test_freight_run_chaining_survives_across_runs`:

```ocaml
let test_freight_run_chaining_nested_field _ =
  let preview_output =
    "HTTP/1.1 200 OK\r\n\
     Content-Type: application/json\r\n\
     \r\n\
     {\"data\":{\"id\":\"abc123\"}}\n\
     200\n\
     0.010"
  in
  let state = State.create () in
  let preview_config =
    { Test_runtime_fake.default_config with
      buffer_lines = [ "# @name preview"; "GET https://example.com/preview" ]
    ; buffer_dir = Some "/tmp/does-not-exist"
    ; cursor = { Freight_effect.Cursor.row = 1; col = 0 }
    ; curl_result = Ok preview_output
    ; fork_mode = `Run_immediately
    }
  in
  let (), _ =
    Test_runtime_fake.run preview_config @@ fun () -> Handlers.freight_run state
  in
  let apply_config =
    { Test_runtime_fake.default_config with
      buffer_lines =
        [ "# @name apply"
        ; "POST https://example.com/{{preview.response.body.data.id}}/apply"
        ]
    ; buffer_dir = Some "/tmp/does-not-exist"
    ; cursor = { Freight_effect.Cursor.row = 1; col = 0 }
    ; curl_result = Ok preview_output
    ; fork_mode = `Run_immediately
    }
  in
  let (), calls =
    Test_runtime_fake.run apply_config @@ fun () -> Handlers.freight_run state
  in
  assert_bool "curl url has the nested id"
    (has_call
       (function
        | Test_runtime_fake.Run_curl invocation ->
          List.mem "https://example.com/abc123/apply" invocation.Freight.Executor.args
        | _ -> false)
       calls)
```

Register in the suite list:

```ocaml
    ; "freight_run chaining nested field" >:: test_freight_run_chaining_nested_field
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune build 2>&1 | grep -v "duplicate libraries" && dune exec test/test_handlers.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Expected: FAIL — the nested `{{preview.response.body.data.id}}` is not resolved
by the current flat-env chaining (top-level only), so curl gets literal braces
and the asserted URL is absent.

- [ ] **Step 3: Add `responses` to State**

In `bin/state.ml`, add the field to the record and initializer.

In the `type t = { ... }` record, add:

```ocaml
  mutable responses : Freight.Response_store.t;
```

In `let create () = { ... }`, add:

```ocaml
  responses = Freight.Response_store.empty;
```

In `bin/state.mli`, add to the `type t = { ... }` record the same field:

```ocaml
  mutable responses : Freight.Response_store.t;
```

- [ ] **Step 4: Update handlers to use the store + resolver**

In `bin/handlers.ml`:

(a) Replace `record_response`'s chaining injection. Change:

```ocaml
let record_response state request response verbose_raw response_buf response_buf_name =
  let req_name = Option.value request.Freight.Ast.name ~default:"" in
  state.State.env <-
    Freight.Chaining.inject ~name:req_name response state.State.env;
```

to:

```ocaml
let record_response state request response verbose_raw response_buf response_buf_name =
  let req_name = Option.value request.Freight.Ast.name ~default:"" in
  state.State.responses <-
    Freight.Response_store.record ~name:req_name response state.State.responses;
```

(b) Add a resolver builder near `resolve_env`. After the `resolve_env` function,
add:

```ocaml
(* The active resolver: response-chaining vars (deep, lazy) take precedence over
   .env / accumulated env values. *)
let build_resolver state buf =
  let env = resolve_env state buf in
  Freight.Resolver.make
    [ Freight.Response_store.source state.State.responses
    ; Freight.Env.source env
    ]
```

(c) Change `resolve_request` to use the resolver. Replace:

```ocaml
let resolve_request state source cursor_line buf =
  let env = resolve_env state buf in
  Freight.Resolve.at_cursor ~source ~cursor_line ~env
```

with a resolver-based cursor resolution. First add a resolver variant of
`at_cursor` in `lib/resolve.ml` / `.mli` (Step 4a below), then:

```ocaml
let resolve_request state source cursor_line buf =
  let resolver = build_resolver state buf in
  Freight.Resolve.at_cursor_r ~source ~cursor_line ~resolver
```

- [ ] **Step 4a: Add `at_cursor_r` to Resolve**

In `lib/resolve.ml`, replace the existing `at_cursor` with a resolver core +
env wrapper:

```ocaml
let at_cursor_r ~source ~cursor_line ~resolver =
  match Parser.request_at_cursor source cursor_line with
  | None ->
    (match Parser.parse_string source with
     | Error err -> Error (`Parse err)
     | Ok _ -> Error `No_request)
  | Some request ->
    Ok (Ast.apply_host_header (substitute_request_r resolver request))

let at_cursor ~source ~cursor_line ~env =
  at_cursor_r ~source ~cursor_line ~resolver:(Resolver.make [ Env.source env ])
```

In `lib/resolve.mli`, add:

```ocaml
val at_cursor_r :
  source:string ->
  cursor_line:int ->
  resolver:Resolver.t ->
  (Ast.request, error) result
```

- [ ] **Step 4b: Update run-all's in-loop substitution to use the resolver**

Leave `freight_run`'s unresolved guard untouched — it calls
`Freight.Resolve.unresolved_request Freight.Env.empty request` on the
already-substituted request to detect leftover literals, which is still correct.

Leave the `let base_env = resolve_env state buf in` line in `freight_run_all`
untouched.

In `freight_run_all`'s per-request loop, replace this block:

```ocaml
          (* Resolve against the current env, which accrues the response
             variables injected by earlier requests in this run. *)
          let env =
            Freight.Env.overlay ~base:base_env ~over:state.State.env
          in
          let request =
            raw_request
            |> Freight.Resolve.substitute_request env
            |> Freight.Ast.apply_host_header
          in
```

with:

```ocaml
          (* Resolve against the response store (which accrues earlier responses
             this run) layered over the loaded env. *)
          let resolver =
            Freight.Resolver.make
              [ Freight.Response_store.source state.State.responses
              ; Freight.Env.source base_env
              ]
          in
          let request =
            raw_request
            |> Freight.Resolve.substitute_request_r resolver
            |> Freight.Ast.apply_host_header
          in
```

Chaining now lives in `state.responses` (updated by `record_response` as each
request in the loop completes), so the old `Env.overlay ~over:state.State.env`
is no longer needed for chaining. `base_env` still comes from `resolve_env`,
which overlays `state.env` for any non-chaining user-set vars.

- [ ] **Step 5: Run to verify pass**

Run: `dune exec test/test_handlers.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Expected: `OK` — including the new nested-field test and the existing
`chaining_survives_across_runs` (top-level still works via the same store).

- [ ] **Step 6: Commit**

```bash
jj describe -m "feat(chaining): resolve deep response paths through the response store

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
jj new
```

---

## Task 7: Remove dead chaining code and update docs

**Files:**

- Delete: `lib/chaining.ml`, `lib/chaining.mli` (if nothing else references them)
- Modify: `test/test_freight.ml` (remove `env_substitute_chaining_keys` if it
  asserted the old flat-injection behaviour, or keep it — it tests `Env.substitute`
  with pre-seeded keys, which still works; verify before deleting)
- Modify: `README.md` (Response chaining section)

- [ ] **Step 1: Check for remaining references**

Run: `grep -rn "Chaining\." lib bin test`
Expected: no matches (Task 6 removed the only caller). If any remain, they must
be migrated to `Response_store` before deletion.

- [ ] **Step 2: Delete the module**

```bash
rm lib/chaining.ml lib/chaining.mli
```

- [ ] **Step 3: Verify the chaining-keys test still holds**

`test_env_substitute_chaining_keys` seeds `Env.of_list [("login.response.body.token","abc"); ...]`
and asserts `Env.substitute` replaces `{{ login.response.body.token }}`. This is
still valid (a flat env key that happens to contain dots). Leave it. Confirm:

Run: `dune exec test/test_freight.exe 2>&1 | grep -iE "Ran|OK|FAIL"`
Expected: `OK`.

- [ ] **Step 4: Update README**

In `README.md`, under `## Response chaining`, replace the paragraph that says
responses are injected under `name.response.body.*` / `name.response.headers.*`
with:

```markdown
## Response chaining

Named request responses are addressable from later requests via
`{{name.response.body.<path>}}` and `{{name.response.headers.<header>}}`. Body
paths support nested objects and arrays:

```http
# @name login
POST {{BASE_URL}}/auth
Content-Type: application/json

{"user": "me"}

###

GET {{BASE_URL}}/orders/{{login.response.body.data.items[0].id}}
Authorization: Bearer {{login.response.body.token}}
```

Paths use dotted keys, `[n]` or `.n` array indices, and resolve lazily against
the stored response. A path that is missing or points at a non-scalar reports as
an unresolved variable (the request fails fast instead of shelling out to curl).
```

- [ ] **Step 5: Full test run + build**

Run: `dune build 2>&1 | grep -v "duplicate libraries"; echo "exit=${PIPESTATUS[0]}"`
Run: `dune runtest 2>&1 | grep -v "duplicate libraries" | grep -iE "fail|error"`
Expected: build clean; no failures printed.

- [ ] **Step 6: Commit**

```bash
jj describe -m "refactor(chaining): remove flat-env injection; document deep paths

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
jj new
```

---

## Self-Review Notes (for the executor)

- **Spec coverage:** This plan covers the cross-cutting **Resolver refactor** and
  **Feature #2 (deep chaining)** from `SPEC_FEAT_dynamic_and_chaining.md`. It does
  **not** cover #1 (dynamic sources), #3 (assertions), or #4 (generated values) —
  those are separate plans that build on the `Resolver`/`Json_path`/`Response_store`
  modules created here. The resolver chain in `build_resolver` is intentionally
  ordered so #4 (generated), #1 (dynamic) can be prepended later without churn.
- **`env` field on State:** `state.State.env` is retained (still overlaid by
  `resolve_env` for user-set vars and `:FreightEnv`); only chaining moved out.
- **Type consistency:** module/function names used across tasks — `Resolver.make`,
  `Resolver.resolve`, `Resolver.unresolved`, `Resolver.source`, `Json_path.parse`,
  `Json_path.lookup`, `Json_path.Field`/`Index`, `Response_store.empty`/`record`/
  `source`, `Resolve.substitute_request_r`/`unresolved_request_r`/`at_cursor_r`,
  `Env.source`, `State.responses` — are consistent throughout.
```
