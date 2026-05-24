# VCaml Command Shell Manual Smoke Test

## Preconditions

- `dune build` succeeds.
- Neovim can load the built freight executable through the local VCaml plugin loading workflow.

## Cases

1. Start Neovim with freight plugin loaded.
2. Run `:FreightOpen`.
   - Expected: scratch request buffer opens with `filetype=http`.
3. Enter a simple request:
   ```http
   GET https://example.com

   ```
4. Run `:FreightRun`.
   - Expected: `freight://inspect` buffer opens with method, URL, and curl argv.
   - Expected: no HTTP request is executed.
5. Replace request with malformed text and run `:FreightRun`.
   - Expected: `freight://error` buffer opens with parse details.
6. Run `:FreightEnv dev`.
   - Expected: inspect/info buffer reports active env `dev`.
7. Run `:FreightInspect` from a normal buffer.
   - Expected: friendly diagnostic about missing `freight_curl_cmd` metadata.
