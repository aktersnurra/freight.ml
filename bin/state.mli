type history_entry = {
  request : Freight.Ast.request;
  response : Freight.Ast.response;
  verbose : string;
}

type run_all_success = {
  line_number : int;
  source_buffer : Freight_effect.buffer_id;
  source_window : int;
  source_line : int;
  request : Freight.Ast.request;
  response : Freight.Ast.response;
  verbose : string;
}

type run_all_failure = {
  line_number : int;
  source_buffer : Freight_effect.buffer_id;
  source_window : int;
  source_line : int;
  request : Freight.Ast.request;
  message : string;
  response : Freight.Ast.response option;
}

type run_all_result =
  | Run_all_success of run_all_success
  | Run_all_failure of run_all_failure

type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable responses : Freight.Response_store.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf : Freight_effect.buffer_id option;
  mutable response_buf_name : string option;
  mutable verbose_output : string option;
  mutable history : history_entry list;
  mutable run_all_results : run_all_result list;
  mutable run_all_summary : string list;
}

val create : unit -> t
val set_active_env : t -> string option -> unit
val push_history : t -> Freight.Ast.request -> Freight.Ast.response -> string -> unit
