# VCaml Command Shell Manual Smoke Test

## Preconditions

- OCaml 5.2.1 opam switch with `vcaml.v0.17.0` and the v0.17 Jane Street stack installed (see `freight-vcaml` switch).
- `dune build` succeeds from the repo root and produces `_build/default/bin/main.exe`.
- Neovim 0.9.1+ (vcaml v0.17 is tested against 0.9.1).

## Plugin loading (lazy.nvim)

This repo lives at `~/projects/vibe/freight-core-library`, outside lazy's default `:dev.path = "~/projects"`. Pin the directory explicitly in a plugin spec:

**Lua spec:**

```lua
{
  dir = vim.fn.expand("~/projects/vibe/freight-core-library"),
  name = "freight",
  ft = { "http", "rest" },
  cmd = { "FreightStart", "FreightOpen", "FreightRun", "FreightEnv", "FreightInspect" },
}
```

**Fennel spec (matches local nvim config style):**

Create `fnl/plugins/freight.fnl`:

```fennel
;; Freight HTTP client (OCaml/VCaml).
{:dir (vim.fn.expand "~/projects/vibe/freight-core-library")
 :name :freight
 :ft [:http :rest]
 :cmd [:FreightStart :FreightOpen :FreightRun :FreightEnv :FreightInspect]}
```

The repo ships `plugin/freight.vim` and `autoload/freight.vim`:

- `plugin/freight.vim` defines `:FreightStart` and a `BufRead *.http,*.rest` autocmd that auto-launches the plugin process.
- `autoload/freight.vim` defines `freight#start`, `freight#on_startup` (called by the OCaml side via `notify_fn`), and resolves the executable from `g:freight_executable` (if set) or `<plugin-root>/_build/default/bin/main.exe`.

The four user commands (`:FreightOpen`, `:FreightRun`, `:FreightEnv`, `:FreightInspect`) are registered by the OCaml plugin during `on_startup` — they appear after the process has started.

## Cases

1. From this repo, run `dune build` (on the `freight-vcaml` opam switch).
2. Open Neovim with the lazy spec above installed. Verify `:Lazy` shows `freight` loaded or pending.
3. Open a `.http` file (e.g. `:e /tmp/scratch.http`). The `BufRead` autocmd should fire and `:FreightStart` should launch the plugin process.
   - Expected: no error, `freight#ready()` returns `1` shortly after.
4. Run `:FreightOpen`.
   - Expected: scratch request buffer named `freight://request` opens with `filetype=http`.
5. In the request buffer, enter:
   ```http
   GET https://example.com

   ```
6. Run `:FreightRun`.
   - Expected: `freight://inspect` buffer opens with method, URL, and curl argv.
   - Expected: no HTTP request is executed.
7. Replace the request body with malformed text and run `:FreightRun`.
   - Expected: `freight://error` buffer opens with parse details.
8. Run `:FreightEnv dev`.
   - Expected: inspect/info buffer reports active env `dev`.
9. Run `:FreightInspect` from a normal buffer.
   - Expected: friendly diagnostic about missing `freight_curl_cmd` metadata.

## Troubleshooting

- `freight: executable not found` — run `dune build` in the repo root, or set `let g:freight_executable = '/abs/path/to/main.exe'` before the autocmd fires.
- Plugin starts but commands `:FreightOpen` etc. are missing — the OCaml `on_startup` may have errored before registering commands. Check `:messages` and the job's stderr (visible via `:checkhealth` or `:Lazy log`).
- `core_unix.command_unix` errors at runtime — ensure the binary was built on the `freight-vcaml` switch, not the system OCaml switch.
