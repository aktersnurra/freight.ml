open OUnit2

let test_method_to_string _ =
  assert_equal ~printer:Fun.id "GET" (Freight.Ast.method_to_string Freight.Ast.Get)

let test_method_of_string _ =
  assert_equal Freight.Ast.Post (Freight.Ast.method_of_string "POST");
  assert_equal (Freight.Ast.Custom "PROPFIND")
    (Freight.Ast.method_of_string "PROPFIND")

let parse_ok source =
  match Freight.Parser.parse_string source with
  | Ok file -> file
  | Error error -> assert_failure error.Freight.Ast.message

let parse_error source =
  match Freight.Parser.parse_string source with
  | Ok _ -> assert_failure "expected parse error"
  | Error error -> error

let test_parse_named_json_request _ =
  let file =
    parse_ok
      "# @name login\nPOST https://api.example.com/auth\nContent-Type: \
       application/json\n\n{\"user\":\"me\"}\n"
  in
  match file.requests with
  | [ request ] ->
      assert_equal (Some "login") request.name;
      assert_equal Freight.Ast.Post request.method_;
      assert_equal "https://api.example.com/auth" request.url;
      assert_equal [ ("Content-Type", "application/json") ] request.headers;
      assert_equal (Freight.Ast.Body_inline "{\"user\":\"me\"}") request.body
  | _ -> assert_failure "expected one request"

let test_parse_two_requests_with_separator _ =
  let file = parse_ok "GET https://one.test\n\n###\nGET https://two.test\n\n" in
  match file.requests with
  | [ first; second ] ->
      assert_equal "https://one.test" first.url;
      assert_equal "https://two.test" second.url
  | _ -> assert_failure "expected two requests in order"

let test_parse_request_line_missing_url _ =
  let error = parse_error "GET\n" in
  assert_equal "missing request URL" error.message

let test_parse_body_file _ =
  let file = parse_ok "PUT https://api.example.com/upload\n\n< fixtures/payload.json\n" in
  match file.requests with
  | [ request ] ->
      assert_equal (Freight.Ast.Body_file "fixtures/payload.json") request.body
  | _ -> assert_failure "expected one request"

let test_parse_crlf_and_trailing_whitespace _ =
  let file =
    parse_ok
      "# @name ping\r\nGET https://example.test   \r\nAccept: text/plain   \r\n\r\n"
  in
  match file.requests with
  | [ request ] ->
      assert_equal (Some "ping") request.name;
      assert_equal "https://example.test" request.url;
      assert_equal [ ("Accept", "text/plain") ] request.headers;
      assert_equal Freight.Ast.Body_none request.body
  | _ -> assert_failure "expected one request"

let write_file path data =
  let channel = open_out path in
  match output_string channel data with
  | () -> close_out channel
  | exception exn ->
      close_out_noerr channel;
      raise exn

let make_temp_dir () =
  let path = Filename.temp_file "freight-env-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Sys.readdir path
      |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path
    end
    else Sys.remove path

let test_env_substitute_unknown_preserved _ =
  let env = Freight.Env.of_list [ ("host", "https://api.example.com") ] in
  assert_equal "GET https://api.example.com/{{ missing }}"
    (Freight.Env.substitute env "GET {{ host }}/{{ missing }}")

let test_env_load_precedence _ =
  let root = make_temp_dir () in
  Fun.protect
    ~finally:(fun () -> remove_tree root)
    (fun () ->
      let child = Filename.concat root "child" in
      Unix.mkdir child 0o700;
      write_file (Filename.concat root ".env") "base=root\nshared=root\n";
      write_file (Filename.concat root ".env.dev") "shared=dev\nactive=dev\n";
      write_file (Filename.concat root ".env.local") "shared=local\nlocal=root\n";
      write_file (Filename.concat child ".env") "base=child\n";
      let env = Freight.Env.load ~dir:child ~active_env:(Some "dev") in
      assert_equal (Some "child") (Freight.Env.find env "base");
      assert_equal (Some "local") (Freight.Env.find env "shared");
      assert_equal (Some "dev") (Freight.Env.find env "active");
      assert_equal (Some "root") (Freight.Env.find env "local"))

let sample_request body =
  {
    Freight.Ast.name = Some "login";
    method_ = Freight.Ast.Post;
    url = "https://api.example.com/auth";
    headers = [ ("Content-Type", "application/json") ];
    body;
  }

let test_to_curl_inline_body _ =
  let invocation =
    Freight.Executor.to_curl (sample_request (Freight.Ast.Body_inline "{}"))
  in
  assert_bool "has -i" (List.mem "-i" invocation.args);
  assert_bool "has -s" (List.mem "-s" invocation.args);
  assert_bool "has method" (List.mem "POST" invocation.args);
  assert_bool "has header" (List.mem "Content-Type: application/json" invocation.args);
  assert_bool "has data flag" (List.mem "--data-binary" invocation.args);
  assert_bool "has body" (List.mem "{}" invocation.args)

let test_to_curl_file_body _ =
  let invocation =
    Freight.Executor.to_curl (sample_request (Freight.Ast.Body_file "payload.json"))
  in
  assert_bool "has file upload" (List.mem "@payload.json" invocation.args)

let test_to_curl_put_file_body _ =
  let request =
    {
      Freight.Ast.name = Some "upload";
      method_ = Freight.Ast.Put;
      url = "https://api.example.com/upload";
      headers = [];
      body = Freight.Ast.Body_file "payload.json";
    }
  in
  let invocation = Freight.Executor.to_curl request in
  assert_bool "has transfer flag" (List.mem "-T" invocation.args);
  assert_bool "has transfer path" (List.mem "payload.json" invocation.args)

let response_request =
  {
    Freight.Ast.name = Some "login";
    method_ = Freight.Ast.Get;
    url = "https://api.example.com";
    headers = [];
    body = Freight.Ast.Body_none;
  }

let test_parse_curl_output _ =
  let raw =
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"token\":\"abc\"}\n200\n0.142"
  in
  match Freight.Response.parse_curl_output raw response_request with
  | Ok response ->
      assert_equal 200 response.status;
      assert_equal "OK" response.status_text;
      assert_equal 142 response.duration_ms;
      assert_equal "{\"token\":\"abc\"}" response.body
  | Error message -> assert_failure message

let test_parse_curl_output_uses_last_header_block _ =
  let raw =
    "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 201 Created\r\nContent-Type: text/plain\r\n\r\ncreated\n201\n0.005"
  in
  match Freight.Response.parse_curl_output raw response_request with
  | Ok response ->
      assert_equal 201 response.status;
      assert_equal "Created" response.status_text;
      assert_equal [ ("Content-Type", "text/plain") ] response.headers;
      assert_equal "created" response.body
  | Error message -> assert_failure message

let test_parse_curl_output_keeps_body_starting_with_http _ =
  let raw = "HTTP/1.1 200 OK\r\n\r\nHTTP/1.1 is text, not headers\n200\n0.001" in
  match Freight.Response.parse_curl_output raw response_request with
  | Ok response -> assert_equal "HTTP/1.1 is text, not headers" response.body
  | Error message -> assert_failure message

let test_parse_curl_output_rejects_malformed_status_line _ =
  let raw = "NOTHTTP 200 OK\r\n\r\nbody\n200\n0.001" in
  match Freight.Response.parse_curl_output raw response_request with
  | Ok _ -> assert_failure "expected malformed status line error"
  | Error message -> assert_equal "missing HTTP status line" message

let test_parse_curl_output_rejects_malformed_trailer _ =
  let raw = "HTTP/1.1 200 OK\r\n\r\nbody\nnot-a-status\n0.001" in
  match Freight.Response.parse_curl_output raw response_request with
  | Ok _ -> assert_failure "expected malformed trailer error"
  | Error message -> assert_equal "invalid curl status trailer" message

let json_response body =
  {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("Content-Type", "application/json") ];
    body;
    duration_ms = 12;
    request = response_request;
  }

let test_detect_content_type _ =
  assert_equal Freight.Response.Json
    (Freight.Response.detect_content_type (json_response "{}"));
  assert_equal Freight.Response.Html
    (Freight.Response.detect_content_type
       { (json_response "<html></html>") with
         headers = [ ("content-type", "text/html; charset=utf-8") ];
       });
  assert_equal Freight.Response.Plain
    (Freight.Response.detect_content_type
       { (json_response "hello") with headers = [] })

let test_render_pretty_prints_json_response _ =
  assert_equal
    [
      "HTTP 200 OK (12 ms)";
      "Content-Type: application/json";
      "";
      "{ \"token\": \"abc\" }";
    ]
    (Freight.Response.render (json_response "{\"token\":\"abc\"}"))

let test_render_falls_back_to_invalid_json_body _ =
  assert_equal
    [ "HTTP 200 OK (12 ms)"; "Content-Type: application/json"; ""; "not json" ]
    (Freight.Response.render (json_response "not json"))

let test_pretty_print_json _ =
  assert_equal "{ \"token\": \"abc\" }"
    (Freight.Response.pretty_print_body Freight.Response.Json "{\"token\":\"abc\"}")

let suite =
  "freight"
  >::: [
         "method_to_string" >:: test_method_to_string;
         "method_of_string" >:: test_method_of_string;
         "parse_named_json_request" >:: test_parse_named_json_request;
         "parse_two_requests_with_separator" >:: test_parse_two_requests_with_separator;
         "parse_request_line_missing_url" >:: test_parse_request_line_missing_url;
         "parse_body_file" >:: test_parse_body_file;
         "parse_crlf_and_trailing_whitespace"
         >:: test_parse_crlf_and_trailing_whitespace;
         "env_substitute_unknown_preserved"
         >:: test_env_substitute_unknown_preserved;
         "env_load_precedence" >:: test_env_load_precedence;
         "to_curl_inline_body" >:: test_to_curl_inline_body;
         "to_curl_file_body" >:: test_to_curl_file_body;
         "to_curl_put_file_body" >:: test_to_curl_put_file_body;
         "parse_curl_output" >:: test_parse_curl_output;
         "parse_curl_output_uses_last_header_block"
         >:: test_parse_curl_output_uses_last_header_block;
         "parse_curl_output_keeps_body_starting_with_http"
         >:: test_parse_curl_output_keeps_body_starting_with_http;
         "parse_curl_output_rejects_malformed_status_line"
         >:: test_parse_curl_output_rejects_malformed_status_line;
         "parse_curl_output_rejects_malformed_trailer"
         >:: test_parse_curl_output_rejects_malformed_trailer;
         "detect_content_type" >:: test_detect_content_type;
         "render_pretty_prints_json_response" >:: test_render_pretty_prints_json_response;
         "render_falls_back_to_invalid_json_body"
         >:: test_render_falls_back_to_invalid_json_body;
         "pretty_print_json" >:: test_pretty_print_json;
       ]

let () = run_test_tt_main suite
