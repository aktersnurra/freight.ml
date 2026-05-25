open OUnit2
open Freight_plugin

let has_call pred calls =
  List.exists pred calls

let has_show_scratch ~name calls =
  has_call
    (function
     | Test_runtime_fake.Show_scratch v -> v.name = name
     | _ -> false)
    calls

let has_update_scratch calls =
  has_call
    (function Test_runtime_fake.Update_scratch _ -> true | _ -> false)
    calls

let has_run_curl calls =
  has_call
    (function Test_runtime_fake.Run_curl _ -> true | _ -> false)
    calls

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
  assert_bool "shows env scratch"
    (has_show_scratch ~name:"freight://env" calls)

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
  state.State.response_buf_name <- Some "freight://response/test";
  let config =
    { Test_runtime_fake.default_config with
      nvim_eval_result = Msgpck.Int 5
    }
  in
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
  state.State.response_buf_name <- Some "freight://response/test";
  let config =
    { Test_runtime_fake.default_config with
      nvim_eval_result = Msgpck.Int 5
    }
  in
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
  state.State.response_buf_name <- Some "freight://response/test";
  let config =
    { Test_runtime_fake.default_config with
      nvim_eval_result = Msgpck.Int 5
    }
  in
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

let suite =
  "Handlers" >:::
    [ "freight_open" >:: test_freight_open
    ; "freight_env" >:: test_freight_env
    ; "freight_inspect parse error" >:: test_freight_inspect_parse_error
    ; "freight_inspect valid" >:: test_freight_inspect_valid
    ; "freight_run no request" >:: test_freight_run_no_request
    ; "freight_run curl error" >:: test_freight_run_curl_error
    ; "freight_run success" >:: test_freight_run_success
    ; "freight_run parse error" >:: test_freight_run_parse_error
    ; "freight_view no response" >:: test_freight_view_no_response
    ; "freight_view Body" >:: test_freight_view_body
    ; "freight_view Headers" >:: test_freight_view_headers
    ; "freight_view All" >:: test_freight_view_all
    ; "push_history" >:: test_push_history
    ; "push_history_cap" >:: test_push_history_cap
    ]

let () = run_test_tt_main suite
