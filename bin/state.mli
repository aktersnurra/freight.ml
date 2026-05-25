type history_entry = {
  request : Freight.Ast.request;
  response : Freight.Ast.response;
  verbose : string;
}

type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf : Freight_effect.buffer_id option;
  mutable response_buf_name : string option;
  mutable verbose_output : string option;
  mutable history : history_entry list;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
val push_history : t -> Freight.Ast.request -> Freight.Ast.response -> string -> unit
