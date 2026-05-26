# Polished Output Design

## Goal

Make Freight feel like a polished Neovim tool while keeping the current scratch-buffer architecture: Telescope for environment picking, cleaner scratch window chrome, and more readable response output.

## Scope

In scope:

- `:FreightEnv` with no argument opens a Telescope picker.
- `:FreightEnv <name>` keeps immediate environment switching.
- Missing Telescope produces a clear user-facing error.
- Freight scratch buffers hide line numbers and editor gutter chrome.
- Response output uses clearer sections and spacing.
- Loading and error output becomes concise and scannable.

Out of scope:

- Full multi-pane UI.
- Replacing scratch buffers with floating windows.
- Redesigning request execution semantics.
- Fixing the existing double-curl verbose behavior.

## Design

### Environment picker

The Lua plugin owns the Telescope picker because Telescope is a Lua-side Neovim dependency. The OCaml runtime still owns applying the selected environment.

Flow:

1. `:FreightEnv dev` sends `FreightEnv` with argument `dev` through RPC, as today.
2. `:FreightEnv` checks for Telescope.
3. If Telescope is missing, notify: `freight: Telescope is required for :FreightEnv without an argument`.
4. If Telescope exists, gather candidate environment names from the current buffer directory:
   - `dev` from `.env.dev`
   - `local` is not offered for `.env.local` because that file is always loaded as local override, not an active env
   - duplicates are removed and names sorted
5. Selecting an item calls the existing RPC method: `FreightEnv <name>`.

### Scratch buffer chrome

All Freight scratch buffers should feel like app surfaces, not normal editing buffers. `bin/scratch.ml` should set window-local options after opening the scratch buffer:

- `number=false`
- `relativenumber=false`
- `signcolumn=no`
- `foldcolumn=0`

This belongs in the scratch renderer so every Freight surface benefits consistently.

### Response output

Keep the current body filetype detection for body-only response buffers. Improve the textual renderers in `lib/response.ml`:

All view:

```text
HTTP 200 OK · 42 ms

Headers
Content-Type: application/json
X-Request-Id: abc

Body
{
  "ok": true
}
```

Headers view:

```text
HTTP 200 OK · 42 ms

Headers
Content-Type: application/json
X-Request-Id: abc
```

Loading:

```text
Running request…
```

Execution error:

```text
Request failed
<message>
```

Parse error:

```text
Response parse failed
<message>
```

## Testing

- OUnit tests for response renderers:
  - all view includes section headings and pretty JSON body
  - headers view includes status and `Headers`
- Handler tests or direct code inspection for loading/error string changes.
- Headless Neovim checks:
  - plugin loads
  - `:FreightEnv` with missing Telescope emits the required message path where feasible
- Full verification:
  - `opam exec -- dune runtest`
  - `opam exec -- dune build @install`

## Acceptance Criteria

- `:FreightEnv` opens Telescope when no argument is supplied.
- `:FreightEnv dev` still switches directly.
- Missing Telescope gives the required install message.
- Freight scratch windows do not show line numbers.
- Response output is sectioned and easier to scan.
- Existing tests pass.
