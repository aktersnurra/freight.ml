#!/usr/bin/env bash
# Headless end-to-end test: drives the real :FreightRun through the full nvim
# RPC stack against a local mock HTTP server, then asserts on the response
# buffer. This is the only test that exercises the Lua side, jobstart, msgpack
# RPC, and the OCaml handlers together — everything the unit/e2e suites mock.
#
# Requires: nvim, python3, and a built binary (dune build). Runnable from
# anywhere; paths resolve relative to this script.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
exe="$repo/_build/default/bin/main.exe"

if [ ! -x "$exe" ]; then
  echo "FAIL: binary not built at $exe (run: dune build)" >&2
  exit 1
fi

workdir="$(mktemp -d)"
server_pid=""
cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$workdir"
}
trap cleanup EXIT

# Mock server: replies to any GET with a fixed JSON body; prints its port first.
cat > "$workdir/mock.py" <<'PY'
import http.server, socketserver
BODY = b'{"token":"e2e-abc","nested":{"id":"deep-42"}}'
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)
    def log_message(self, *a):
        pass
srv = socketserver.TCPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PY

exec 3< <(python3 "$workdir/mock.py")
server_pid=$!
read -r port <&3
if [ -z "${port:-}" ]; then echo "FAIL: mock did not report a port" >&2; exit 1; fi

printf '# @name ping\nGET http://127.0.0.1:%s/ping\nAccept: application/json\n' \
  "$port" > "$workdir/test.http"

# Minimal init: prepend the repo to rtp, point at the built binary, load the
# plugin (registers :FreightRun). -u NONE would skip plugin/ sourcing.
cat > "$workdir/init.lua" <<LUA
vim.opt.runtimepath:prepend("$repo")
vim.g.freight_executable = "$exe"
vim.cmd("runtime! plugin/freight.lua")
LUA

out="$workdir/out.txt"
# 2G puts the cursor on the request line (line 1 is the # @name comment).
nvim --headless -u "$workdir/init.lua" \
  -c "edit $workdir/test.http" \
  -c "normal! 2G" \
  -c "FreightRun" \
  -c "lua vim.wait(6000, function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          local ok, name = pcall(vim.api.nvim_buf_get_name, b)
          if ok and name:match('freight://') then
            local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
            if #lines > 0 and not (lines[1] or ''):match('Running') then return true end
          end
        end
        return false
      end)" \
  -c "lua local f = io.open('$out', 'w')
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local ok, name = pcall(vim.api.nvim_buf_get_name, b)
        if ok and name:match('freight://') then
          f:write(table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), '\n'))
        end
      end
      f:close()" \
  -c "qa!" 2>/dev/null || true

if [ ! -s "$out" ]; then echo "FAIL: no response buffer captured" >&2; exit 1; fi

fail=0
grep -q "HTTP 200" "$out" || { echo "FAIL: expected 'HTTP 200'" >&2; fail=1; }
grep -q "e2e-abc" "$out" || { echo "FAIL: expected body token 'e2e-abc'" >&2; fail=1; }
if [ "$fail" = 1 ]; then echo "--- response buffer ---" >&2; cat "$out" >&2; exit 1; fi

echo "PASS: :FreightRun end-to-end (200 + body) through headless nvim"
