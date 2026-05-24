# Raw Msgpack-RPC Plugin Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the VCaml executable layer with a hand-rolled msgpack-rpc server that works with Neovim 0.13+, keeping `lib/` unchanged.

**Architecture:** A single Async event loop reads msgpack frames from stdin, dispatches incoming Neovim requests by method name, and sends RPC calls back to Neovim via stdout. All existing handler logic (parse, env, inspect, run) is preserved; only the transport and Neovim API call layer changes. The five existing `bin/` modules are rewritten without VCaml; `bin/rpc.ml` replaces the VCaml client abstraction.

**Tech Stack:** OCaml, Async, Core, msgpack, dune. No VCaml.

---

## File structure

- Replace: `bin/main.ml` — Async entry point: reads channel id from startup notification, registers commands, runs the dispatch loop.
- Replace: `bin/rpc.ml` + `bin/rpc.mli` — Low-level msgpack-rpc transport: frame reader/writer, synchronous `call` helper, incoming request dispatcher.
- Replace: `bin/scratch.ml` + `bin/scratch.mli` — Scratch buffer helper using raw `rpc` calls instead of VCaml.
- Replace: `bin/state.ml` + `bin/state.mli` — Unchanged logic, remove VCaml/Async types from signature.
- Replace: `bin/handlers.ml` + `bin/handlers.mli` — Same four handlers, take `Rpc.t` instead of VCaml client.
- Replace: `bin/request_view.ml` + `bin/request_view.mli` — Pure rendering; no VCaml dependency, likely unchanged.
- Modify: `bin/dune` — Remove vcaml/ppx_jane, add msgpack.
- Modify: `dune-project` — Remove vcaml/async/core from package deps, add msgpack.

---

### Task 1: Update build configuration

**Files:**

- Modify: `bin/dune`
- Modify: `dune-project`

- [ ] **Step 1: Replace `bin/dune`**

```lisp
(executable
 (public_name freight)
 (name main)
 (modules main rpc state scratch handlers request_view)
 (libraries freight msgpack async core core_unix.command_unix)
 (flags (:standard -w @A-4-33-40-41-42-43-34-44)))
```

- [ ] **Step 2: Update package deps in `dune-project`**

Replace the `(depends ...)` stanza in the `(package ...)` block with:

```lisp
(depends
 ocaml
 dune
 angstrom
 yojson
 re
 msgpack
 async
 core
 (ounit2 :with-test)
 (qcheck-core :with-test))
```

- [ ] **Step 3: Install msgpack**

Run:

```bash
opam install msgpack
```

Expected: installs `msgpack.1.3.0`.

- [ ] **Step 4: Verify dune can find the library**

Run:

```bash
dune build 2>&1 | head -20
```

Expected: errors about missing modules (we haven't rewritten them yet) but NOT "library msgpack not found".

---

### Task 2: `Rpc` transport module

**Files:**

- Create: `bin/rpc.mli`
- Create: `bin/rpc.ml`

This module owns all msgpack-rpc I/O. Neovim speaks msgpack-rpc over stdin/stdout using 4-byte big-endian length-prefixed frames.

**Msgpack-rpc message formats:**
- Request from Neovim: `[0, msgid, "MethodName", [params...]]`
- Response to Neovim: `[1, msgid, null, result]` or `[1, msgid, error_str, null]`
- Notification from Neovim: `[2, "MethodName", [params...]]`
- Call to Neovim (we send): `[0, msgid, "nvim_command", [params...]]`
- Reply from Neovim (we receive): `[1, msgid, null, result]`

- [ ] **Step 1: Create `bin/rpc.mli`**

```ocaml
type t

type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpack.t list }
  | Notification of { method_ : string; params : Msgpack.t list }

val create : unit -> t

val read : t -> incoming Async.Deferred.t
(** Read one msgpack-rpc message from stdin. Blocks until a message arrives. *)

val reply_ok : t -> msgid:int -> Msgpack.t -> unit
(** Send [1, msgid, nil, result] to stdout. *)

val reply_error : t -> msgid:int -> string -> unit
(** Send [1, msgid, error_str, nil] to stdout. *)

val call : t -> string -> Msgpack.t list -> (Msgpack.t, string) result Async.Deferred.t
(** Send a request to Neovim and wait for its reply. *)
```

- [ ] **Step 2: Create `bin/rpc.ml`**

```ocaml
open Core
open Async

type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpack.t list }
  | Notification of { method_ : string; params : Msgpack.t list }

type t = {
  reader : Reader.t;
  writer : Writer.t;
  mutable next_msgid : int;
  pending : (int, Msgpack.t Or_error.t Ivar.t) Hashtbl.t;
}

let create () =
  { reader = Lazy.force Reader.stdin
  ; writer = Lazy.force Writer.stdout
  ; next_msgid = 1
  ; pending = Hashtbl.create (module Int)
  }

let read_frame reader =
  let buf = Bytes.create 4 in
  let%bind () = Reader.really_read reader buf >>| function
    | `Ok -> ()
    | `Eof _ -> failwith "stdin closed"
  in
  let len =
    (Char.to_int (Bytes.get buf 0) lsl 24)
    lor (Char.to_int (Bytes.get buf 1) lsl 16)
    lor (Char.to_int (Bytes.get buf 2) lsl 8)
    lor (Char.to_int (Bytes.get buf 3))
  in
  let payload = Bytes.create len in
  let%map () = Reader.really_read reader payload >>| function
    | `Ok -> ()
    | `Eof _ -> failwith "stdin closed"
  in
  Bytes.to_string payload

let write_frame writer bytes =
  let len = String.length bytes in
  let header = Bytes.create 4 in
  Bytes.set header 0 (Char.of_int_exn (len lsr 24 land 0xff));
  Bytes.set header 1 (Char.of_int_exn (len lsr 16 land 0xff));
  Bytes.set header 2 (Char.of_int_exn (len lsr 8 land 0xff));
  Bytes.set header 3 (Char.of_int_exn (len land 0xff));
  Writer.write writer (Bytes.to_string header);
  Writer.write writer bytes

let encode msg =
  Msgpack.serialize msg |> Bytes.to_string

let decode bytes =
  match Msgpack.deserialize (Bytes.of_string bytes) with
  | Ok (msg, _) -> msg
  | Error e -> failwithf "msgpack decode error: %s" e ()

let parse_incoming msg =
  match msg with
  | Msgpack.Array [ Int 0; Int msgid; String method_; Array params ] ->
    Request { msgid; method_; params }
  | Msgpack.Array [ Int 2; String method_; Array params ] ->
    Notification { method_; params }
  | Msgpack.Array [ Int 1; Int msgid; err; result ] ->
    (* Route reply to pending call *)
    `Reply (msgid, err, result)
  | _ -> failwith "unexpected msgpack-rpc message shape"

let read t =
  let rec loop () =
    let%bind frame = read_frame t.reader in
    let msg = decode frame in
    match parse_incoming msg with
    | `Reply (msgid, err, result) ->
      (match Hashtbl.find t.pending msgid with
       | None -> loop ()
       | Some ivar ->
         Hashtbl.remove t.pending msgid;
         let value =
           match err with
           | Msgpack.Nil -> Ok result
           | Msgpack.String s -> Or_error.error_string s
           | _ -> Or_error.error_string "rpc error"
         in
         Ivar.fill ivar value;
         loop ())
    | #incoming as inc -> return inc
  in
  loop ()

let reply_ok t ~msgid result =
  let msg = Msgpack.Array [ Int 1; Int msgid; Nil; result ] in
  write_frame t.writer (encode msg)

let reply_error t ~msgid err =
  let msg = Msgpack.Array [ Int 1; Int msgid; String err; Nil ] in
  write_frame t.writer (encode msg)

let call t method_ params =
  let msgid = t.next_msgid in
  t.next_msgid <- msgid + 1;
  let ivar = Ivar.create () in
  Hashtbl.set t.pending ~key:msgid ~data:ivar;
  let msg = Msgpack.Array [ Int 0; Int msgid; String method_; Array params ] in
  write_frame t.writer (encode msg);
  let%map result = Ivar.read ivar in
  Result.map_error result ~f:Error.to_string_hum
```

- [ ] **Step 3: Attempt build (will fail — other modules still reference VCaml)**

Run:

```bash
dune build bin/rpc.ml 2>&1 | head -20
```

Expected: rpc.ml itself compiles, errors from other modules only.

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(rpc): add raw msgpack-rpc transport"
jj new
```

---

### Task 3: `State` module

**Files:**

- Replace: `bin/state.mli`
- Replace: `bin/state.ml`

Remove `response_history` (unused in scope) and all VCaml references.

- [ ] **Step 1: Replace `bin/state.mli`**

```ocaml
type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
```

- [ ] **Step 2: Replace `bin/state.ml`**

```ocaml
type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
}

let create () = { active_env = None; env = Freight.Env.empty }

let set_active_env state env_name =
  state.active_env <- env_name
```

- [ ] **Step 3: Commit**

```bash
jj describe -m "refactor(state): remove vcaml dependency"
jj new
```

---

### Task 4: `Scratch` buffer helper

**Files:**

- Replace: `bin/scratch.mli`
- Replace: `bin/scratch.ml`

Replace VCaml buffer API calls with raw `Rpc.call` calls.

Neovim API used:
- `nvim_create_buf listed=false scratch=true` → buffer handle (Int)
- `nvim_buf_set_name handle name`
- `nvim_buf_set_option handle "buftype" "nofile"`
- `nvim_buf_set_option handle "filetype" ft`
- `nvim_buf_set_option handle "modifiable" true`
- `nvim_buf_set_lines handle 0 -1 false [lines]`
- `nvim_buf_set_option handle "modifiable" false`
- `nvim_command "split | buffer <handle>"`

- [ ] **Step 1: Replace `bin/scratch.mli`**

```ocaml
val show
  :  rpc:Rpc.t
  -> name:string
  -> filetype:string
  -> lines:string list
  -> unit Async.Deferred.t
```

- [ ] **Step 2: Replace `bin/scratch.ml`**

```ocaml
open Async

let nvim_call rpc method_ params =
  match%map Rpc.call rpc method_ params with
  | Ok result -> result
  | Error e -> failwithf "nvim call %s failed: %s" method_ e ()

let show ~rpc ~name ~filetype ~lines =
  let open Msgpack in
  let%bind buf = nvim_call rpc "nvim_create_buf" [ Bool false; Bool true ] in
  let handle = match buf with Int n -> n | _ -> failwith "expected buffer handle" in
  let%bind _ = nvim_call rpc "nvim_buf_set_name" [ Int handle; String name ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Int handle; String "buftype"; String "nofile" ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Int handle; String "filetype"; String filetype ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Int handle; String "modifiable"; Bool true ] in
  let msgpack_lines = Array (List.map lines ~f:(fun l -> String l)) in
  let%bind _ = nvim_call rpc "nvim_buf_set_lines" [ Int handle; Int 0; Int (-1); Bool false; msgpack_lines ] in
  let%bind _ = nvim_call rpc "nvim_buf_set_option" [ Int handle; String "modifiable"; Bool false ] in
  let%map _ = nvim_call rpc "nvim_command" [ String (Printf.sprintf "split | buffer %d" handle) ] in
  ()
```

- [ ] **Step 3: Commit**

```bash
jj describe -m "refactor(scratch): use raw rpc instead of vcaml"
jj new
```

---

### Task 5: `Request_view` rendering

**Files:**

- Replace: `bin/request_view.mli`
- Replace: `bin/request_view.ml`

This module is pure — no VCaml dependency. Verify and keep as-is, just removing any VCaml/Async imports.

- [ ] **Step 1: Read current `bin/request_view.ml`**

Read the file and check for any VCaml/Async imports at the top. If none, copy it unchanged.

- [ ] **Step 2: Replace `bin/request_view.mli`**

```ocaml
val render_request : Freight.Ast.request -> Freight.Executor.curl_invocation -> string list
val render_parse_error : Freight.Ast.parse_error -> string list
val render_message : title:string -> body:string list -> string list
```

- [ ] **Step 3: Verify request_view.ml has no vcaml/async opens**

Read `bin/request_view.ml`. If the only opens are `Core` or standard OCaml modules, leave the implementation unchanged. If it has `open Vcaml` or `open Async`, remove those lines.

- [ ] **Step 4: Commit**

```bash
jj describe -m "refactor(request_view): verify no vcaml dependency"
jj new
```

---

### Task 6: `Handlers` module

**Files:**

- Replace: `bin/handlers.mli`
- Replace: `bin/handlers.ml`

Same four handlers as before. Replace VCaml client with `Rpc.t`. Replace VCaml buffer/nvim API calls with `Rpc.call`. Replace `Deferred.Or_error.t` returns with plain `Deferred.t` (errors go to the `freight://error` scratch buffer, not propagated).

Neovim API used by handlers:
- `nvim_get_current_buf` → Int handle
- `nvim_buf_get_lines handle 0 -1 false` → Array of Strings
- `nvim_buf_get_name handle` → String path

- [ ] **Step 1: Replace `bin/handlers.mli`**

```ocaml
val freight_open    : rpc:Rpc.t -> State.t -> unit Async.Deferred.t
val freight_env     : rpc:Rpc.t -> State.t -> string option -> unit Async.Deferred.t
val freight_inspect : rpc:Rpc.t -> State.t -> unit Async.Deferred.t
val freight_run     : rpc:Rpc.t -> State.t -> unit Async.Deferred.t
```

- [ ] **Step 2: Replace `bin/handlers.ml`**

```ocaml
open Core
open Async

let nvim_call rpc method_ params =
  match%map Rpc.call rpc method_ params with
  | Ok result -> result
  | Error e -> failwithf "nvim %s: %s" method_ e ()

let show_error ~rpc message =
  Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
    (Request_view.render_message ~title:"Error" ~body:[message])

let get_current_buf_lines rpc =
  let%bind buf = nvim_call rpc "nvim_get_current_buf" [] in
  let handle = match buf with Msgpack.Int n -> n | _ -> failwith "expected buf handle" in
  let%bind lines_msg = nvim_call rpc "nvim_buf_get_lines"
    [ Msgpack.Int handle; Msgpack.Int 0; Msgpack.Int (-1); Msgpack.Bool false ]
  in
  let lines = match lines_msg with
    | Msgpack.Array xs -> List.filter_map xs ~f:(function Msgpack.String s -> Some s | _ -> None)
    | _ -> []
  in
  return (handle, lines)

let get_buf_path rpc handle =
  match%map nvim_call rpc "nvim_buf_get_name" [ Msgpack.Int handle ] with
  | Msgpack.String s when not (String.is_empty s) -> Some (Filename.dirname s)
  | _ -> None

let freight_open ~rpc _state =
  Scratch.show ~rpc ~name:"freight://request" ~filetype:"http"
    [ "# @name my_request"; "GET https://example.com"; "" ]

let freight_env ~rpc state arg =
  let env_name = match arg with
    | Some s when not (String.is_empty s) -> Some s
    | _ -> None
  in
  State.set_active_env state env_name;
  let%bind buf = nvim_call rpc "nvim_get_current_buf" [] in
  let handle = match buf with Msgpack.Int n -> n | _ -> failwith "expected buf handle" in
  let%bind dir_opt = get_buf_path rpc handle in
  (match dir_opt with
   | Some dir ->
     state.env <- Freight.Env.load ~dir ~active_env:env_name
   | None -> ());
  let label = match env_name with Some n -> n | None -> "(none)" in
  Scratch.show ~rpc ~name:"freight://info" ~filetype:"text"
    (Request_view.render_message ~title:"Env" ~body:[ Printf.sprintf "Active env: %s" label ])

let freight_inspect ~rpc _state =
  Scratch.show ~rpc ~name:"freight://info" ~filetype:"text"
    (Request_view.render_message ~title:"Inspect"
       ~body:[ "No freight_curl_cmd metadata on current buffer." ])

let freight_run ~rpc state =
  let%bind (handle, lines) = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match Freight.Parser.parse_string source with
  | Error err ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      (Request_view.render_parse_error err)
  | Ok file ->
    match Freight.Parser.request_at_cursor file.requests 0 with
    | None ->
      show_error ~rpc "No requests found in buffer."
    | Some request ->
      let%bind dir_opt = get_buf_path rpc handle in
      let env = match dir_opt with
        | Some dir -> Freight.Env.load ~dir ~active_env:state.active_env
        | None -> state.env
      in
      let request = { request with
        url = Freight.Env.substitute env request.url;
        headers = List.map request.headers ~f:(fun (k, v) -> (k, Freight.Env.substitute env v));
      } in
      let invocation = Freight.Executor.to_curl request in
      Scratch.show ~rpc ~name:"freight://inspect" ~filetype:"text"
        (Request_view.render_request request invocation)
```

- [ ] **Step 3: Commit**

```bash
jj describe -m "refactor(handlers): use raw rpc instead of vcaml"
jj new
```

---

### Task 7: `Main` entry point

**Files:**

- Replace: `bin/main.ml`

The entry point must:
1. Create the `Rpc.t`
2. Read the first notification from Neovim — this is `nvim_get_api_info` with params `[channel_id, api_info]`; extract `channel_id`
3. Register the four commands using `nvim_command` with the channel id
4. Run the dispatch loop: read messages, dispatch to handlers, reply

- [ ] **Step 1: Replace `bin/main.ml`**

```ocaml
open Core
open Async

let register_commands rpc channel =
  let cmd name nargs rpc_method =
    let nargs_str = match nargs with
      | `None -> ""
      | `Optional -> " -nargs=?"
    in
    let call_str = match nargs with
      | `None -> Printf.sprintf "call rpcrequest(%d, '%s')" channel rpc_method
      | `Optional -> Printf.sprintf "call rpcrequest(%d, '%s', <q-args>)" channel rpc_method
    in
    Rpc.call rpc "nvim_command"
      [ Msgpack.String (Printf.sprintf "command!%s %s %s" nargs_str name call_str) ]
    >>| ignore
  in
  let%bind () = cmd "FreightOpen"    `None     "FreightOpen"    in
  let%bind () = cmd "FreightRun"     `None     "FreightRun"     in
  let%bind () = cmd "FreightEnv"     `Optional "FreightEnv"     in
  let%bind () = cmd "FreightInspect" `None     "FreightInspect" in
  return ()

let dispatch rpc state method_ params =
  match method_ with
  | "FreightOpen" ->
    let%map () = Handlers.freight_open ~rpc state in
    Msgpack.Nil
  | "FreightRun" ->
    let%map () = Handlers.freight_run ~rpc state in
    Msgpack.Nil
  | "FreightEnv" ->
    let arg = match params with
      | [ Msgpack.String s ] when not (String.is_empty s) -> Some s
      | _ -> None
    in
    let%map () = Handlers.freight_env ~rpc state arg in
    Msgpack.Nil
  | "FreightInspect" ->
    let%map () = Handlers.freight_inspect ~rpc state in
    Msgpack.Nil
  | _ ->
    return Msgpack.Nil

let rec loop rpc state =
  match%bind Rpc.read rpc with
  | Rpc.Request { msgid; method_; params } ->
    let%bind result = dispatch rpc state method_ params in
    Rpc.reply_ok rpc ~msgid result;
    loop rpc state
  | Rpc.Notification _ ->
    loop rpc state

let main () =
  let rpc = Rpc.create () in
  let state = State.create () in
  (* First message is nvim_get_api_info notification: [2, "nvim_get_api_info", [channel_id, info]] *)
  let%bind channel =
    match%map Rpc.read rpc with
    | Rpc.Notification { method_ = "nvim_get_api_info"; params = Msgpack.Int ch :: _ } ->
      ch
    | Rpc.Notification { params = Msgpack.Int ch :: _ } ->
      ch
    | _ -> failwith "unexpected first message from neovim"
  in
  let%bind () = register_commands rpc channel in
  loop rpc state

let () =
  Command_unix.run
    (Command.async ~summary:"freight.ml neovim plugin"
       (Command.Param.return main))
```

- [ ] **Step 2: Build**

Run:

```bash
dune build 2>&1
```

Expected: clean build.

- [ ] **Step 3: Run the test suite to confirm lib/ still passes**

Run:

```bash
dune runtest
```

Expected: 28 tests pass (same as before).

- [ ] **Step 4: Commit**

```bash
jj describe -m "feat(bin): replace vcaml with raw msgpack-rpc"
jj new
```

---

### Task 8: Smoke test in Neovim

**Files:**

- No code changes — manual verification only.

- [ ] **Step 1: Build the binary**

Run:

```bash
dune build
```

Verify `_build/default/bin/main.exe` exists.

- [ ] **Step 2: Restart Neovim**

Restart Neovim. With `lazy = false` and `VimEnter` autocmd in `plugin/freight.vim`, the process should start automatically.

- [ ] **Step 3: Verify commands registered**

Run `:FreightOpen` in Neovim.

Expected: a `freight://request` buffer opens with `filetype=http`.

- [ ] **Step 4: Run a request**

In the request buffer, enter:

```http
# @name get_example
GET https://httpbin.org/get

```

Run `:FreightRun`.

Expected: `freight://inspect` buffer opens showing method, URL, and curl argv.

- [ ] **Step 5: Test parse error**

Replace buffer contents with `NOT A REQUEST` and run `:FreightRun`.

Expected: `freight://error` buffer opens with parse details.

- [ ] **Step 6: Test env**

Run `:FreightEnv dev`.

Expected: `freight://info` buffer shows `Active env: dev`.

- [ ] **Step 7: Commit**

```bash
jj describe -m "chore: verify raw msgpack-rpc smoke test passes"
jj new
```

---

## Self-review

**Spec coverage:**
- ✅ Raw msgpack-rpc transport replacing VCaml
- ✅ Channel id extracted from `nvim_get_api_info` startup notification
- ✅ Four commands registered via `nvim_command`
- ✅ `FreightOpen`, `FreightRun`, `FreightEnv`, `FreightInspect` handlers
- ✅ Scratch buffer helper using raw RPC calls
- ✅ `lib/` unchanged
- ✅ `bin/dune` removes vcaml/ppx_jane, adds msgpack
- ✅ Single-threaded Async event loop
- ✅ Errors go to `freight://error` scratch buffer

**Placeholder scan:** No TBDs or vague steps — all code blocks are concrete.

**Type consistency:**
- `Rpc.t` passed as `~rpc` throughout handlers and scratch
- `Msgpack.t` used consistently (not `Msgpack.obj` or other aliases)
- `State.t` fields `active_env` and `env` match both state.mli and handlers usage
- `Scratch.show` signature matches all call sites in handlers
