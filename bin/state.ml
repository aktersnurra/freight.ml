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
  cookie_jars : (Freight_effect.buffer_id, string) Hashtbl.t;
      (** Per-buffer curl cookie jar path, so Set-Cookie sessions chain across
          requests in the same .http buffer for this process. *)
}

let history_cap = 50

let create () = {
  active_env = None;
  env = Freight.Env.empty;
  responses = Freight.Response_store.empty;
  last_response = None;
  response_buf = None;
  response_buf_name = None;
  verbose_output = None;
  history = [];
  run_all_results = [];
  run_all_summary = [];
  cookie_jars = Hashtbl.create 8;
}

(* The cookie jar path for [buf], created (as a session-unique temp path) on
   first use and reused thereafter. *)
let cookie_jar state buf =
  match Hashtbl.find_opt state.cookie_jars buf with
  | Some path -> path
  | None ->
    let path =
      Filename.concat (Filename.get_temp_dir_name ())
        (Printf.sprintf "freight-cookies-%d-%d.txt" (Unix.getpid ())
           (Freight_effect.Buffer_id.to_int buf))
    in
    Hashtbl.replace state.cookie_jars buf path;
    path

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
