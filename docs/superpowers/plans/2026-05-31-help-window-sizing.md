# Adaptive Help Window Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Size the Freight help float to its longest displayed line without exceeding the Neovim editor width.

**Architecture:** Keep float presentation in `Scratch.show_float`. Add a small pure helper that selects a safe inner width from a screen width and already-measured display widths; use Neovim's `nvim_strwidth` to obtain those measurements so Unicode cell widths are correct. Test the pure helper through the existing unwrapped `freight_plugin` library.

**Tech Stack:** OCaml 5, Dune, OUnit2, Neovim msgpack RPC (`nvim_list_uis`, `nvim_strwidth`, `nvim_open_win`).

## Global Constraints

- Measure rendered line width with Neovim's `nvim_strwidth`, not OCaml byte length.
- Reserve two editor columns for the existing rounded left and right border cells.
- Cap the inner float width to `max 1 (screen_width - 2)`.
- Preserve existing centering, height, help content, key bindings, and non-help scratch-window behavior.

---

## File Structure

- Modify: `bin/scratch.mli` — expose the pure inner-width helper to the focused test.
- Modify: `bin/scratch.ml` — define the helper and use Neovim display-width measurements before opening the help float.
- Create: `test/test_scratch.ml` — OUnit regression tests for width selection and boundary handling.
- Modify: `test/dune` — register the scratch test executable with `freight_plugin` and OUnit2.

### Task 1: Select a safe content-based float width

**Files:**

- Modify: `bin/scratch.mli`
- Modify: `bin/scratch.ml`
- Create: `test/test_scratch.ml`
- Modify: `test/dune`

**Interfaces:**

- Consumes: `screen_width:int` from the `width` field of `nvim_list_uis`; `line_widths:int list` measured by `nvim_strwidth`.
- Produces: `Scratch.float_width : screen_width:int -> line_widths:int list -> int`, the safe inner width passed to `nvim_open_win`.

- [ ] **Step 1: Write the failing regression tests**

Create `test/test_scratch.ml`:

```ocaml
open OUnit2

let test_float_width_uses_widest_line _ =
  assert_equal 28
    (Scratch.float_width ~screen_width:80 ~line_widths:[ 11; 28; 16 ])

let test_float_width_reserves_rounded_border_space _ =
  assert_equal 78
    (Scratch.float_width ~screen_width:80 ~line_widths:[ 120 ])

let test_float_width_never_returns_less_than_one _ =
  assert_equal 1
    (Scratch.float_width ~screen_width:1 ~line_widths:[])

let suite =
  "scratch" >::: 
  [ "uses widest line" >:: test_float_width_uses_widest_line
  ; "reserves rounded border space" >:: test_float_width_reserves_rounded_border_space
  ; "never returns less than one" >:: test_float_width_never_returns_less_than_one
  ]

let () = run_test_tt_main suite
```

Append this stanza to `test/dune`:

```lisp
(test
 (name test_scratch)
 (modules test_scratch)
 (libraries freight_plugin ounit2 msgpck))
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
opam exec -- dune runtest --force -- test/test_scratch.exe
```

Expected: the test target fails to compile because `Scratch.float_width` is not yet defined.

- [ ] **Step 3: Add the helper to the module interface**

Add this declaration to `bin/scratch.mli` before `show_float`:

```ocaml
val float_width : screen_width:int -> line_widths:int list -> int
```

- [ ] **Step 4: Implement the pure width helper and connect it to Neovim display measurements**

Add this helper after `set_window_chrome` in `bin/scratch.ml`:

```ocaml
let float_width ~screen_width ~line_widths =
  let content_width = List.fold_left max 1 line_widths in
  let available_width = max 1 (screen_width - 2) in
  min content_width available_width
```

In `show_float`, replace the fixed-width binding:

```ocaml
  let width = 40 in
```

with this code after `screen_w, screen_h` have been obtained:

```ocaml
  let line_widths =
    List.map
      (fun line ->
        match call "nvim_strwidth" [ Msgpck.String line ] with
        | Msgpck.Int width -> width
        | _ -> 0)
      flat_lines
  in
  let width = float_width ~screen_width:screen_w ~line_widths in
```

Keep the existing `height`, `row`, `col`, rounded border, focus behavior, and keymaps unchanged.

- [ ] **Step 5: Run the focused test to verify it passes**

Run:

```bash
opam exec -- dune runtest --force -- test/test_scratch.exe
```

Expected: all three `scratch` tests pass.

- [ ] **Step 6: Run the full automated verification**

Run:

```bash
opam exec -- dune runtest
opam exec -- dune build @install
```

Expected: both commands exit successfully with no test failures or build errors.

- [ ] **Step 7: Review the actual change**

Run:

```bash
jj diff --git
```

Confirm that the only production change is `Scratch.show_float` sizing its inner width from `nvim_strwidth` results and capping it to the editor width less the rounded border.

- [ ] **Step 8: Commit the implementation**

Run:

```bash
jj describe -m "fix(ui): size help window to its content"
jj new
```

Expected: the implementation change has the stated Conventional Commit description and the new working copy is empty.

## Self-Review

**Spec coverage:** The single task covers content-derived sizing, Unicode display measurement, rounded-border capping, centered placement, a lower bound for tiny UIs, and focused regression coverage. It deliberately leaves help text, key bindings, height, and other scratch windows unchanged.

**Placeholder scan:** No placeholders, deferred implementation notes, or undefined steps remain.

**Type consistency:** The test, `.mli`, implementation, and call site all use `float_width ~screen_width ~line_widths : int`. The line widths are `int list` values returned by `nvim_strwidth`, and the result remains the `Msgpck.Int` passed as the float's `width` option.
