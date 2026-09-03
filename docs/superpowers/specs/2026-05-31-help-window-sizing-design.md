# Help Window Sizing Design

## Goal

Make the Freight help float wide enough to display each help entry on one line, while keeping the window within the available Neovim editor area.

## Scope

In scope:

- Size the help float from its rendered text.
- Measure display width with Neovim's `nvim_strwidth` API so Unicode cell widths are correct.
- Cap the float's inner width to the editor width after reserving space for its rounded border.
- Keep the float centered after sizing.
- Add a regression test for the sizing calculation.

Out of scope:

- Changing the help content or key bindings.
- Resizing unrelated scratch windows.
- Changing the float height behavior.

## Design

`Scratch.show_float` already owns float creation, receives the rendered lines, and queries `nvim_list_uis` for the editor size. It will derive the requested inner width from the maximum display-cell width of its lines.

For each line, `Scratch.show_float` will call `nvim_strwidth`. This delegates Unicode-width handling to Neovim rather than incorrectly using OCaml byte length. The desired width is the maximum of those measurements.

The window will reserve two editor columns for its left and right rounded-border cells. Its inner width is therefore capped to `max 1 (screen_width - 2)`. The existing centered-column calculation will use the capped result. Height remains the number of rendered lines.

If Neovim reports no UI, the existing 80-column fallback remains in effect. An empty line list produces the minimum safe inner width.

## Testing

Add a focused test that exercises the width-selection helper with representative measured widths and a constrained screen width. It must prove that the helper:

- selects the widest line;
- leaves content that fits unchanged;
- caps oversized content while reserving border space; and
- never yields a width below one column.

Run the focused test suite, then the complete test suite and build.

## Acceptance Criteria

- The current Freight help text is rendered without wrapping solely because of the float's width.
- Wider future help entries expand the float up to the usable editor width.
- The float does not extend beyond the editor because of its rounded border.
- Unicode help text is sized by display-cell width.
- Existing behavior outside the help float is unchanged.
