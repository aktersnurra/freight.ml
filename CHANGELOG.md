# Changelog

## [Unreleased]

## [0.1.2] - 2026-10-14

### Fixed
- Load `@name = value` file variables, including declarations before the first `###`, in Run, RunAll, and Inspect.
- Execute each request once and reuse its captured verbose trace instead of replaying successful requests.
- Display curl diagnostics for malformed URLs and transport failures.
- Reject orphaned request metadata in declarations-only blocks with a source line number.

## [0.1.1] - 2026-10-02

### Fixed
- Sized the `:FreightHelp` float to its longest line, capped to the editor width, instead of clipping descriptions at 40 columns.

## [0.1.0] - 2026-08-26

### Added
- Documented run-all grouped results and Enter-to-open behavior in the README.
- Added run-all commands and keymaps to `:FreightHelp`.
- Added suggested `<leader>r` Freight keymaps to the README.
- Added `o` in run-all results to jump back to the source request.

### Changed
- Polished run-all result buffers with progress updates, hidden empty groups, and full HTTP failure response details.
