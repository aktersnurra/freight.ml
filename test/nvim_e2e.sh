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
import http.server, socketserver, sys
BODY = b'{"token":"e2e-abc","nested":{"id":"deep-42"}}'
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        with open(sys.argv[1], "a") as log:
            log.write(self.path + "\n")
        body = b'{"result":"created-once"}'
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
srv = socketserver.TCPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PY

exec 3< <(python3 "$workdir/mock.py" "$workdir/posts.log")
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

# Exercise the real Eio failure path, then reuse the same plugin process.
cat > "$workdir/failure.lua" <<LUA
local ok, err = pcall(function()
  vim.cmd("edit $workdir/test.http")
  local source = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(source, 0, -1, false, {
    "GET example.com/ y",
    "###",
    "GET http://127.0.0.1:$port/ping",
    "###",
    "POST http://127.0.0.1:$port/create",
    "Content-Type: application/json",
    "",
    "{}",
  })
  local function wait_for(expected)
    assert(vim.wait(6000, function()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b)
            and vim.api.nvim_buf_get_name(b):match("freight://") then
          local text = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
          if text:find(expected, 1, true) then return true end
        end
      end
      return false
    end), "response did not contain: " .. expected)
  end
  local function run(row, expected)
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_win_set_cursor(0, {row, 0})
    vim.cmd("FreightRun")
    wait_for(expected)
  end
  run(1, "curl: (3)")
  run(3, "e2e-abc")
  run(5, "created-once")
  vim.cmd("FreightView Verbose")
  wait_for("> POST /create HTTP/1.1")
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
end
LUA

nvim --headless -u "$workdir/init.lua" \
  -c "luafile $workdir/failure.lua" -c "qa!"

if [ "$(grep -c '^/create$' "$workdir/posts.log")" -ne 1 ]; then
  echo "FAIL: POST /create must reach the server exactly once" >&2
  cat "$workdir/posts.log" >&2
  exit 1
fi

echo "PASS: malformed URL reports curl error and next request succeeds"
echo "PASS: POST executes once and Verbose shows its captured trace"
