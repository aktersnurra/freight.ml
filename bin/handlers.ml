open Core
open Async
open Vcaml

let freight_open ~client _state =
  let open Deferred.Or_error.Let_syntax in
  Scratch.show
    ~client
    ~name:"freight://request"
    ~filetype:"http"
    ~lines:[ "GET https://example.com"; "" ]
;;

let freight_env ~client state active_env =
  let open Deferred.Or_error.Let_syntax in
  State.set_active_env state active_env;
  let%bind buf = Nvim.get_current_buf [%here] client in
  let%bind buf_name =
    Buffer.get_name [%here] client (Buffer.Or_current.Id buf)
  in
  let dir_opt =
    if String.equal buf_name "" then None
    else
      let d = Filename.dirname buf_name in
      if String.equal d "" then None else Some d
  in
  let lines =
    match dir_opt with
    | None ->
      state.State.active_env <- active_env;
      Request_view.render_message
        ~title:"Freight Env"
        ~body:
          [ (match active_env with
             | None -> "Active env: (none)"
             | Some e -> Printf.sprintf "Active env: %s" e)
          ; "Env files not loaded: no file in current buffer."
          ]
    | Some dir ->
      let env = Freight.Env.load ~dir ~active_env in
      state.State.env <- env;
      Request_view.render_message
        ~title:"Freight Env"
        ~body:
          [ (match active_env with
             | None -> "Active env: (none)"
             | Some e -> Printf.sprintf "Active env: %s" e)
          ; Printf.sprintf "Loaded env from: %s" dir
          ]
  in
  Scratch.show ~client ~name:"freight://inspect" ~filetype:"" ~lines
;;

let freight_inspect ~client _state =
  let open Deferred.Or_error.Let_syntax in
  let lines =
    Request_view.render_message
      ~title:"Freight Inspect"
      ~body:[ "No freight_curl_cmd metadata on current buffer yet." ]
  in
  Scratch.show ~client ~name:"freight://inspect" ~filetype:"" ~lines
;;

let freight_run ~client state =
  let open Deferred.Or_error.Let_syntax in
  let%bind result =
    Buffer.get_lines
      [%here]
      client
      Buffer.Or_current.Current
      ~start:0
      ~end_:(-1)
      ~strict_indexing:false
  in
  let lines = Buffer.With_changedtick.value result in
  let content = String.concat ~sep:"\n" (List.map lines ~f:(fun s -> (s :> string))) in
  match Freight.Parser.parse_string content with
  | Error err ->
    Scratch.show
      ~client
      ~name:"freight://error"
      ~filetype:""
      ~lines:(Request_view.render_parse_error err)
  | Ok file ->
    let%bind win = Nvim.get_current_win [%here] client in
    let%bind pos = Window.get_cursor [%here] client (Window.Or_current.Id win) in
    let cursor_line = pos.row in
    (match Freight.Parser.request_at_cursor file.requests cursor_line with
     | None ->
       Scratch.show
         ~client
         ~name:"freight://error"
         ~filetype:""
         ~lines:
           (Request_view.render_message
              ~title:"Freight Error"
              ~body:[ "No request at cursor" ])
     | Some req ->
       let url = Freight.Env.substitute state.State.env req.url in
       let headers =
         List.map req.headers ~f:(fun (k, v) ->
           Freight.Env.substitute state.State.env k,
           Freight.Env.substitute state.State.env v)
       in
       let body =
         match req.body with
         | Freight.Ast.Body_inline s ->
           Freight.Ast.Body_inline (Freight.Env.substitute state.State.env s)
         | Freight.Ast.Body_file f ->
           Freight.Ast.Body_file (Freight.Env.substitute state.State.env f)
         | Freight.Ast.Body_none -> Freight.Ast.Body_none
       in
       let req' = { req with url; headers; body } in
       let inv = Freight.Executor.to_curl req' in
       Scratch.show
         ~client
         ~name:"freight://inspect"
         ~filetype:""
         ~lines:(Request_view.render_request req' inv))
;;
