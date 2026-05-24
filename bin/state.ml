type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
  mutable last_response : Freight.Ast.response option;
  mutable response_buf_name : string option;
}

let create () = {
  active_env = None;
  env = Freight.Env.empty;
  last_response = None;
  response_buf_name = None;
}

let set_active_env state env_name =
  state.active_env <- env_name
