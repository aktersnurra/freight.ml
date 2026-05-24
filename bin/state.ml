type t = {
  mutable active_env : string option;
  mutable env : Freight.Env.t;
}

let create () = { active_env = None; env = Freight.Env.empty }

let set_active_env state env_name =
  state.active_env <- env_name
