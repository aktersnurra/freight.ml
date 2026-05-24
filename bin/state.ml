type t = {
  mutable active_env : string option;
  mutable response_history : string list;
  mutable env : Freight.Env.t;
}

let create () =
  { active_env = None; response_history = []; env = Freight.Env.empty }

let set_active_env t active_env =
  t.active_env <- active_env

let remember_buffer t name =
  t.response_history <- name :: t.response_history
