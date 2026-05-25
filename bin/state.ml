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

let history_cap = 50

let create () = {
  active_env = None;
  env = Freight.Env.empty;
  last_response = None;
  response_buf = None;
  response_buf_name = None;
  verbose_output = None;
  history = [];
}

let set_active_env state env_name =
  state.active_env <- env_name

let push_history state request response verbose =
  let entry = { request; response; verbose } in
  let entries = entry :: state.history in
  state.history <-
    if List.length entries > history_cap then
      List.filteri (fun i _ -> i < history_cap) entries
    else
      entries
