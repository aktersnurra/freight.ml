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
      [ "  Commands"
      ; ""
      ; "  :FreightRun           Run request under cursor"
      ; "  :FreightRunAll        Run every request in the buffer"
      ; "  :FreightHistory       Show recent request history"
      ; ""
      ; "  Keymaps"
      ; ""
      ; "  q                     Close window"
      ; "  g?                    Show this help"
      ; "  <CR>                  Open run-all/history entry"
      ; "  o                     Jump from run-all entry to source"
      ; ""
      ; "  (response buffer)"
      ; "  B                     Body view"
      ; "  H                     Headers view"
      ; "  A                     All view"
      ; "  V                     Verbose view"
      ]

let record_response state request response verbose_raw response_buf response_buf_name =
  let req_name = Option.value request.Freight.Ast.name ~default:"" in
  state.State.env <-
    Freight.Chaining.inject ~name:req_name response state.State.env;
  state.State.last_response <- Some response;
  state.State.response_buf <- Some response_buf;
  state.State.response_buf_name <- Some response_buf_name;
  state.State.verbose_output <- Some verbose_raw;
  State.push_history state request response verbose_raw

let set_response_keymaps buf =
  Freight_effect.set_keymap buf ~key:"B" ~command:":FreightView Body<CR>";
  Freight_effect.set_keymap buf ~key:"H" ~command:":FreightView Headers<CR>";
  Freight_effect.set_keymap buf ~key:"A" ~command:":FreightView All<CR>";
  Freight_effect.set_keymap buf ~key:"V" ~command:":FreightView Verbose<CR>"

let ext_to_int s =
  String.fold_left (fun acc c -> (acc lsl 8) lor Char.code c) 0 s

let decode_handle = function
  | Msgpck.Int id -> id
  | Msgpck.Ext (_, s) -> ext_to_int s
  | _ -> 0

let request_label request =
  Printf.sprintf "%s %s"
    (Freight.Ast.method_to_string request.Freight.Ast.method_)
    request.Freight.Ast.url

let render_run_all_results ?progress results =
  let successes, failures =
    List.partition_map
      (function
       | State.Run_all_success entry -> Left entry
       | State.Run_all_failure entry -> Right entry)
      results
  in
  let successes : State.run_all_success list = successes in
  let failures : State.run_all_failure list = failures in
  let success_count = List.length successes in
  let failure_count = List.length failures in
  let failure_lines =
    failures
    |> List.map (fun (entry : State.run_all_failure) ->
      Printf.sprintf "%d. %s — %s" entry.line_number
        (request_label entry.request) entry.message)
  in
  let success_lines =
    successes
    |> List.map (fun (entry : State.run_all_success) ->
      Printf.sprintf "%d. %s — %d %s" entry.line_number
        (request_label entry.request) entry.response.Freight.Ast.status
        entry.response.Freight.Ast.status_text)
  in
  let header =
    match progress with
    | Some (done_count, total) ->
      Printf.sprintf "Running %d/%d requests…" done_count total
    | None ->
      Printf.sprintf "Run all complete: %d succeeded, %d failed"
        success_count failure_count
  in
  let failed_section =
    if failure_lines = [] then [] else [ ""; "Failed" ] @ failure_lines
  in
  let success_section =
    if success_lines = [] then [] else [ ""; "Successful" ] @ success_lines
  in
  [ header ] @ failed_section @ success_section

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
            record_response state request response verbose_raw loading_buf name;
            Freight_effect.update_scratch loading_buf
              ~name ~filetype
              ~lines:(Freight.Response.render response);
            set_response_keymaps loading_buf))

let freight_run_all state =
  let buf, source, _cursor_line = current_source () in
  let source_window =
    Freight_effect.nvim_call "nvim_get_current_win" [] |> decode_handle
  in
  let env = resolve_env state buf in
  match Freight.Parser.parse_string source with
  | Error err ->
    let scratch_buf =
      Freight_effect.show_scratch
        ~name:"freight://error"
        ~filetype:"freight"
        ~lines:(Request_view.render_parse_error err)
    in
    set_buf_keymaps scratch_buf
  | Ok { Freight.Ast.requests = []; _ } ->
    show_error "No requests found in buffer."
  | Ok _file ->
    let requests =
      match Freight.Parser.parse_source_with_lines source with
      | Error _ -> []
      | Ok pairs ->
        List.map
          (fun (source_line, request) ->
            ( source_line
            , request
              |> Freight.Resolve.substitute_request env
              |> Freight.Ast.apply_host_header ))
          pairs
    in
    let name = "freight://run-all" in
    let loading_buf =
      Freight_effect.show_scratch
        ~name
        ~filetype:"freight"
        ~lines:[ Printf.sprintf "Running %d requests…" (List.length requests) ]
    in
    set_buf_keymaps loading_buf;
    Freight_effect.set_keymap loading_buf ~key:"<CR>"
      ~command:":<C-u>execute 'FreightViewRunAll ' . line('.')<CR>";
    Freight_effect.set_keymap loading_buf ~key:"o"
      ~command:":<C-u>execute 'FreightJumpRunAll ' . line('.')<CR>";
    Freight_effect.fork "FreightRunAll" @@ fun () ->
      let results = ref [] in
      List.iteri
        (fun index (source_line, request) ->
          let line_number = index + 1 in
          let source_buffer = buf in
          let invocation = Freight.Executor.to_curl request in
          match Freight_effect.run_curl invocation with
          | Error message ->
            results :=
              State.Run_all_failure
                { line_number; source_buffer; source_window; source_line; request; message; response = None }
              :: !results
          | Ok raw ->
            (match Freight.Response.parse_curl_output raw request with
             | Error message ->
               results :=
                 State.Run_all_failure
                   { line_number; source_buffer; source_window; source_line; request; message; response = None }
                 :: !results
             | Ok response ->
               if response.Freight.Ast.status >= 400 then
                 results :=
                   State.Run_all_failure
                     { line_number
                     ; source_buffer
                     ; source_window
                     ; source_line
                     ; request
                     ; message =
                         Printf.sprintf "%d %s" response.status response.status_text
                     ; response = Some response
                     }
                   :: !results
               else begin
                 record_response state request response "" loading_buf name;
                 results :=
                   State.Run_all_success
                     { line_number; source_buffer; source_window; source_line; request; response; verbose = "" }
                   :: !results
               end);
          state.State.run_all_results <- List.rev !results;
          Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
            ~lines:(render_run_all_results ~progress:(line_number, List.length requests)
                      state.State.run_all_results))
        requests;
      Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
        ~lines:(render_run_all_results state.State.run_all_results)

let run_all_result_at_line results line_number =
  let failures, successes =
    List.partition_map
      (function
       | State.Run_all_failure entry -> Left (State.Run_all_failure entry)
       | State.Run_all_success entry -> Right (State.Run_all_success entry))
      results
  in
  let line = ref 1 in
  let append_section entries =
    match entries with
    | [] -> []
    | _ ->
      line := !line + 2;
      let mapped =
        List.mapi (fun index entry -> (!line + index + 1, entry)) entries
      in
      line := !line + List.length entries;
      mapped
  in
  let failure_entries = append_section failures in
  let success_entries = append_section successes in
  let indexed_lines = failure_entries @ success_entries in
  List.assoc_opt line_number indexed_lines

let freight_jump_run_all state line_number =
  let jump _source_window source_buffer source_line =
    let command =
      Printf.sprintf
        "lua local wins=vim.fn.win_findbuf(%d); if #wins > 0 then vim.fn.win_gotoid(wins[1]) else vim.cmd('buffer %d') end; vim.api.nvim_win_set_cursor(0, {%d, 0})"
        source_buffer source_buffer source_line
    in
    ignore (Freight_effect.nvim_call "nvim_command" [ Msgpck.String command ])
  in
  match run_all_result_at_line state.State.run_all_results line_number with
  | None -> show_error "No run-all entry at that line."
  | Some (State.Run_all_success entry) ->
    jump entry.source_window entry.source_buffer entry.source_line
  | Some (State.Run_all_failure entry) ->
    jump entry.source_window entry.source_buffer entry.source_line

let freight_view_run_all state line_number =
  match run_all_result_at_line state.State.run_all_results line_number with
  | None -> show_error "No run-all entry at that line."
  | Some (State.Run_all_success entry) ->
    let name = Freight.Buffer.buffer_name entry.request in
    let filetype =
      Freight.Buffer.filetype_of_content_type
        (Freight.Response.detect_content_type entry.response)
    in
    state.State.last_response <- Some entry.response;
    state.State.verbose_output <-
      (if entry.verbose = "" then None else Some entry.verbose);
    let buf = Freight_effect.current_buffer () in
    Freight_effect.update_scratch buf ~name ~filetype
      ~lines:(Freight.Response.render entry.response);
    set_buf_keymaps buf;
    set_response_keymaps buf;
    state.State.response_buf <- Some buf;
    state.State.response_buf_name <- Some name
  | Some (State.Run_all_failure entry) ->
    (match entry.response with
     | Some response ->
       let name = Freight.Buffer.buffer_name entry.request in
       let filetype =
         Freight.Buffer.filetype_of_content_type
           (Freight.Response.detect_content_type response)
       in
       state.State.last_response <- Some response;
       state.State.verbose_output <- None;
       let buf = Freight_effect.current_buffer () in
       Freight_effect.update_scratch buf ~name ~filetype
         ~lines:(Freight.Response.render response);
       set_buf_keymaps buf;
       set_response_keymaps buf;
       state.State.response_buf <- Some buf;
       state.State.response_buf_name <- Some name
     | None ->
       let buf = Freight_effect.current_buffer () in
       Freight_effect.update_scratch buf
         ~name:"freight://run-all/failure"
         ~filetype:"freight"
         ~lines:[ "Request failed"; ""; request_label entry.request; ""; entry.message ];
       set_buf_keymaps buf)

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
             | None -> [ "No verbose output available for run-all results." ]
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
