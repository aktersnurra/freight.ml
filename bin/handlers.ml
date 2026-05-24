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
  let%bind lines_msg =
    nvim_call rpc "nvim_buf_get_lines"
      [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false ]
  in
  let source =
    match lines_msg with
    | Msgpck.List xs ->
      List.filter_map xs ~f:(function Msgpck.String s -> Some s | _ -> None)
      |> String.concat ~sep:"\n"
    | _ -> ""
  in
  let pairs = Freight.Env.to_list state.State.env in
  let unresolved = Freight.Env.unresolved state.State.env source in
  Scratch.show ~rpc ~name:"freight://env" ~filetype:"text"
    ~lines:(Request_view.render_env ~active_env:env_name ~pairs ~unresolved)

let resolve_request ~rpc state source cursor_line buf =
  match Freight.Parser.request_at_cursor source cursor_line with
  | None ->
    (match Freight.Parser.parse_string source with
     | Error err -> return (Error (`Parse err))
     | Ok _ -> return (Error `No_request))
  | Some request ->
    let%bind dir_opt = get_buf_path rpc buf in
    let env =
      match dir_opt with
      | Some dir -> Freight.Env.load ~dir ~active_env:state.State.active_env
      | None -> state.State.env
    in
    let sub = Freight.Env.substitute env in
    let body = match request.Freight.Ast.body with
      | Freight.Ast.Body_inline s -> Freight.Ast.Body_inline (sub s)
      | other -> other
    in
    let request =
      { request with
        Freight.Ast.url = sub request.Freight.Ast.url
      ; headers = List.map request.Freight.Ast.headers ~f:(fun (k, v) -> (k, sub v))
      ; body
      }
    in
    return (Ok (Freight.Ast.apply_host_header request))

let freight_inspect ~rpc state =
  let%bind buf, lines, cursor_line = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match%bind resolve_request ~rpc state source cursor_line buf with
  | Error (`Parse err) ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      ~lines:(Request_view.render_parse_error err)
  | Error `No_request -> show_error ~rpc "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    Scratch.show ~rpc ~name:"freight://inspect" ~filetype:"text"
      ~lines:(Request_view.render_request request invocation)

let freight_run ~rpc state =
  let%bind buf, lines, cursor_line = get_current_buf_lines rpc in
  let source = String.concat lines ~sep:"\n" in
  match%bind resolve_request ~rpc state source cursor_line buf with
  | Error (`Parse err) ->
    Scratch.show ~rpc ~name:"freight://error" ~filetype:"text"
      ~lines:(Request_view.render_parse_error err)
  | Error `No_request -> show_error ~rpc "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    let name = Freight.Buffer.buffer_name request in
    let%map loading_buf = Scratch.show_loading ~rpc ~name in
    don't_wait_for begin
      match%bind
        Monitor.try_with (fun () ->
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
                ~lines:(Freight.Response.render response))
      with
      | Ok () -> return ()
      | Error exn ->
        (match%map
           Monitor.try_with (fun () ->
             Scratch.update ~rpc loading_buf ~filetype:"text"
               ~lines:[ "Internal error: " ^ Exn.to_string exn ])
         with
         | Ok () | Error _ -> ())
    end
