let show_error message =
  ignore
    (Freight_effect.show_scratch
       ~name:"freight://error"
       ~filetype:"freight"
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

let set_buf_keymaps buf =
  Freight_effect.set_keymap buf ~key:"q" ~command:":close<CR>";
  Freight_effect.set_keymap buf ~key:"g?" ~command:":FreightHelp<CR>"

let set_current_window_chrome () =
  ignore
    (Freight_effect.nvim_call "nvim_command"
       [ Msgpck.String "setlocal nonumber norelativenumber signcolumn=no foldcolumn=0" ]);
  let set name value =
    ignore
      (Freight_effect.nvim_call "nvim_set_option_value"
         [ Msgpck.String name
         ; value
         ; Msgpck.Map [ (Msgpck.String "scope", Msgpck.String "local") ]
         ])
  in
  set "number" (Msgpck.Bool false);
  set "relativenumber" (Msgpck.Bool false);
  set "signcolumn" (Msgpck.String "no");
  set "foldcolumn" (Msgpck.String "0")

let freight_open _state =
  let buf =
    Freight_effect.show_scratch
      ~name:"freight://request"
      ~filetype:"http"
      ~lines:[ "# @name my_request"; "GET https://example.com"; "" ]
  in
  set_buf_keymaps buf

let load_active_env state active_env =
  State.set_active_env state active_env;
  let buf = Freight_effect.current_buffer () in
  let dir_opt = Freight_effect.buffer_dir buf in
  match dir_opt with
  | Some dir -> state.State.env <- Freight_effect.load_env ~dir ~active_env
  | None -> ()

let describe_active_env = function
  | None | Some "" -> ".env"
  | Some name -> ".env." ^ name

let freight_env_apply state active_env =
  load_active_env state active_env;
  Freight_effect.notify Info
    ("Freight env: " ^ describe_active_env active_env)

let freight_env state arg =
  match arg with
  | None | Some "" ->
    ignore
      (Freight_effect.nvim_call "nvim_command"
         [ Msgpck.String "lua require('freight').select_env()" ])
  | Some env_name -> freight_env_apply state (Some env_name)

let freight_inspect state =
  let buf, source, cursor_line = current_source () in
  match resolve_request state source cursor_line buf with
  | Error (`Parse err) ->
    let scratch_buf =
      Freight_effect.show_scratch
        ~name:"freight://error"
        ~filetype:"freight"
        ~lines:(Request_view.render_parse_error err)
    in
    set_buf_keymaps scratch_buf
  | Error `No_request ->
    show_error "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    let scratch_buf =
      Freight_effect.show_scratch
        ~name:"freight://inspect"
        ~filetype:"freight"
        ~lines:(Request_view.render_request request invocation)
    in
    set_buf_keymaps scratch_buf

let freight_help _state =
  Freight_effect.show_float ~title:"Freight Help"
    ~lines:
      [ "  Keymaps"
      ; ""
      ; "  q        Close window"
      ; "  g?       Show this help"
      ; ""
      ; "  (response buffer)"
      ; "  B        Body view"
      ; "  H        Headers view"
      ; "  A        All view"
      ; "  V        Verbose view"
      ]

let freight_run state =
  let buf, source, cursor_line = current_source () in
  match resolve_request state source cursor_line buf with
  | Error (`Parse err) ->
    let scratch_buf =
      Freight_effect.show_scratch
        ~name:"freight://error"
        ~filetype:"freight"
        ~lines:(Request_view.render_parse_error err)
    in
    set_buf_keymaps scratch_buf
  | Error `No_request ->
    show_error "No requests found in buffer."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    let name = Freight.Buffer.buffer_name request in
    let loading_buf =
      Freight_effect.show_scratch
        ~name
        ~filetype:"freight"
        ~lines:[ "Running request…" ]
    in
    set_buf_keymaps loading_buf;
    Freight_effect.fork "FreightRun" @@ fun () ->
      let run_result = Freight_effect.run_curl invocation in
      let verbose_result = Freight_effect.run_curl_verbose invocation in
      (match run_result, verbose_result with
       | Error msg, _ | _, Error msg ->
         Freight_effect.update_scratch loading_buf
           ~name ~filetype:"freight"
           ~lines:[ "Request failed"; msg ]
       | Ok raw, Ok verbose_raw ->
         (match Freight.Response.parse_curl_output raw request with
          | Error msg ->
            Freight_effect.update_scratch loading_buf
              ~name ~filetype:"freight"
              ~lines:[ "Response parse failed"; msg ]
          | Ok response ->
            let filetype =
              Freight.Buffer.filetype_of_content_type
                (Freight.Response.detect_content_type response)
            in
            let req_name = Option.value request.Freight.Ast.name ~default:"" in
            state.State.env <-
              Freight.Chaining.inject ~name:req_name response state.State.env;
            state.State.last_response <- Some response;
            state.State.response_buf <- Some loading_buf;
            state.State.response_buf_name <- Some name;
            state.State.verbose_output <- Some verbose_raw;
            State.push_history state request response verbose_raw;
            Freight_effect.update_scratch loading_buf
              ~name ~filetype
              ~lines:(Freight.Response.render response);
            Freight_effect.set_keymap loading_buf
              ~key:"B" ~command:":FreightView Body<CR>";
            Freight_effect.set_keymap loading_buf
              ~key:"H" ~command:":FreightView Headers<CR>";
            Freight_effect.set_keymap loading_buf
              ~key:"A" ~command:":FreightView All<CR>";
            Freight_effect.set_keymap loading_buf
              ~key:"V" ~command:":FreightView Verbose<CR>"))

let freight_view state view_name =
  match state.State.last_response with
  | None ->
    show_error "No response to view."
  | Some response ->
    (match state.State.response_buf, state.State.response_buf_name with
     | None, _ | _, None ->
       show_error "No response buffer."
     | Some buf, Some buf_name ->
       let lines, filetype =
         match view_name with
         | "Body" ->
           let ct = Freight.Response.detect_content_type response in
           let ft = Freight.Buffer.filetype_of_content_type ct in
           (Freight.Response.render_body response, ft)
         | "Headers" ->
           (Freight.Response.render_headers response, "freight")
         | "Verbose" ->
           let lines =
             match state.State.verbose_output with
             | None -> [ "No verbose output available." ]
             | Some raw -> Freight.Response.render_verbose raw
           in
           (lines, "freight")
         | _ ->
           let ct = Freight.Response.detect_content_type response in
           let ft = Freight.Buffer.filetype_of_content_type ct in
           (Freight.Response.render_all response, ft)
       in
       Freight_effect.update_scratch buf ~name:buf_name ~filetype ~lines)

let freight_history state =
  let lines = Request_view.render_history state.State.history in
  let buf =
    Freight_effect.show_scratch
      ~name:"freight://history"
      ~filetype:"freight"
      ~lines
  in
  set_buf_keymaps buf;
  Freight_effect.set_keymap buf ~key:"<CR>"
    ~command:":<C-u>execute 'FreightViewHistory ' . line('.')<CR>"

let freight_view_history state line_number =
  let index = line_number - 1 in
  Freight_effect.notify Info
    (Printf.sprintf "FreightViewHistory: line=%d history_len=%d"
       line_number (List.length state.State.history));
  match List.nth_opt state.State.history index with
  | None -> show_error "No history entry at that line."
  | Some entry ->
    let request = entry.State.request in
    let response = entry.State.response in
    let name = Freight.Buffer.buffer_name request in
    let filetype =
      Freight.Buffer.filetype_of_content_type
        (Freight.Response.detect_content_type response)
    in
    state.State.last_response <- Some response;
    state.State.verbose_output <- Some entry.State.verbose;
    (match state.State.response_buf, state.State.response_buf_name with
     | Some buf, Some buf_name ->
       Freight_effect.update_scratch buf ~name:buf_name ~filetype
         ~lines:(Freight.Response.render response);
       ignore (Freight_effect.nvim_call "nvim_command"
         [ Msgpck.String (Printf.sprintf "vsplit | buffer %d" buf) ]);
       set_current_window_chrome ()
     | _ ->
       let buf =
         Freight_effect.show_scratch ~name ~filetype
           ~lines:(Freight.Response.render response)
       in
       set_buf_keymaps buf;
       Freight_effect.set_keymap buf ~key:"B" ~command:":FreightView Body<CR>";
       Freight_effect.set_keymap buf ~key:"H" ~command:":FreightView Headers<CR>";
       Freight_effect.set_keymap buf ~key:"A" ~command:":FreightView All<CR>";
       Freight_effect.set_keymap buf ~key:"V" ~command:":FreightView Verbose<CR>";
       state.State.response_buf <- Some buf;
       state.State.response_buf_name <- Some name)
