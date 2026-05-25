type buffer_id = int

module Buffer_id = struct
  type t = buffer_id

  let of_int n = n
  let to_int t = t

  let to_msgpack t = Msgpck.Int t
end

module Cursor = struct
  type t =
    { row : int
    ; col : int
    }
end

type notify_level =
  | Info
  | Warning
  | Error

type scratch_view =
  { name : string
  ; filetype : string
  ; lines : string list
  }

type _ Effect.t +=
  | Current_buffer : buffer_id Effect.t
  | Buffer_lines : buffer_id -> string list Effect.t
  | Buffer_dir : buffer_id -> string option Effect.t
  | Cursor : Cursor.t Effect.t
  | Show_scratch : scratch_view -> buffer_id Effect.t
  | Update_scratch : buffer_id * scratch_view -> unit Effect.t
  | Set_keymap : buffer_id * string * string -> unit Effect.t
  | Run_curl : Freight.Executor.invocation -> (string, string) result Effect.t
  | Notify : notify_level * string -> unit Effect.t
  | Fork : string * (unit -> unit) -> unit Effect.t
  | Load_env : { dir : string; active_env : string option } -> Freight.Env.t Effect.t
  | Nvim_call : string * Msgpck.t list -> Msgpck.t Effect.t

let current_buffer () = Effect.perform Current_buffer
let buffer_lines buf = Effect.perform (Buffer_lines buf)
let buffer_dir buf = Effect.perform (Buffer_dir buf)
let cursor () = Effect.perform Cursor

let show_scratch ~name ~filetype ~lines =
  Effect.perform (Show_scratch { name; filetype; lines })

let update_scratch buf ~name ~filetype ~lines =
  Effect.perform (Update_scratch (buf, { name; filetype; lines }))

let set_keymap buf ~key ~command =
  Effect.perform (Set_keymap (buf, key, command))

let load_env ~dir ~active_env = Effect.perform (Load_env { dir; active_env })
let run_curl invocation = Effect.perform (Run_curl invocation)
let notify level msg = Effect.perform (Notify (level, msg))
let fork label f = Effect.perform (Fork (label, f))
let nvim_call method_ params = Effect.perform (Nvim_call (method_, params))
