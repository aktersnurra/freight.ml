# Fix Review Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix suggestions S1-S4 from `.rpiv/artifacts/reviews/2026-05-26_whole-project-review.md` without addressing the critical/important findings in this pass.

**Architecture:** Keep fixes small and local. Improve parser diagnostics by carrying source line numbers through block parsing; reduce invalid public AST construction by adding validated smart constructors while preserving existing records for compatibility; make Lua command wrappers available before the OCaml RPC process registers its commands; update README command documentation to match implementation.

**Tech Stack:** OCaml/dune/OUnit2 for parser/API changes, Lua Neovim plugin APIs for command wrappers, Markdown docs. Use `jj` for VCS operations.

---

## File Structure

- Modify: `lib/ast.mli` — expose validation error ADT and smart constructors for request/response records.
- Modify: `lib/ast.ml` — implement smart constructors and validation helpers.
- Modify: `lib/parser.ml` — preserve original line numbers in `Ast.parse_error.line`.
- Modify: `plugin/freight.lua` — register startup-safe user commands for the public command surface.
- Modify: `README.md` — document `FreightHelp`, `FreightHistory`, `FreightViewHistory`, and `FreightView Verbose`.
- Modify: `test/test_freight.ml` — add OUnit parser/API regression tests.
- Optional modify: `test/dune` — only if local QCheck runner dependency blocks all verification; do not mix that packaging fix with this plan unless execution requires it.

---

### Task 1: Preserve parser error line numbers

**Files:**

- Modify: `lib/parser.ml`
- Test: `test/test_freight.ml`

- [ ] **Step 1: Add failing parser line tests**

Append these tests near `test_parse_request_line_missing_url` in `test/test_freight.ml`:

```ocaml
let test_parse_error_reports_request_line_after_metadata _ =
  let error = parse_error "# comment\n# @name broken\nGET\n" in
  assert_equal "missing request URL" error.message;
  assert_equal 3 error.line;
  assert_equal "GET" error.snippet

let test_parse_error_reports_request_line_in_second_block _ =
  let error = parse_error "GET https://one.test\n\n###\n# comment\nPOST\n" in
  assert_equal "missing request URL" error.message;
  assert_equal 5 error.line;
  assert_equal "POST" error.snippet
```

Add both tests to the suite list at the bottom of `test/test_freight.ml`:

```ocaml
"parse error reports request line after metadata" >:: test_parse_error_reports_request_line_after_metadata;
"parse error reports request line in second block" >:: test_parse_error_reports_request_line_in_second_block;
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```sh
opam exec -- dune exec test/test_freight.exe -- -only-test freight:"parse error reports request line after metadata"
```

Expected: FAIL because `error.line` is `1`, not `3`.

- [ ] **Step 3: Thread line numbers through `parse_block`**

In `lib/parser.ml`, replace `parse_block` with this implementation:

```ocaml
let parse_block ~start_line block =
  let rec skip_leading_metadata line_number name = function
    | [] -> make_error ~line:line_number "missing request line"
    | line :: rest when trim line = "" ->
        skip_leading_metadata (line_number + 1) name rest
    | line :: rest -> (
        match parse_name line with
        | Some parsed_name ->
            skip_leading_metadata (line_number + 1) (Some parsed_name) rest
        | None when starts_with ~prefix:"#" (trim line) ->
            skip_leading_metadata (line_number + 1) name rest
        | None -> (
            match parse_request_line line with
            | Error message -> make_error ~line:line_number ~snippet:line message
            | Ok (method_, url) ->
                let header_lines, body_lines = split_at_blank rest in
                let headers = List.filter_map parse_header header_lines in
                Ok
                  {
                    Ast.name;
                    method_;
                    url;
                    headers;
                    body = parse_body body_lines;
                  }))
  in
  skip_leading_metadata start_line None block
```

Then update both callers in `parse_source` and `parse_source_with_lines`:

```ocaml
match parse_block ~start_line:start block with
```

- [ ] **Step 4: Run parser tests and verify pass**

Run:

```sh
opam exec -- dune exec test/test_freight.exe
```

Expected: all `test_freight` tests pass.

- [ ] **Step 5: Commit**

```sh
jj describe -m "fix(parser): preserve parse error line numbers"
jj new
```

---

### Task 2: Add validated AST constructors without breaking existing callers

**Files:**

- Modify: `lib/ast.mli`
- Modify: `lib/ast.ml`
- Test: `test/test_freight.ml`

- [ ] **Step 1: Add failing validation tests**

Append these tests in `test/test_freight.ml` near the AST method tests:

```ocaml
let test_make_request_rejects_empty_url _ =
  match
    Freight.Ast.make_request
      ?name:None
      ~method_:Freight.Ast.Get
      ~url:""
      ~headers:[]
      ~body:Freight.Ast.Body_none
      ()
  with
  | Error Freight.Ast.Empty_url -> ()
  | Ok _ -> assert_failure "expected Empty_url"
  | Error _ -> assert_failure "expected Empty_url"

let test_make_response_rejects_invalid_status _ =
  let request =
    {
      Freight.Ast.name = None;
      method_ = Freight.Ast.Get;
      url = "https://example.test";
      headers = [];
      body = Freight.Ast.Body_none;
    }
  in
  match
    Freight.Ast.make_response
      ~status:99
      ~status_text:"Invalid"
      ~headers:[]
      ~body:""
      ~duration_ms:0
      ~request
      ()
  with
  | Error Freight.Ast.Invalid_status -> ()
  | Ok _ -> assert_failure "expected Invalid_status"
  | Error _ -> assert_failure "expected Invalid_status"

let test_make_response_rejects_negative_duration _ =
  let request =
    {
      Freight.Ast.name = None;
      method_ = Freight.Ast.Get;
      url = "https://example.test";
      headers = [];
      body = Freight.Ast.Body_none;
    }
  in
  match
    Freight.Ast.make_response
      ~status:200
      ~status_text:"OK"
      ~headers:[]
      ~body:""
      ~duration_ms:(-1)
      ~request
      ()
  with
  | Error Freight.Ast.Negative_duration -> ()
  | Ok _ -> assert_failure "expected Negative_duration"
  | Error _ -> assert_failure "expected Negative_duration"
```

Add them to the suite list:

```ocaml
"make_request rejects empty url" >:: test_make_request_rejects_empty_url;
"make_response rejects invalid status" >:: test_make_response_rejects_invalid_status;
"make_response rejects negative duration" >:: test_make_response_rejects_negative_duration;
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```sh
opam exec -- dune exec test/test_freight.exe -- -only-test freight:"make_request rejects empty url"
```

Expected: compile failure because `Freight.Ast.make_request` and `Freight.Ast.Empty_url` do not exist yet.

- [ ] **Step 3: Extend `lib/ast.mli`**

After `type http_file = ...`, add:

```ocaml
type validation_error =
  | Empty_url
  | Empty_header_name
  | Invalid_status
  | Negative_duration

val make_request :
  ?name:string ->
  method_:method_ ->
  url:string ->
  headers:(string * string) list ->
  body:body ->
  unit ->
  (request, validation_error) result

val make_response :
  status:int ->
  status_text:string ->
  headers:(string * string) list ->
  body:string ->
  duration_ms:int ->
  request:request ->
  unit ->
  (response, validation_error) result
```

- [ ] **Step 4: Implement validation in `lib/ast.ml`**

After `type http_file = ...`, add:

```ocaml
type validation_error =
  | Empty_url
  | Empty_header_name
  | Invalid_status
  | Negative_duration

let has_empty_header_name headers =
  List.exists (fun (name, _) -> String.trim name = "") headers

let make_request ?name ~method_ ~url ~headers ~body () =
  if String.trim url = "" then Error Empty_url
  else if has_empty_header_name headers then Error Empty_header_name
  else Ok { name; method_; url; headers; body }

let make_response ~status ~status_text ~headers ~body ~duration_ms ~request () =
  if status < 100 || status > 599 then Error Invalid_status
  else if duration_ms < 0 then Error Negative_duration
  else if has_empty_header_name headers then Error Empty_header_name
  else Ok { status; status_text; headers; body; duration_ms; request }
```

- [ ] **Step 5: Run AST tests and verify pass**

Run:

```sh
opam exec -- dune exec test/test_freight.exe
```

Expected: all `test_freight` tests pass.

- [ ] **Step 6: Commit**

```sh
jj describe -m "feat(ast): add validated constructors"
jj new
```

---

### Task 3: Register startup-safe Lua command wrappers

**Files:**

- Modify: `plugin/freight.lua`
- Manual test: Neovim command availability

- [ ] **Step 1: Replace direct `FreightStart`-only registration with local wrapper helpers**

Replace the command registration block in `plugin/freight.lua` with:

```lua
local function ensure_and_call(method, args)
  freight.ensure_started()
  vim.schedule(function()
    vim.cmd(method .. (args ~= "" and (" " .. args) or ""))
  end)
end

vim.api.nvim_create_user_command("FreightStart", function()
  freight.start()
end, { desc = "Start the freight RPC process" })

vim.api.nvim_create_user_command("FreightOpen", function()
  ensure_and_call("FreightOpen", "")
end, { desc = "Open a Freight request scratch buffer" })

vim.api.nvim_create_user_command("FreightRun", function()
  ensure_and_call("FreightRun", "")
end, { desc = "Run the request under the cursor" })

vim.api.nvim_create_user_command("FreightEnv", function(opts)
  ensure_and_call("FreightEnv", opts.args)
end, { nargs = "?", desc = "Show or select the active Freight environment" })

vim.api.nvim_create_user_command("FreightView", function(opts)
  ensure_and_call("FreightView", opts.args)
end, {
  nargs = 1,
  complete = function()
    return { "Body", "Headers", "All", "Verbose" }
  end,
  desc = "Switch the Freight response view",
})

vim.api.nvim_create_user_command("FreightHelp", function()
  ensure_and_call("FreightHelp", "")
end, { desc = "Show Freight help" })

vim.api.nvim_create_user_command("FreightHistory", function()
  ensure_and_call("FreightHistory", "")
end, { desc = "Show Freight request history" })

vim.api.nvim_create_user_command("FreightViewHistory", function(opts)
  ensure_and_call("FreightViewHistory", opts.args)
end, { nargs = 1, desc = "Open a Freight history entry" })
```

- [ ] **Step 2: Manually verify commands exist before opening an HTTP file**

Run:

```sh
nvim --clean -u NONE -c 'set rtp+=.' -c 'runtime plugin/freight.lua' -c 'command FreightRun' -c 'qa'
```

Expected: Neovim prints a `FreightRun` user command definition rather than `E184: No such user-defined command`.

- [ ] **Step 3: Commit**

```sh
jj describe -m "fix(plugin): register startup-safe freight commands"
jj new
```

---

### Task 4: Update README command documentation

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Update the feature summary**

In the opening paragraph, replace `B`/`H`/`A` with `B`/`H`/`A`/`V` so the verbose view is advertised:

```markdown
`:FreightRun` parses the request at cursor, substitutes environment variables, runs curl in the background, and renders the response in a scratch buffer with `B`/`H`/`A`/`V` keymaps to toggle between body, headers, full, and verbose views.
```

- [ ] **Step 2: Replace the command table rows**

Replace the existing command table body with:

```markdown
| Command | Description |
| --- | --- |
| `:FreightStart` | Start the plugin process manually |
| `:FreightOpen` | Open a scratch request buffer |
| `:FreightRun` | Parse the request at cursor, execute curl in the background, render the response |
| `:FreightEnv [name]` | Show environment variables, or switch to the named environment |
| `:FreightView <Body\|Headers\|All\|Verbose>` | Switch the response buffer view (also mapped to `B`, `H`, `A`, `V` keys) |
| `:FreightHelp` | Show Freight buffer-local help and keymaps |
| `:FreightHistory` | Show recent request history |
| `:FreightViewHistory <index>` | Open a response from request history |
```

- [ ] **Step 3: Verify README mentions every registered command**

Run:

```sh
for command in FreightStart FreightOpen FreightRun FreightEnv FreightView FreightHelp FreightHistory FreightViewHistory; do grep -q "$command" README.md || exit 1; done
```

Expected: exit code 0.

- [ ] **Step 4: Commit**

```sh
jj describe -m "docs(readme): document freight command surface"
jj new
```

---

### Task 5: Final verification for suggestion fixes

**Files:**

- No new files.

- [ ] **Step 1: Run focused OCaml test binary**

Run:

```sh
opam exec -- dune exec test/test_freight.exe
```

Expected: all tests in `test_freight` pass.

- [ ] **Step 2: Run full tests**

Run:

```sh
opam exec -- dune runtest
```

Expected: pass if the local QCheck runner dependency is available. If it fails with `Library "qcheck-core.runner" not found`, record that as a pre-existing verification blocker from the review and run the focused binaries that are not blocked.

- [ ] **Step 3: Build install target**

Run:

```sh
opam exec -- dune build @install
```

Expected: exit code 0.

- [ ] **Step 4: Check working-copy summary**

Run:

```sh
jj st
```

Expected: only files listed in this plan changed.

- [ ] **Step 5: Final commit description if tasks were squashed into one change**

If execution kept all changes in one jj change instead of one change per task, describe it as:

```sh
jj describe -m "fix(review): address project review suggestions"
```

---

## Self-Review Notes

- S1 maps to Task 1.
- S2 maps to Task 2. This intentionally adds smart constructors without making record types abstract, because fully abstracting `Ast.request`/`Ast.response` would require a broader migration across parser, response parsing, tests, and handlers.
- S3 maps to Task 3.
- S4 maps to Task 4.
- The plan does not address critical/important review findings C1/I1-I7; those need separate plans or a broader fix pass.
