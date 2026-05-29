open OUnit2

let has_call pred calls =
  List.exists pred calls

let has_show_scratch ~name calls =
  has_call
    (function
     | Test_runtime_fake.Show_scratch v -> v.name = name
     | _ -> false)
    calls

let has_show_float_line line calls =
  has_call
    (function
     | Test_runtime_fake.Show_float v -> List.mem line v.lines
     | _ -> false)
    calls

let has_update_scratch calls =
  has_call
    (function Test_runtime_fake.Update_scratch _ -> true | _ -> false)
    calls

let has_update_scratch_line line calls =
  has_call
    (function
     | Test_runtime_fake.Update_scratch (_, view) -> List.mem line view.lines
     | _ -> false)
    calls

let update_scratch_lines calls =
  calls
  |> List.filter_map (function
    | Test_runtime_fake.Update_scratch (_, view) -> Some view.lines
    | _ -> None)

let has_no_update_scratch_line line calls =
  calls
  |> update_scratch_lines
  |> List.exists (fun lines -> not (List.mem line lines))

let has_run_curl calls =
  has_call
    (function Test_runtime_fake.Run_curl _ -> true | _ -> false)
    calls

let count_run_curl calls =
  List.fold_left
    (fun count -> function
      | Test_runtime_fake.Run_curl _ -> count + 1
      | _ -> count)
    0 calls

let count_run_curl_verbose calls =
  List.fold_left
    (fun count -> function
      | Test_runtime_fake.Run_curl_verbose _ -> count + 1
      | _ -> count)
    0 calls

let has_fork calls =
  has_call
    (function Test_runtime_fake.Fork _ -> true | _ -> false)
    calls

let has_set_keymap ~key calls =
  has_call
    (function
     | Test_runtime_fake.Set_keymap (_, k, _) -> k = key
     | _ -> false)
    calls

(* freight_open *)

let test_freight_open _ =
  let config = Test_runtime_fake.default_config in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_open (State.create ())
  in
  assert_bool "creates scratch buffer"
    (has_show_scratch ~name:"freight://request" calls)

(* freight_env *)

let test_freight_env _ =
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines = [ "GET https://example.com" ]
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_env (State.create ()) (Some "staging")
  in
  assert_bool "does not show env scratch"
    (not (has_show_scratch ~name:"freight://env" calls));
  assert_bool "notifies active env"
    (has_call
       (function
        | Test_runtime_fake.Notify (Freight_effect.Info, "Freight env: .env.staging") -> true
        | _ -> false)
       calls)

(* freight_inspect *)

let test_freight_inspect_parse_error _ =
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines = [ "GET" ]
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_inspect (State.create ())
  in
  assert_bool "shows error scratch"
    (has_show_scratch ~name:"freight://error" calls)

let test_freight_inspect_valid _ =
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines =
        [ "# @name test"
        ; "GET https://example.com"
        ]
    ; cursor = { Freight_effect.Cursor.row = 1; col = 0 }
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_inspect (State.create ())
  in
  assert_bool "shows inspect scratch"
    (has_show_scratch ~name:"freight://inspect" calls)

(* freight_help *)

let test_freight_help_includes_run_all _ =
  let (), calls =
    Test_runtime_fake.run Test_runtime_fake.default_config @@ fun () ->
      Handlers.freight_help (State.create ())
  in
  assert_bool "documents run all command"
    (has_show_float_line "  :FreightRunAll        Run every request in the buffer" calls);
  assert_bool "documents run all enter"
    (has_show_float_line "  <CR>                  Open run-all/history entry" calls)

(* freight_run *)

let test_freight_run_no_request _ =
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines = [ "" ]
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run (State.create ())
  in
  assert_bool "shows error"
    (has_show_scratch ~name:"freight://error" calls);
  assert_bool "no curl"
    (not (has_run_curl calls))

let test_freight_run_curl_error _ =
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines =
        [ "# @name test"
        ; "GET https://example.com"
        ]
    ; cursor = { Freight_effect.Cursor.row = 1; col = 0 }
    ; curl_result = Error "connection refused"
    ; fork_mode = `Run_immediately
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run (State.create ())
  in
  assert_bool "curl was run" (has_run_curl calls);
  assert_bool "scratch updated with error" (has_update_scratch calls)

let test_freight_run_success _ =
  let curl_output =
    "HTTP/1.1 200 OK\r\n\
     Content-Type: application/json\r\n\
     \r\n\
     {\"ok\":true}\n\
     200\n\
     0.042"
  in
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines =
        [ "# @name login"
        ; "GET https://example.com"
        ]
    ; cursor = { Freight_effect.Cursor.row = 1; col = 0 }
    ; curl_result = Ok curl_output
    ; fork_mode = `Run_immediately
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run (State.create ())
  in
  assert_bool "curl was run" (has_run_curl calls);
  assert_bool "scratch updated" (has_update_scratch calls);
  assert_bool "forked for background" (has_fork calls);
  assert_bool "B keymap set" (has_set_keymap ~key:"B" calls);
  assert_bool "H keymap set" (has_set_keymap ~key:"H" calls);
  assert_bool "A keymap set" (has_set_keymap ~key:"A" calls)

let test_freight_run_all_runs_every_request _ =
  let curl_output =
    "HTTP/1.1 200 OK\r\n\
     Content-Type: application/json\r\n\
     \r\n\
     {\"ok\":true}\n\
     200\n\
     0.042"
  in
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines =
        [ "GET https://httpbin.org/get"
        ; ""
        ; "###"
        ; "POST /post"
        ; "Host: https://httpbin.org/"
        ; "Content-Type: application/json"
        ; ""
        ; "{\"message\": \"hello from freight\"}"
        ]
    ; curl_result = Ok curl_output
    ; curl_verbose_result = Ok curl_output
    ; fork_mode = `Run_immediately
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run_all (State.create ())
  in
  assert_equal 2 (count_run_curl calls);
  assert_equal 0 (count_run_curl_verbose calls);
  assert_bool "second request uses absolute url"
    (has_call
       (function
        | Test_runtime_fake.Run_curl invocation ->
          List.mem "https://httpbin.org/post" invocation.Freight.Executor.args
        | _ -> false)
       calls);
  assert_bool "no raw relative URL reaches curl"
    (not
       (has_call
          (function
           | Test_runtime_fake.Run_curl invocation ->
             List.mem "/post" invocation.Freight.Executor.args
           | _ -> false)
          calls))

let test_freight_run_all_groups_results _ =
  let raw_response =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello\n200\n0.010"
  in
  let state = State.create () in
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines =
        [ "GET https://example.com/ok"; ""; "###"; "GET https://example.com/fail" ]
    ; curl_result = Ok raw_response
    ; fork_mode = `Run_immediately
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run_all state
  in
  assert_equal 2 (List.length state.State.run_all_results);
  assert_bool "hides empty failed heading" (has_no_update_scratch_line "Failed" calls);
  assert_bool "has successful heading" (has_update_scratch_line "Successful" calls);
  assert_bool "updates progress after first request"
    (has_update_scratch_line "Running 1/2 requests…" calls);
  assert_bool "enter keymap set"
    (has_set_keymap ~key:"<CR>" calls);
  assert_bool "jump keymap set"
    (has_set_keymap ~key:"o" calls);
  assert_bool "records source line"
    (match state.State.run_all_results with
     | [ State.Run_all_success first; State.Run_all_success second ] ->
       first.source_line = 1 && second.source_line = 4
     | _ -> false)

let test_freight_run_all_groups_http_errors_as_failed _ =
  let raw_response =
    "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nbad\n400\n0.010"
  in
  let state = State.create () in
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines = [ "POST https://example.com/post" ]
    ; curl_result = Ok raw_response
    ; fork_mode = `Run_immediately
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run_all state
  in
  assert_bool "400 is stored as failure"
    (match state.State.run_all_results with
     | [ State.Run_all_failure _ ] -> true
     | _ -> false);
  assert_bool "summary counts HTTP error as failed"
    (has_update_scratch_line "Run all complete: 0 succeeded, 1 failed" calls);
  assert_bool "hides empty successful heading" (has_no_update_scratch_line "Successful" calls)

let test_freight_run_all_http_failure_opens_response_detail _ =
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Post
    ; url = "https://example.com/post"
    ; headers = []
    ; body = Freight.Ast.Body_none
    }
  in
  let response =
    { Freight.Ast.status = 400
    ; status_text = "Bad Request"
    ; headers = [ ("Content-Type", "text/plain") ]
    ; body = "bad body"
    ; duration_ms = 10
    ; request
    }
  in
  let state = State.create () in
  state.State.run_all_results <-
    [ State.Run_all_failure
        { line_number = 1
        ; source_buffer = 1
        ; source_window = 1
        ; source_line = 1
        ; request
        ; message = "400 Bad Request"
        ; response = Some response
        } ];
  let (), calls =
    Test_runtime_fake.run Test_runtime_fake.default_config @@ fun () ->
      Handlers.freight_view_run_all state 4
  in
  assert_bool "opens HTTP failure response scratch"
    (has_show_scratch ~name:"freight://response/post-example-com-post" calls)

let test_freight_view_run_all_success _ =
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://example.com/ok"
    ; headers = []
    ; body = Freight.Ast.Body_none
    }
  in
  let response =
    { Freight.Ast.status = 200
    ; status_text = "OK"
    ; headers = []
    ; body = "hello"
    ; duration_ms = 10
    ; request
    }
  in
  let state = State.create () in
  state.State.run_all_results <-
    [ State.Run_all_success
        { line_number = 1
        ; source_buffer = 1
        ; source_window = 1
        ; source_line = 1
        ; request
        ; response
        ; verbose = ""
        } ];
  let (), calls =
    Test_runtime_fake.run Test_runtime_fake.default_config @@ fun () ->
      Handlers.freight_view_run_all state 4
  in
  assert_bool "opens response scratch"
    (has_show_scratch ~name:"freight://response/get-example-com-ok" calls)

let test_freight_view_run_all_verbose_unavailable _ =
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://example.com/ok"
    ; headers = []
    ; body = Freight.Ast.Body_none
    }
  in
  let response =
    { Freight.Ast.status = 200
    ; status_text = "OK"
    ; headers = []
    ; body = "hello"
    ; duration_ms = 10
    ; request
    }
  in
  let state = State.create () in
  state.State.run_all_results <-
    [ State.Run_all_success
        { line_number = 1
        ; source_buffer = 1
        ; source_window = 1
        ; source_line = 1
        ; request
        ; response
        ; verbose = ""
        } ];
  let (), _calls =
    Test_runtime_fake.run Test_runtime_fake.default_config @@ fun () ->
      Handlers.freight_view_run_all state 4
  in
  let (), calls =
    Test_runtime_fake.run Test_runtime_fake.default_config @@ fun () ->
      Handlers.freight_view state "Verbose"
  in
  assert_bool "shows unavailable verbose message"
    (has_update_scratch_line "No verbose output available for run-all results." calls)

let test_freight_view_run_all_failure _ =
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://example.com/fail"
    ; headers = []
    ; body = Freight.Ast.Body_none
    }
  in
  let state = State.create () in
  state.State.run_all_results <-
    [ State.Run_all_failure
        { line_number = 1
        ; source_buffer = 1
        ; source_window = 1
        ; source_line = 1
        ; request
        ; message = "curl failed"
        ; response = None
        } ];
  let (), calls =
    Test_runtime_fake.run Test_runtime_fake.default_config @@ fun () ->
      Handlers.freight_view_run_all state 4
  in
  assert_bool "opens failure scratch"
    (has_show_scratch ~name:"freight://run-all/failure" calls)

let test_freight_jump_run_all _ =
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://example.com/ok"
    ; headers = []
    ; body = Freight.Ast.Body_none
    }
  in
  let response =
    { Freight.Ast.status = 200
    ; status_text = "OK"
    ; headers = []
    ; body = "hello"
    ; duration_ms = 10
    ; request
    }
  in
  let state = State.create () in
  state.State.run_all_results <-
    [ State.Run_all_success
        { line_number = 1
        ; source_buffer = 7
        ; source_window = 42
        ; source_line = 12
        ; request
        ; response
        ; verbose = ""
        } ];
  let (), calls =
    Test_runtime_fake.run Test_runtime_fake.default_config @@ fun () ->
      Handlers.freight_jump_run_all state 4
  in
  assert_bool "switches to source window"
    (has_call
       (function
        | Test_runtime_fake.Nvim_call ("nvim_set_current_win", [ Msgpck.Int 42 ]) -> true
        | _ -> false)
       calls);
  assert_bool "switches to source buffer"
    (has_call
       (function
        | Test_runtime_fake.Nvim_call ("nvim_command", [ Msgpck.String "buffer 7" ]) -> true
        | _ -> false)
       calls);
  assert_bool "moves cursor to source line"
    (has_call
       (function
        | Test_runtime_fake.Nvim_call
            ("nvim_win_set_cursor", [ Msgpck.Int 0; Msgpck.List [ Msgpck.Int 12; Msgpck.Int 0 ] ]) -> true
        | _ -> false)
       calls)

let test_freight_run_parse_error _ =
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines =
        [ "# @name test"
        ; "GET https://example.com"
        ]
    ; cursor = { Freight_effect.Cursor.row = 1; col = 0 }
    ; curl_result = Ok "garbage"
    ; fork_mode = `Run_immediately
    }
  in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run (State.create ())
  in
  assert_bool "curl was run" (has_run_curl calls);
  assert_bool "scratch updated" (has_update_scratch calls)

(* freight_view *)

let test_freight_view_no_response _ =
  let config = Test_runtime_fake.default_config in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_view (State.create ()) "Body"
  in
  assert_bool "shows error"
    (has_show_scratch ~name:"freight://error" calls)

let test_freight_view_body _ =
  let state = State.create () in
  state.State.last_response <- Some
    { Freight.Ast.status = 200
    ; status_text = "OK"
    ; headers = [ ("Content-Type", "application/json") ]
    ; body = "{\"ok\":true}"
    ; duration_ms = 42
    ; request =
        { Freight.Ast.name = Some "test"
        ; method_ = Freight.Ast.Get
        ; url = "https://example.com"
        ; headers = []
        ; body = Freight.Ast.Body_none
        }
    };
  state.State.response_buf <- Some 42;
  state.State.response_buf_name <- Some "freight://response/test";
  let config = Test_runtime_fake.default_config in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_view state "Body"
  in
  assert_bool "scratch updated" (has_update_scratch calls)

let test_freight_view_headers _ =
  let state = State.create () in
  state.State.last_response <- Some
    { Freight.Ast.status = 200
    ; status_text = "OK"
    ; headers = [ ("Content-Type", "text/plain") ]
    ; body = "hello"
    ; duration_ms = 10
    ; request =
        { Freight.Ast.name = Some "test"
        ; method_ = Freight.Ast.Get
        ; url = "https://example.com"
        ; headers = []
        ; body = Freight.Ast.Body_none
        }
    };
  state.State.response_buf <- Some 42;
  state.State.response_buf_name <- Some "freight://response/test";
  let config = Test_runtime_fake.default_config in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_view state "Headers"
  in
  assert_bool "scratch updated" (has_update_scratch calls)

let test_freight_view_all _ =
  let state = State.create () in
  state.State.last_response <- Some
    { Freight.Ast.status = 200
    ; status_text = "OK"
    ; headers = [ ("Content-Type", "text/plain") ]
    ; body = "hello"
    ; duration_ms = 10
    ; request =
        { Freight.Ast.name = Some "test"
        ; method_ = Freight.Ast.Get
        ; url = "https://example.com"
        ; headers = []
        ; body = Freight.Ast.Body_none
        }
    };
  state.State.response_buf <- Some 42;
  state.State.response_buf_name <- Some "freight://response/test";
  let config = Test_runtime_fake.default_config in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_view state "All"
  in
  assert_bool "scratch updated" (has_update_scratch calls)

(* history *)

let test_push_history _ =
  let state = State.create () in
  let req = { Freight.Ast.name = Some "r1"; method_ = Get;
               url = "https://example.com"; headers = []; body = Body_none } in
  let resp = { Freight.Ast.status = 200; status_text = "OK";
               headers = []; body = ""; duration_ms = 1; request = req } in
  State.push_history state req resp "verbose";
  assert_equal 1 (List.length state.State.history);
  let entry = List.hd state.State.history in
  assert_equal req entry.State.request;
  assert_equal resp entry.State.response;
  assert_equal "verbose" entry.State.verbose

let test_push_history_cap _ =
  let state = State.create () in
  let req = { Freight.Ast.name = None; method_ = Get;
               url = "https://example.com"; headers = []; body = Body_none } in
  let resp = { Freight.Ast.status = 200; status_text = "OK";
               headers = []; body = ""; duration_ms = 1; request = req } in
  for i = 1 to 55 do
    State.push_history state req { resp with Freight.Ast.body = string_of_int i } "v"
  done;
  assert_equal 50 (List.length state.State.history);
  assert_equal "55" (List.hd state.State.history).State.response.Freight.Ast.body

let test_freight_run_appends_history _ =
  let raw_response =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello\n200\n0.010"
  in
  let config =
    { Test_runtime_fake.default_config with
      buffer_lines = [ "GET https://example.com" ]
    ; curl_result = Ok raw_response
    ; fork_mode = `Run_immediately
    }
  in
  let state = State.create () in
  let (), _calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_run state
  in
  assert_equal 1 (List.length state.State.history)

let test_freight_history_empty _ =
  let config = Test_runtime_fake.default_config in
  let state = State.create () in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_history state
  in
  assert_bool "shows history scratch"
    (has_show_scratch ~name:"freight://history" calls)

let test_freight_view_history _ =
  let state = State.create () in
  let req = { Freight.Ast.name = Some "r1"; method_ = Freight.Ast.Get;
               url = "https://example.com"; headers = []; body = Freight.Ast.Body_none } in
  let resp = { Freight.Ast.status = 200; status_text = "OK";
               headers = []; body = "hello"; duration_ms = 1; request = req } in
  State.push_history state req resp "verbose";
  let config = Test_runtime_fake.default_config in
  let (), calls =
    Test_runtime_fake.run config @@ fun () ->
      Handlers.freight_view_history state 1
  in
  assert_bool "shows response scratch"
    (has_show_scratch ~name:"freight://response/r1" calls)

let suite =
  "Handlers" >:::
    [ "freight_open" >:: test_freight_open
    ; "freight_env" >:: test_freight_env
    ; "freight_inspect parse error" >:: test_freight_inspect_parse_error
    ; "freight_inspect valid" >:: test_freight_inspect_valid
    ; "freight_help includes run all" >:: test_freight_help_includes_run_all
    ; "freight_run no request" >:: test_freight_run_no_request
    ; "freight_run curl error" >:: test_freight_run_curl_error
    ; "freight_run success" >:: test_freight_run_success
    ; "freight_run_all runs every request" >:: test_freight_run_all_runs_every_request
    ; "freight_run_all groups results" >:: test_freight_run_all_groups_results
    ; "freight_run_all groups HTTP errors as failed" >:: test_freight_run_all_groups_http_errors_as_failed
    ; "freight_run_all HTTP failure opens response detail" >:: test_freight_run_all_http_failure_opens_response_detail
    ; "freight_view_run_all success" >:: test_freight_view_run_all_success
    ; "freight_view_run_all verbose unavailable" >:: test_freight_view_run_all_verbose_unavailable
    ; "freight_view_run_all failure" >:: test_freight_view_run_all_failure
    ; "freight_jump_run_all" >:: test_freight_jump_run_all
    ; "freight_run parse error" >:: test_freight_run_parse_error
    ; "freight_run appends history" >:: test_freight_run_appends_history
    ; "freight_view no response" >:: test_freight_view_no_response
    ; "freight_view Body" >:: test_freight_view_body
    ; "freight_view Headers" >:: test_freight_view_headers
    ; "freight_view All" >:: test_freight_view_all
    ; "push_history" >:: test_push_history
    ; "push_history_cap" >:: test_push_history_cap
    ; "freight_history empty" >:: test_freight_history_empty
    ; "freight_view_history" >:: test_freight_view_history
    ]

let () = run_test_tt_main suite
