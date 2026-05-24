type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf_name : string option;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
