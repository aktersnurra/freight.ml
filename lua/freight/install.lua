-- Release-binary installer.
--
-- freight's runtime is a single OCaml executable that Neovim drives over
-- msgpack RPC. Building it needs an OCaml toolchain, which most Neovim users
-- do not have, so releases ship prebuilt binaries and this module fetches the
-- one matching the current platform.
--
-- Resolution order used by freight.lua: g:freight_executable, then a binary
-- installed here, then a local `dune build` tree (the dev loop).

local M = {}

-- Bumped in lockstep with the git tag the release workflow builds. The plugin
-- refuses a binary installed for a different version rather than failing later
-- with an opaque RPC error.
M.version = "v0.1.0"

local repo = "aktersnurra/freight.ml"

local function install_dir()
  return vim.fn.stdpath("data") .. "/freight"
end

function M.binary_path()
  return install_dir() .. "/main.exe"
end

local function stamp_path()
  return install_dir() .. "/version"
end

-- The release asset for this machine, or nil plus a reason when unsupported.
-- Kept as one table so :checkhealth can report the same mapping the installer
-- uses.
function M.asset()
  local uname = vim.uv or vim.loop
  local sys = uname.os_uname()
  local os_name, arch = sys.sysname, sys.machine

  if arch == "arm64" then
    arch = "aarch64"
  elseif arch == "amd64" then
    arch = "x86_64"
  end

  if os_name == "Linux" then
    if arch == "x86_64" or arch == "aarch64" then
      return "freight-linux-" .. arch
    end
    return nil, "unsupported Linux architecture: " .. arch
  elseif os_name == "Darwin" then
    if arch == "aarch64" then
      return "freight-macos-aarch64"
    end
    -- Intel Macs are not built by the release workflow.
    return nil, "unsupported macOS architecture: " .. arch .. " (build from source)"
  end

  return nil, "unsupported platform: " .. os_name .. "/" .. arch
end

-- Version recorded alongside the installed binary, or nil when absent.
function M.installed_version()
  local f = io.open(stamp_path(), "r")
  if not f then
    return nil
  end
  local v = f:read("*l")
  f:close()
  if v == nil or v == "" then
    return nil
  end
  return v
end

function M.is_installed()
  return vim.fn.executable(M.binary_path()) == 1
    and M.installed_version() == M.version
end

local function run(cmd)
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, out
  end
  return out, nil
end

-- SHA256 of a file using whichever of sha256sum/shasum this machine has.
-- Returns nil when neither exists, which downgrades to an unverified install
-- rather than blocking it.
local function sha256(path)
  if vim.fn.executable("sha256sum") == 1 then
    local out = run({ "sha256sum", path })
    return out and out:match("^(%x+)")
  elseif vim.fn.executable("shasum") == 1 then
    local out = run({ "shasum", "-a", "256", path })
    return out and out:match("^(%x+)")
  end
  return nil
end

-- Expected checksum for `asset` parsed out of the release's SHA256SUMS.
local function expected_sum(sums, asset)
  for line in sums:gmatch("[^\r\n]+") do
    local sum, name = line:match("^(%x+)%s+%*?(.+)$")
    if name then
      name = name:gsub("^%./", "")
      if name == asset then
        return sum
      end
    end
  end
  return nil
end

local function url_for(asset)
  return ("https://github.com/%s/releases/download/%s/%s"):format(repo, M.version, asset)
end

-- Downloads the binary for this platform into stdpath("data")/freight.
-- Returns true on success, or false plus a message. Safe to call when already
-- installed: it is a no-op unless `force` is set.
function M.install(opts)
  opts = opts or {}

  if M.is_installed() and not opts.force then
    return true, "freight: binary already installed (" .. M.version .. ")"
  end

  local asset, why = M.asset()
  if not asset then
    return false, "freight: " .. why
  end

  if vim.fn.executable("curl") == 0 then
    return false, "freight: curl not found on $PATH (needed to download the binary)"
  end

  local dir = install_dir()
  vim.fn.mkdir(dir, "p")

  local tmp = dir .. "/main.exe.download"
  local url = url_for(asset)

  local _, err = run({ "curl", "-fsSL", "--retry", "3", "-o", tmp, url })
  if err then
    vim.fn.delete(tmp)
    return false, "freight: download failed from " .. url .. "\n" .. err
  end

  -- Verify against the release's published SHA256SUMS. A missing sums file or
  -- no local hashing tool is a warning, not a failure; a *mismatch* is fatal.
  local warning = nil
  local sums = run({ "curl", "-fsSL", "--retry", "3", url_for("SHA256SUMS") })
  if sums then
    local want = expected_sum(sums, asset)
    local got = sha256(tmp)
    if want and got then
      if want:lower() ~= got:lower() then
        vim.fn.delete(tmp)
        return false,
          ("freight: checksum mismatch for %s\n  expected %s\n  got      %s"):format(asset, want, got)
      end
    elseif not got then
      warning = "freight: no sha256sum/shasum available; binary not verified"
    elseif not want then
      warning = "freight: " .. asset .. " missing from SHA256SUMS; binary not verified"
    end
  else
    warning = "freight: could not fetch SHA256SUMS; binary not verified"
  end

  local target = M.binary_path()
  local ok = os.rename(tmp, target)
  if not ok then
    vim.fn.delete(tmp)
    return false, "freight: could not move binary into " .. target
  end
  vim.fn.system({ "chmod", "+x", target })

  local f = io.open(stamp_path(), "w")
  if f then
    f:write(M.version .. "\n")
    f:close()
  end

  local msg = "freight: installed " .. asset .. " " .. M.version
  if warning then
    msg = msg .. "\n" .. warning
  end
  return true, msg
end

-- Entry point for the lazy.nvim `build` hook and :FreightInstall.
function M.build(opts)
  local ok, msg = M.install(opts)
  vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  return ok
end

return M
