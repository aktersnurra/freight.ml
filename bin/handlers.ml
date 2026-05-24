open Core
open Async

let nvim_call rpc method_ params =
  match%map Nvim_rpc.call rpc method_ params with
  | Ok result -> result
  | Error e -> failwithf "nvim %s: %s" method_ e ()

let show_error ~rpc message =
  Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
    ~lines:(Request_view.render_message ~title:"Error" ~body:[ message ])

let get_current_buf_lines rpc =
  let%bind buf = nvim_call rpc "nvim_get_current_buf" [] in
  let%bind lines_msg =
    nvim_call rpc "nvim_buf_get_lines"
      [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false ]
  in
  let lines =
    match lines_msg with
    | Msgpck.List xs ->
      List.filter_map xs ~f:(function Msgpck.String s -> Some s | _ -> None)
    | _ -> []
  in
  (* nvim_win_get_cursor returns [row, col] (1-based row) *)
  let%bind cursor_msg = nvim_call rpc "nvim_win_get_cursor" [ Msgpck.Int 0 ] in
  let cursor_line = match cursor_msg with
    | Msgpck.List (Msgpck.Int row :: _) -> row - 1  (* convert to 0-based *)
    | _ -> 0
  in
  return (buf, lines, cursor_line)

let get_buf_path rpc buf =
  match%map nvim_call rpc "nvim_buf_get_name" [ buf ] with
  | Msgpck.String s when not (String.is_empty s) -> Some (Filename.dirname s)
  | _ -> None

let freight_open ~rpc _state =
  Scratch.show ~rpc ~name:"freight://request" ~filetype:"http"
    ~lines:[ "# @name my_request"; "GET https://example.com"; "" ]

let freight_env ~rpc state arg =
  let env_name =
    match arg with
    | Some s when not (String.is_empty s) -> Some s
    | _ -> None
  in
  State.set_active_env state env_name;
  let%bind buf = nvim_call rpc "nvim_get_current_buf" [] in
  let%bind dir_opt = get_buf_path rpc buf in
  (match dir_opt with
   | Some dir -> state.State.env <- Freight.Env.load ~dir ~active_env:env_name
   | None -> ());
  let label = match env_name with Some n -> n | None -> "(none)" in
  Scratch.show ~rpc ~name:"freight://info" ~filetype:"text"
    ~lines:(Request_view.render_message ~title:"Env"
       ~body:[ Printf.sprintf "Active env: %s" label ])

let freight_inspect ~rpc state =
  let%bind buf, lines, cursor_line = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match Freight.Parser.request_at_cursor source cursor_line with
  | None ->
    (match Freight.Parser.parse_string source with
     | Error err ->
       Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
         ~lines:(Request_view.render_parse_error err)
     | Ok _ -> show_error ~rpc "No requests found in buffer.")
  | Some request ->
    let%bind dir_opt = get_buf_path rpc buf in
    let env =
      match dir_opt with
      | Some dir -> Freight.Env.load ~dir ~active_env:state.State.active_env
      | None -> state.State.env
    in
    let request =
      { request with
        Freight.Ast.url = Freight.Env.substitute env request.Freight.Ast.url
      ; headers =
          List.map request.Freight.Ast.headers ~f:(fun (k, v) ->
            (k, Freight.Env.substitute env v))
      }
    in
    let invocation = Freight.Executor.to_curl request in
    Scratch.show ~rpc ~name:"freight://inspect" ~filetype:"text"
      ~lines:(Request_view.render_request request invocation)

let freight_run ~rpc state =
  let%bind buf, lines, cursor_line = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match Freight.Parser.request_at_cursor source cursor_line with
  | None ->
    (match Freight.Parser.parse_string source with
     | Error err ->
       Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
         ~lines:(Request_view.render_parse_error err)
     | Ok _ -> show_error ~rpc "No requests found in buffer.")
  | Some request ->
    let%bind dir_opt = get_buf_path rpc buf in
    let env =
      match dir_opt with
      | Some dir -> Freight.Env.load ~dir ~active_env:state.State.active_env
      | None -> state.State.env
    in
    let request =
      { request with
        Freight.Ast.url = Freight.Env.substitute env request.Freight.Ast.url
      ; headers =
          List.map request.Freight.Ast.headers ~f:(fun (k, v) ->
            (k, Freight.Env.substitute env v))
      }
    in
    let invocation = Freight.Executor.to_curl request in
    let name = Freight.Buffer.buffer_name request in
    let%map loading_buf = Scratch.show_loading ~rpc ~name in
    don't_wait_for begin
      match%bind Freight.Executor.run invocation with
      | Error msg ->
        Scratch.update ~rpc loading_buf ~filetype:"text"
          ~lines:[ "Error: " ^ msg ]
      | Ok raw ->
        match Freight.Response.parse_curl_output raw request with
        | Error msg ->
          Scratch.update ~rpc loading_buf ~filetype:"text"
            ~lines:[ "Parse error: " ^ msg ]
        | Ok response ->
          let filetype =
            Freight.Buffer.filetype_of_content_type
              (Freight.Response.detect_content_type response)
          in
          let req_name = Option.value request.Freight.Ast.name ~default:"" in
          state.State.env <- Freight.Chaining.inject ~name:req_name response state.State.env;
          Scratch.update ~rpc loading_buf ~filetype
            ~lines:(Freight.Response.render response)
    end
