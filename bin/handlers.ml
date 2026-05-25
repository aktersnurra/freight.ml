let show_error message =
  ignore
    (Freight_effect.show_scratch
       ~name:"freight://error"
       ~filetype:"text"
       ~lines:(Request_view.render_message ~title:"Error" ~body:[ message ]))

let current_source () =
  let buf = Freight_effect.current_buffer () in
  let lines = Freight_effect.buffer_lines buf in
  let cursor = Freight_effect.cursor () in
  (buf, String.concat "\n" lines, cursor.Freight_effect.Cursor.row)

let resolve_env state buf =
  match Freight_effect.buffer_dir buf with
  | Some dir -> Freight_effect.load_env ~dir ~active_env:state.State.active_env
  | None -> state.State.env

let resolve_request state source cursor_line buf =
  let env = resolve_env state buf in
  Freight.Resolve.at_cursor ~source ~cursor_line ~env

let freight_open _state =
  ignore
    (Freight_effect.show_scratch
       ~name:"freight://request"
       ~filetype:"http"
       ~lines:[ "# @name my_request"; "GET https://example.com"; "" ])

let freight_env state arg =
  let env_name =
    match arg with
    | Some s when s <> "" -> Some s
    | _ -> None
  in
  State.set_active_env state env_name;
  let buf = Freight_effect.current_buffer () in
  let dir_opt = Freight_effect.buffer_dir buf in
  (match dir_opt with
   | Some dir -> state.State.env <- Freight_effect.load_env ~dir ~active_env:env_name
   | None -> ());
  let lines = Freight_effect.buffer_lines buf in
  let source = String.concat "\n" lines in
  let pairs = Freight.Env.to_list state.State.env in
  let unresolved = Freight.Env.unresolved state.State.env source in
  ignore
    (Freight_effect.show_scratch
       ~name:"freight://env"
       ~filetype:"text"
       ~lines:(Request_view.render_env ~active_env:env_name ~pairs ~unresolved))

let freight_inspect state =
  let buf, source, cursor_line = current_source () in
  match resolve_request state source cursor_line buf with
  | Error (`Parse err) ->
    ignore
      (Freight_effect.show_scratch
         ~name:"freight://error"
         ~filetype:"text"
         ~lines:(Request_view.render_parse_error err))
  | Error `No_request ->
    show_error "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    ignore
      (Freight_effect.show_scratch
         ~name:"freight://inspect"
         ~filetype:"text"
         ~lines:(Request_view.render_request request invocation))

let freight_run state =
  let buf, source, cursor_line = current_source () in
  match resolve_request state source cursor_line buf with
  | Error (`Parse err) ->
    ignore
      (Freight_effect.show_scratch
         ~name:"freight://error"
         ~filetype:"text"
         ~lines:(Request_view.render_parse_error err))
  | Error `No_request ->
    show_error "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    let name = Freight.Buffer.buffer_name request in
    let loading_buf =
      Freight_effect.show_scratch
        ~name
        ~filetype:"text"
        ~lines:[ "Loading\xe2\x80\xa6" ]
    in
    Freight_effect.fork "FreightRun" @@ fun () ->
      match Freight_effect.run_curl invocation with
      | Error msg ->
        Freight_effect.update_scratch loading_buf
          ~name ~filetype:"text"
          ~lines:[ "Error: " ^ msg ]
      | Ok raw ->
        (match Freight.Response.parse_curl_output raw request with
         | Error msg ->
           Freight_effect.update_scratch loading_buf
             ~name ~filetype:"text"
             ~lines:[ "Parse error: " ^ msg ]
         | Ok response ->
           let filetype =
             Freight.Buffer.filetype_of_content_type
               (Freight.Response.detect_content_type response)
           in
           let req_name = Option.value request.Freight.Ast.name ~default:"" in
           state.State.env <-
             Freight.Chaining.inject ~name:req_name response state.State.env;
           state.State.last_response <- Some response;
           state.State.response_buf_name <- Some name;
           Freight_effect.update_scratch loading_buf
             ~name ~filetype
             ~lines:(Freight.Response.render response);
           Freight_effect.set_keymap loading_buf
             ~key:"B" ~command:":FreightView Body<CR>";
           Freight_effect.set_keymap loading_buf
             ~key:"H" ~command:":FreightView Headers<CR>";
           Freight_effect.set_keymap loading_buf
             ~key:"A" ~command:":FreightView All<CR>")

let freight_view state view_name =
  match state.State.last_response with
  | None ->
    show_error "No response to view."
  | Some response ->
    (match state.State.response_buf_name with
     | None ->
       show_error "No response buffer."
     | Some buf_name ->
       let lines, filetype =
         match view_name with
         | "Body" ->
           let ct = Freight.Response.detect_content_type response in
           let ft = Freight.Buffer.filetype_of_content_type ct in
           (Freight.Response.render_body response, ft)
         | "Headers" ->
           (Freight.Response.render_headers response, "text")
         | _ ->
           let ct = Freight.Response.detect_content_type response in
           let ft = Freight.Buffer.filetype_of_content_type ct in
           (Freight.Response.render_all response, ft)
       in
       let buf_msg =
         Freight_effect.nvim_call "nvim_eval"
           [ Msgpck.String (Printf.sprintf "bufnr('%s')" buf_name) ]
       in
       match buf_msg with
       | Msgpck.Int n when n >= 0 ->
         Freight_effect.update_scratch n
           ~name:buf_name ~filetype ~lines
       | _ ->
         show_error "Response buffer not found.")
