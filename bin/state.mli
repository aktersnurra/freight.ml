type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
