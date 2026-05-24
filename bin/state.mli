type t = {
  mutable active_env : string option;
  mutable response_history : string list;
  mutable env : Freight.Env.t;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
val remember_buffer : t -> string -> unit
