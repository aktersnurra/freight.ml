# freight.ml Core Library First Design

Date: 2026-05-24

## Goal

Implement the first freight.ml milestone as a pure OCaml `lib/` library. The milestone covers the core request/response model, `.http` parsing, environment loading and substitution, curl argument construction, response parsing/rendering, simple response chaining, and pure response-buffer helpers.

The VCaml persistent plugin and Async process execution are out of scope for this milestone except that `bin/main.ml` should continue to compile.

## Current project state

The repository is a fresh dune project:

- `dune-project` has placeholder package metadata.
- `freight.opam` is empty/generated placeholder state.
- `lib/dune` defines an empty `freight` library.
- `bin/main.ml` prints `Hello, World!`.
- `test/test_freight.ml` is empty.
- No git repository was detected from the working directory during discovery.

## Architecture

Use explicit `.mli` interfaces for every library module. The interfaces are the design boundary; implementations should remain small and focused.

### `Ast`

Defines shared domain types from the v1 spec:

- HTTP method variants, including `Custom of string`.
- Request body variants: inline, file, none.
- Request, response, parse error, and HTTP file records.

Small conversion helpers may be added where useful, for example method-to-string and method-of-string.

### `Parser`

Uses Angstrom to parse the JetBrains-style `.http` subset:

- `###` request separators.
- Optional comments before a request.
- `# @name` metadata capture.
- Request line, headers, mandatory blank line before body, inline body, and file body.
- Lenient trailing whitespace and CRLF handling.

The public API should include:

- `parse_string : string -> (Ast.http_file, Ast.parse_error) result`
- `parse_file : string -> (Ast.http_file, Ast.parse_error) result`

Cursor lookup needs source ranges. Because the spec's `Ast.request` has no line metadata, the parser should internally track ranges and expose cursor lookup only through a ranged parse result or a parallel private representation. Do not add location fields to `Ast.request` unless the interface design explicitly requires it.

### `Env`

Implements pure-ish environment loading and substitution:

- Starting at the `.http` file directory, walk upward to root.
- Merge `.env`, `.env.<active_env>`, then `.env.local`; later values win.
- Substitute `{{key}}` in URLs, headers, inline bodies, and body-file paths.
- Unknown variables remain unchanged.

Use the OCaml standard `Map.Make(String)` for `Env.t` unless Base is deliberately added to `lib/`. The original spec mentions `Map.Poly.t`, but the current core dependency list does not include Base/Core.

### `Executor`

Keep this module pure in the core milestone.

- Implement `to_curl : Ast.request -> curl_invocation`.
- Include method, URL, headers, body flags, `-i`, `-s`, and `-w` arguments.
- Do not implement `Async.Process.run` in `lib/`; that belongs in the later VCaml/Async executable layer.

### `Response`

Implements curl output parsing and response rendering:

- Parse `curl -i -w` output into `Ast.response`.
- Detect content type from response headers.
- Pretty-print JSON with Yojson.
- Leave XML/HTML unchanged or with minimal naive formatting.
- Render response-buffer lines with status and duration.

Highlight application is not part of `lib/`; `lib/` may expose a status category if useful later.

### `Chaining`

Implements named-response extraction and environment injection:

- Extract simple dot-separated JSON object paths from response bodies.
- Extract response headers by name.
- Inject keys under `name.response.body.*` and `name.response.headers.*` for named requests.
- No array indexing for v1.

### `Buffer`

Implements pure buffer helpers only:

- `buffer_name : Ast.request -> string`
- slug generation for unnamed requests.
- `filetype_of_content_type : Response.content_type -> string`

Actual Neovim buffer creation, variables, windows, options, and highlights remain in `bin/` for a later milestone.

## Dependencies

Library dependencies for this milestone:

- `angstrom`
- `yojson`
- `re`

Executable dependencies are deferred until VCaml wiring:

- `vcaml`
- `async`
- `core`

## Testing strategy

Add tests under `test/` for the core modules:

- Parser: separators, names, headers, inline body, file body, trailing whitespace, CRLF.
- Env: file precedence, active environment override, local override, substitution, unknown variable preservation.
- Executor: curl argument construction for methods, headers, inline body, file body, PUT upload behavior.
- Response: status/header/body parsing, duration conversion, content-type detection, JSON pretty-printing, render output.
- Chaining: body token extraction, header extraction, environment injection.
- Buffer: named and slugged buffer names, filetype mapping.

## Error handling

Core functions should return `result` for expected failures. Use structured error types where interfaces need callers to distinguish error categories. Avoid exceptions for control flow.

UI-facing error buffers are out of scope for this milestone and will be handled in the VCaml layer later.

## Acceptance criteria

- `lib/` contains focused `.ml` and `.mli` modules for the core milestone.
- `lib/` has no VCaml, Async, or Core dependency.
- `dune build` succeeds.
- Core tests exercise all implemented modules.
- `bin/main.ml` still compiles, even if it remains a placeholder.
