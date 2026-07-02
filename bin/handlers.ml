let show_or_update state ~name ~filetype ~lines =
  match state.State.response_buf with
  | Some buf ->
    Freight_effect.update_scratch buf ~name ~filetype ~lines;
    state.State.response_buf_name <- Some name;
    buf
  | None ->
    let buf = Freight_effect.show_scratch ~name ~filetype ~lines in
    state.State.response_buf <- Some buf;
    state.State.response_buf_name <- Some name;
    buf

let show_error_state state message =
  ignore
    (show_or_update state
       ~name:"freight://error"
       ~filetype:"freight"
       ~lines:(Request_view.render_message ~title:"Error" ~body:[ message ]))

let show_error message =
  ignore
    (Freight_effect.show_scratch
       ~name:"freight://error"
       ~filetype:"freight"
       ~lines:(Request_view.render_message ~title:"Error" ~body:[ message ]))

(* Variables left as literal [{{...}}] in an already-substituted request will be
   shipped verbatim to curl and fail cryptically, so report them up front. *)
let unresolved_message unresolved =
  let names = String.concat ", " unresolved in
  Printf.sprintf
    "Unresolved variables: %s — run the request that defines them first, or add them to .env."
    names

let current_source () =
  let buf = Freight_effect.current_buffer () in
  let lines = Freight_effect.buffer_lines buf in
  let cursor = Freight_effect.cursor () in
  (buf, String.concat "\n" lines, cursor.Freight_effect.Cursor.row)

let resolve_env state buf =
  match Freight_effect.buffer_dir buf with
  | Some dir ->
    (* Load .env files as the base, then overlay the accumulated env so that
       response-chaining variables injected by earlier runs survive. *)
    let base = Freight_effect.load_env ~dir ~active_env:state.State.active_env in
    Freight.Env.overlay ~base ~over:state.State.env
  | None -> state.State.env

(* The active resolver: response-chaining vars (deep, lazy) take precedence over
   .env / accumulated env values. *)
let build_resolver state buf =
  let env = resolve_env state buf in
  Freight.Resolver.make
    [ Freight.Response_store.source state.State.responses
    ; Freight.Env.source env
    ]

let resolve_request state source cursor_line buf =
  let resolver = build_resolver state buf in
  Freight.Resolve.at_cursor_r ~source ~cursor_line ~resolver

let set_buf_keymaps buf =
  Freight_effect.set_keymap buf ~key:"q" ~command:":close<CR>";
  Freight_effect.set_keymap buf ~key:"g?" ~command:":FreightHelp<CR>"

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
      show_or_update state
        ~name:"freight://error"
        ~filetype:"freight"
        ~lines:(Request_view.render_parse_error err)
    in
    set_buf_keymaps scratch_buf
  | Error `No_request ->
    show_error_state state "No request under cursor."
  | Ok request ->
    let invocation = Freight.Executor.to_curl request in
    let scratch_buf =
      show_or_update state
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
      ; "  S                     Return to run-all summary"
      ; ""
      ; "  (response buffer)"
      ; "  B                     Body view"
      ; "  H                     Headers view"
      ; "  A                     All view"
      ; "  V                     Verbose view"
      ]

let record_response state request response verbose_raw response_buf response_buf_name =
  let req_name = Option.value request.Freight.Ast.name ~default:"" in
  state.State.responses <-
    Freight.Response_store.record ~name:req_name response state.State.responses;
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

(* Save targets resolve relative to the .http file's directory, mirroring how
   [< file] body includes are read. *)
let resolve_save_path ~dir path =
  if Filename.is_relative path then
    match dir with Some dir -> Filename.concat dir path | None -> path
  else path

(* Pull the filename from a Content-Disposition: attachment; filename="..."
   header, used when [>>] is given without an explicit path. *)
let content_disposition_filename response =
  response.Freight.Ast.headers
  |> List.find_map (fun (name, value) ->
       if String.lowercase_ascii name = "content-disposition" then
         value
         |> String.split_on_char ';'
         |> List.find_map (fun param ->
              match String.index_opt param '=' with
              | Some index
                when String.lowercase_ascii (String.trim (String.sub param 0 index)) = "filename" ->
                let raw =
                  String.sub param (index + 1) (String.length param - index - 1)
                  |> String.trim
                in
                let length = String.length raw in
                Some
                  (if length >= 2 && raw.[0] = '"' && raw.[length - 1] = '"' then
                     String.sub raw 1 (length - 2)
                   else raw)
              | _ -> None)
       else None)

(* After a saved request completes, report where the body landed. For an
   explicit path curl already streamed the bytes to disk (-o); for a derived
   path we write the parsed body ourselves. *)
let report_saved ~dir ~name loading_buf save response render_lines =
  let saved path bytes =
    Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
      ~lines:(render_lines @ [ ""; Printf.sprintf "Saved %d bytes to %s" bytes path ])
  in
  match save.Freight.Ast.save_path with
  | Some path ->
    (* curl streamed the body to disk with -o, so the parsed response body is
       empty; report the actual file size instead. *)
    let path = resolve_save_path ~dir path in
    (match Freight_effect.file_size path with
     | Some bytes -> saved path bytes
     | None ->
       Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
         ~lines:(render_lines @ [ ""; "Saved to " ^ path ]))
  | None ->
    (match content_disposition_filename response with
     | None ->
       Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
         ~lines:(render_lines
                 @ [ ""
                   ; "Could not save: no path given and no Content-Disposition filename."
                   ])
     | Some filename ->
       let path = resolve_save_path ~dir filename in
       (match Freight_effect.write_file ~path ~data:response.Freight.Ast.body with
        | Ok bytes -> saved path bytes
        | Error message ->
          Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
            ~lines:(render_lines @ [ ""; "Could not save: " ^ message ])))

(* Render an "Assertions" section: a ✓/✗ line per declared assertion, with the
   failure detail on the ✗ lines. Empty when the request declares none. *)
let assertion_lines request response =
  match request.Freight.Ast.assertions with
  | [] -> []
  | assertions ->
    let failures = Freight.Assertion.check response assertions in
    let failed a =
      List.find_opt (fun (f : Freight.Assertion.failure) -> f.assertion == a) failures
    in
    let line a =
      match failed a with
      | None -> "✓ " ^ Freight.Assertion.describe a
      | Some f -> Printf.sprintf "✗ %s — %s" (Freight.Assertion.describe a) f.detail
    in
    "" :: "Assertions" :: List.map line assertions

let freight_run state =
  let buf, source, cursor_line = current_source () in
  let dir = Freight_effect.buffer_dir buf in
  match resolve_request state source cursor_line buf with
  | Error (`Parse err) ->
    let scratch_buf =
      show_or_update state
        ~name:"freight://error"
        ~filetype:"freight"
        ~lines:(Request_view.render_parse_error err)
    in
    set_buf_keymaps scratch_buf
  | Error `No_request ->
    show_error_state state "No request under cursor."
  | Ok request when Freight.Resolve.unresolved_request Freight.Env.empty request <> [] ->
    let unresolved =
      Freight.Resolve.unresolved_request Freight.Env.empty request
    in
    show_error_state state (unresolved_message unresolved)
  | Ok request ->
    (* Resolve a save target's path against the .http file's directory so both
       the no-clobber check and curl's [-o] point at the right file. *)
    let request =
      match request.Freight.Ast.save_to with
      | Some ({ save_path = Some path; _ } as save) ->
        { request with save_to = Some { save with save_path = Some (resolve_save_path ~dir path) } }
      | _ -> request
    in
    let clobbers =
      match request.Freight.Ast.save_to with
      | Some { save_path = Some path; overwrite = false } -> Freight_effect.file_exists path
      | _ -> false
    in
    if clobbers then
      let path =
        match request.Freight.Ast.save_to with
        | Some { save_path = Some path; _ } -> path
        | _ -> ""
      in
      show_error_state state
        (Printf.sprintf "%s already exists — use >>! to overwrite." path)
    else
      let invocation = Freight.Executor.to_curl request in
      let name = Freight.Buffer.buffer_name request in
      let loading_buf =
        show_or_update state
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
              let render_lines =
                Freight.Response.render response @ assertion_lines request response
              in
              Freight_effect.update_scratch loading_buf
                ~name ~filetype
                ~lines:render_lines;
              set_response_keymaps loading_buf;
              (match request.Freight.Ast.save_to with
               | Some save -> report_saved ~dir ~name loading_buf save response render_lines
               | None -> ())))

let freight_run_all state =
  let buf, source, _cursor_line = current_source () in
  let source_window =
    Freight_effect.nvim_call "nvim_get_current_win" [] |> decode_handle
  in
  let base_env = resolve_env state buf in
  match Freight.Parser.parse_string source with
  | Error err ->
    let scratch_buf =
      show_or_update state
        ~name:"freight://error"
        ~filetype:"freight"
        ~lines:(Request_view.render_parse_error err)
    in
    set_buf_keymaps scratch_buf
  | Ok { Freight.Ast.requests = []; _ } ->
    show_error_state state "No requests found in buffer."
  | Ok _file ->
    (* Keep the requests unsubstituted here; each is resolved lazily inside the
       run loop against the accumulating env so that later requests can see the
       response variables injected by earlier ones. *)
    let requests =
      match Freight.Parser.parse_source_with_lines source with
      | Error _ -> []
      | Ok pairs -> pairs
    in
    let name = "freight://run-all" in
    let loading_buf =
      show_or_update state
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
        (fun index (source_line, raw_request) ->
          let line_number = index + 1 in
          let source_buffer = buf in
          (* Resolve against the response store (which accrues earlier responses
             this run) layered over the loaded env. *)
          let resolver =
            Freight.Resolver.make
              [ Freight.Response_store.source state.State.responses
              ; Freight.Env.source base_env
              ]
          in
          let request =
            raw_request
            |> Freight.Resolve.substitute_request_r resolver
            |> Freight.Ast.apply_host_header
          in
          let unresolved =
            Freight.Resolve.unresolved_request Freight.Env.empty request
          in
          if unresolved <> [] then
            results :=
              State.Run_all_failure
                { line_number; source_buffer; source_window; source_line
                ; request; message = unresolved_message unresolved; response = None }
              :: !results
          else begin
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
                 match Freight.Assertion.check response request.Freight.Ast.assertions with
                 | failure :: _ ->
                   results :=
                     State.Run_all_failure
                       { line_number; source_buffer; source_window; source_line
                       ; request
                       ; message =
                           "assertion failed: "
                           ^ Freight.Assertion.describe failure.Freight.Assertion.assertion
                       ; response = Some response }
                     :: !results
                 | [] ->
                   results :=
                     State.Run_all_success
                       { line_number; source_buffer; source_window; source_line; request; response; verbose = "" }
                     :: !results
               end)
          end;
          state.State.run_all_results <- List.rev !results;
          Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
            ~lines:(render_run_all_results ~progress:(line_number, List.length requests)
                      state.State.run_all_results))
        requests;
      state.State.run_all_summary <- render_run_all_results state.State.run_all_results;
      Freight_effect.update_scratch loading_buf ~name ~filetype:"freight"
        ~lines:state.State.run_all_summary

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
    Freight_effect.set_keymap buf ~key:"S" ~command:":FreightRunAllSummary<CR>";
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
       Freight_effect.set_keymap buf ~key:"S" ~command:":FreightRunAllSummary<CR>";
       state.State.response_buf <- Some buf;
       state.State.response_buf_name <- Some name
     | None ->
       let buf = Freight_effect.current_buffer () in
       Freight_effect.update_scratch buf
         ~name:"freight://run-all/failure"
         ~filetype:"freight"
         ~lines:[ "Request failed"; ""; request_label entry.request; ""; entry.message ];
       set_buf_keymaps buf)

let freight_run_all_summary state =
  match state.State.response_buf with
  | Some buf when state.State.run_all_summary <> [] ->
    Freight_effect.update_scratch buf
      ~name:"freight://run-all"
      ~filetype:"freight"
      ~lines:state.State.run_all_summary;
    set_buf_keymaps buf;
    Freight_effect.set_keymap buf ~key:"<CR>"
      ~command:":<C-u>execute 'FreightViewRunAll ' . line('.')<CR>";
    Freight_effect.set_keymap buf ~key:"o"
      ~command:":<C-u>execute 'FreightJumpRunAll ' . line('.')<CR>"
  | _ -> show_error_state state "No run-all summary available."

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
    show_or_update state
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
  | None -> show_error_state state "No history entry at that line."
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
    let buf =
      show_or_update state ~name ~filetype
        ~lines:(Freight.Response.render response)
    in
    set_buf_keymaps buf;
    set_response_keymaps buf
