type buffer_id = int

module Buffer_id : sig
  type t = buffer_id
  val of_int : int -> t
  val to_int : t -> int
  val to_msgpack : t -> Msgpck.t
end

module Cursor : sig
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
  | Run_curl_verbose : Freight.Executor.invocation -> (string, string) result Effect.t
  | Notify : notify_level * string -> unit Effect.t
  | Fork : string * (unit -> unit) -> unit Effect.t
  | Load_env : { dir : string; active_env : string option } -> Freight.Env.t Effect.t
  | Nvim_call : string * Msgpck.t list -> Msgpck.t Effect.t

val current_buffer : unit -> buffer_id
val buffer_lines : buffer_id -> string list
val buffer_dir : buffer_id -> string option
val cursor : unit -> Cursor.t
val show_scratch : name:string -> filetype:string -> lines:string list -> buffer_id
val update_scratch : buffer_id -> name:string -> filetype:string -> lines:string list -> unit
val set_keymap : buffer_id -> key:string -> command:string -> unit
val load_env : dir:string -> active_env:string option -> Freight.Env.t
val run_curl : Freight.Executor.invocation -> (string, string) result
val run_curl_verbose : Freight.Executor.invocation -> (string, string) result
val notify : notify_level -> string -> unit
val fork : string -> (unit -> unit) -> unit
val nvim_call : string -> Msgpck.t list -> Msgpck.t
