# Changelog

## [Unreleased]

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
