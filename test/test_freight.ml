open OUnit2

let test_method_to_string _ =
  assert_equal ~printer:Fun.id "GET" (Freight.Ast.method_to_string Freight.Ast.Get)

let test_method_of_string _ =
  assert_equal Freight.Ast.Post (Freight.Ast.method_of_string "POST");
  assert_equal (Freight.Ast.Custom "PROPFIND")
    (Freight.Ast.method_of_string "PROPFIND")

let test_make_request_rejects_empty_url _ =
  match
    Freight.Ast.make_request
      ?name:None
      ~method_:Freight.Ast.Get
      ~url:""
      ~headers:[]
      ~body:Freight.Ast.Body_none
      ()
  with
  | Error Freight.Ast.Empty_url -> ()
  | Ok _ -> assert_failure "expected Empty_url"
  | Error _ -> assert_failure "expected Empty_url"

let test_make_response_rejects_invalid_status _ =
  let request =
    {
      Freight.Ast.name = None;
      method_ = Freight.Ast.Get;
      url = "https://example.test";
      headers = [];
      body = Freight.Ast.Body_none;
    }
  in
  match
    Freight.Ast.make_response
      ~status:99
      ~status_text:"Invalid"
      ~headers:[]
      ~body:""
      ~duration_ms:0
      ~request
      ()
  with
  | Error Freight.Ast.Invalid_status -> ()
  | Ok _ -> assert_failure "expected Invalid_status"
  | Error _ -> assert_failure "expected Invalid_status"

let test_make_response_rejects_negative_duration _ =
  let request =
    {
      Freight.Ast.name = None;
      method_ = Freight.Ast.Get;
      url = "https://example.test";
      headers = [];
      body = Freight.Ast.Body_none;
    }
  in
  match
    Freight.Ast.make_response
      ~status:200
      ~status_text:"OK"
      ~headers:[]
      ~body:""
      ~duration_ms:(-1)
      ~request
      ()
  with
  | Error Freight.Ast.Negative_duration -> ()
  | Ok _ -> assert_failure "expected Negative_duration"
  | Error _ -> assert_failure "expected Negative_duration"

let assert_empty_url = function
  | Error Freight.Ast.Empty_url -> ()
  | Ok _ -> assert_failure "expected Empty_url"
  | Error _ -> assert_failure "expected Empty_url"

let test_make_response_rejects_invalid_request_url _ =
  let request =
    {
      Freight.Ast.name = None;
      method_ = Freight.Ast.Get;
      url = "";
      headers = [];
      body = Freight.Ast.Body_none;
    }
  in
  assert_empty_url
    (Freight.Ast.make_response
       ~status:200
       ~status_text:"OK"
       ~headers:[]
       ~body:""
       ~duration_ms:0
       ~request
       ())

let assert_empty_header_name = function
  | Error Freight.Ast.Empty_header_name -> ()
  | Ok _ -> assert_failure "expected Empty_header_name"
  | Error _ -> assert_failure "expected Empty_header_name"

let test_make_request_rejects_empty_header_name _ =
  assert_empty_header_name
    (Freight.Ast.make_request
       ?name:None
       ~method_:Freight.Ast.Get
       ~url:"https://example.test"
       ~headers:[ ("", "value") ]
       ~body:Freight.Ast.Body_none
       ());
  assert_empty_header_name
    (Freight.Ast.make_request
       ?name:None
       ~method_:Freight.Ast.Get
       ~url:"https://example.test"
       ~headers:[ (" \t", "value") ]
       ~body:Freight.Ast.Body_none
       ())

let test_make_response_rejects_empty_header_name _ =
  let request =
    {
      Freight.Ast.name = None;
      method_ = Freight.Ast.Get;
      url = "https://example.test";
      headers = [];
      body = Freight.Ast.Body_none;
    }
  in
  assert_empty_header_name
    (Freight.Ast.make_response
       ~status:200
       ~status_text:"OK"
       ~headers:[ ("", "value") ]
       ~body:""
       ~duration_ms:0
       ~request
       ());
  assert_empty_header_name
    (Freight.Ast.make_response
       ~status:200
       ~status_text:"OK"
       ~headers:[ (" \t", "value") ]
       ~body:""
       ~duration_ms:0
       ~request
       ())

let test_make_response_rejects_invalid_request_header_name _ =
  let make_response request =
    Freight.Ast.make_response
      ~status:200
      ~status_text:"OK"
      ~headers:[]
      ~body:""
      ~duration_ms:0
      ~request
      ()
  in
  assert_empty_header_name
    (make_response
       {
         Freight.Ast.name = None;
         method_ = Freight.Ast.Get;
         url = "https://example.test";
         headers = [ ("", "value") ];
         body = Freight.Ast.Body_none;
       });
  assert_empty_header_name
    (make_response
       {
         Freight.Ast.name = None;
         method_ = Freight.Ast.Get;
         url = "https://example.test";
         headers = [ (" \t", "value") ];
         body = Freight.Ast.Body_none;
       })

let test_make_request_preserves_fields _ =
  let headers = [ ("Accept", "application/json"); ("X-Trace", "abc") ] in
  match
    Freight.Ast.make_request
      ~name:"list-users"
      ~method_:Freight.Ast.Post
      ~url:" https://example.test/users "
      ~headers
      ~body:(Freight.Ast.Body_inline "{ }")
      ()
  with
  | Ok request ->
      assert_equal (Some "list-users") request.name;
      assert_equal Freight.Ast.Post request.method_;
      assert_equal " https://example.test/users " request.url;
      assert_equal headers request.headers;
      assert_equal (Freight.Ast.Body_inline "{ }") request.body
  | Error _ -> assert_failure "expected valid request"

let test_make_response_preserves_fields _ =
  let request =
    {
      Freight.Ast.name = Some "list-users";
      method_ = Freight.Ast.Get;
      url = "https://example.test/users";
      headers = [ ("Accept", "application/json") ];
      body = Freight.Ast.Body_none;
    }
  in
  let headers = [ ("Content-Type", "application/json"); ("X-Trace", "abc") ] in
  match
    Freight.Ast.make_response
      ~status:201
      ~status_text:" Created "
      ~headers
      ~body:"{\"ok\":true}"
      ~duration_ms:123
      ~request
      ()
  with
  | Ok response ->
      assert_equal 201 response.status;
      assert_equal " Created " response.status_text;
      assert_equal headers response.headers;
      assert_equal "{\"ok\":true}" response.body;
      assert_equal 123 response.duration_ms;
      assert_equal request response.request
  | Error _ -> assert_failure "expected valid response"

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

let test_parse_error_reports_request_line_after_metadata _ =
  let error = parse_error "# comment\n# @name broken\nGET\n" in
  assert_equal "missing request URL" error.message;
  assert_equal 3 error.line;
  assert_equal "GET" error.snippet

let test_parse_error_reports_request_line_in_second_block _ =
  let error = parse_error "GET https://one.test\n\n###\n# comment\nPOST\n" in
  assert_equal "missing request URL" error.message;
  assert_equal 5 error.line;
  assert_equal "POST" error.snippet

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

let test_env_substitute_chaining_keys _ =
  let env =
    Freight.Env.of_list
      [
        ("login.response.body.token", "abc");
        ("login.response.headers.X-Request-Id", "req-1");
      ]
  in
  assert_equal "Bearer abc"
    (Freight.Env.substitute env "Bearer {{ login.response.body.token }}");
  assert_equal "Request req-1"
    (Freight.Env.substitute env "Request {{login.response.headers.X-Request-Id}}")

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

let test_env_to_list _ =
  let env = Freight.Env.of_list [ ("b", "2"); ("a", "1"); ("c", "3") ] in
  let pairs = Freight.Env.to_list env in
  assert_equal [ ("a", "1"); ("b", "2"); ("c", "3") ] pairs

let test_env_unresolved _ =
  let env = Freight.Env.of_list [ ("host", "https://api.example.com") ] in
  let source = "GET {{host}}/users\nAuthorization: Bearer {{token}}\nX-Id: {{request_id}}" in
  let missing = Freight.Env.unresolved env source in
  assert_equal [ "request_id"; "token" ] missing

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

let test_to_curl_applies_host_header _ =
  let request =
    {
      Freight.Ast.name = Some "relative";
      method_ = Freight.Ast.Post;
      url = "/post";
      headers =
        [ ("Host", "https://httpbin.org/"); ("Content-Type", "application/json") ];
      body = Freight.Ast.Body_inline "{\"message\": \"hello from freight\"}";
    }
  in
  let invocation = Freight.Executor.to_curl request in
  assert_bool "uses absolute url" (List.mem "https://httpbin.org/post" invocation.args);
  assert_bool "does not use raw relative url" (not (List.mem "/post" invocation.args));
  assert_bool "removes Host header"
    (not (List.mem "Host: https://httpbin.org/" invocation.args))

let test_second_parsed_request_applies_host_header _ =
  let source =
    String.concat "\n"
      [ "GET https://httpbin.org/get"
      ; ""
      ; "###"
      ; "POST /post"
      ; "Host: https://httpbin.org/"
      ; "Content-Type: application/json"
      ; ""
      ; "{\"message\": \"hello from freight\"}"
      ]
  in
  let file = parse_ok source in
  match file.requests with
  | [ _; request ] ->
      let invocation = Freight.Executor.to_curl request in
      assert_bool "uses absolute url" (List.mem "https://httpbin.org/post" invocation.args);
      assert_bool "does not use raw relative url" (not (List.mem "/post" invocation.args));
      assert_bool "removes Host header"
        (not (List.mem "Host: https://httpbin.org/" invocation.args))
  | _ -> assert_failure "expected two requests"

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

let sample_response ?(body = "") () =
  {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("Content-Type", "application/json") ];
    body;
    duration_ms = 123;
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
      "HTTP 200 OK · 12 ms";
      "";
      "Headers";
      "Content-Type: application/json";
      "";
      "Body";
      "{ \"token\": \"abc\" }";
    ]
    (Freight.Response.render (json_response "{\"token\":\"abc\"}"))

let test_render_falls_back_to_invalid_json_body _ =
  assert_equal
    [
      "HTTP 200 OK · 12 ms";
      "";
      "Headers";
      "Content-Type: application/json";
      "";
      "Body";
      "not json";
    ]
    (Freight.Response.render (json_response "not json"))

let test_render_body _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [];
    body = Freight.Ast.Body_none;
  } in
  let response = {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("content-type", "application/json") ];
    body = {|{"id":1}|};
    duration_ms = 42;
    request;
  } in
  let lines = Freight.Response.render_body response in
  assert_equal [ "{ \"id\": 1 }" ] lines

let test_response_render_all_has_sections _ =
  let response = sample_response ~body:"{\"ok\":true}" () in
  let lines = Freight.Response.render_all response in
  assert_bool "has status" (List.exists (( = ) "HTTP 200 OK · 123 ms") lines);
  assert_bool "has headers heading" (List.exists (( = ) "Headers") lines);
  assert_bool "has body heading" (List.exists (( = ) "Body") lines)

let test_response_render_headers_has_heading _ =
  let response = sample_response ~body:"" () in
  let lines = Freight.Response.render_headers response in
  assert_equal [ "HTTP 200 OK · 123 ms"; ""; "Headers"; "Content-Type: application/json" ] lines

let test_render_headers _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [];
    body = Freight.Ast.Body_none;
  } in
  let response = {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("content-type", "application/json"); ("x-foo", "bar") ];
    body = {|{"id":1}|};
    duration_ms = 100;
    request;
  } in
  let lines = Freight.Response.render_headers response in
  assert_equal
    [
      "HTTP 200 OK · 100 ms";
      "";
      "Headers";
      "content-type: application/json";
      "x-foo: bar";
    ]
    lines

let test_render_all _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [];
    body = Freight.Ast.Body_none;
  } in
  let response = {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("content-type", "application/json") ];
    body = {|{"id":1}|};
    duration_ms = 42;
    request;
  } in
  let lines = Freight.Response.render_all response in
  assert_equal
    (Freight.Response.render response)
    lines

let test_pretty_print_json _ =
  assert_equal "{ \"token\": \"abc\" }"
    (Freight.Response.pretty_print_body Freight.Response.Json "{\"token\":\"abc\"}")

let login_response =
  {
    Freight.Ast.status = 200;
    status_text = "OK";
    headers = [ ("X-Request-Id", "req-1") ];
    body = "{\"token\":\"abc\",\"user\":{\"id\":\"42\"}}";
    duration_ms = 10;
    request = response_request;
  }

let test_extract_body_path _ =
  assert_equal (Some "42")
    (Freight.Chaining.extract login_response
       (Freight.Chaining.Response_body [ "user"; "id" ]))

let test_extract_header _ =
  assert_equal (Some "req-1")
    (Freight.Chaining.extract login_response
       (Freight.Chaining.Response_header "x-request-id"))

let test_inject_named_response _ =
  let env = Freight.Chaining.inject ~name:"login" login_response Freight.Env.empty in
  assert_equal (Some "abc") (Freight.Env.find env "login.response.body.token");
  assert_equal (Some "req-1")
    (Freight.Env.find env "login.response.headers.X-Request-Id")

let test_named_buffer_name _ =
  assert_equal "freight://response/login" (Freight.Buffer.buffer_name response_request)

let test_slugged_buffer_name _ =
  let request =
    {
      response_request with
      name = None;
      method_ = Freight.Ast.Post;
      url = "https://api.example.com/data";
    }
  in
  assert_equal "freight://response/post-api-example-com-data"
    (Freight.Buffer.buffer_name request)

let test_filetype_mapping _ =
  assert_equal "json" (Freight.Buffer.filetype_of_content_type Freight.Response.Json);
  assert_equal "xml" (Freight.Buffer.filetype_of_content_type Freight.Response.Xml);
  assert_equal "html" (Freight.Buffer.filetype_of_content_type Freight.Response.Html);
  assert_equal "text" (Freight.Buffer.filetype_of_content_type Freight.Response.Plain);
  assert_equal "text"
    (Freight.Buffer.filetype_of_content_type (Freight.Response.Other "application/pdf"))

let test_apply_host_header_relative_url _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Post;
    url = "/post";
    headers = [ ("Host", "https://httpbin.org"); ("Content-Type", "application/json") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://httpbin.org/post" result.Freight.Ast.url;
  assert_equal [ ("Content-Type", "application/json") ] result.Freight.Ast.headers

let test_apply_host_header_trailing_slash _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "/users";
    headers = [ ("Host", "https://api.example.com/") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://api.example.com/users" result.Freight.Ast.url;
  assert_equal [] result.Freight.Ast.headers

let test_apply_host_header_absolute_url_unchanged _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "https://httpbin.org/get";
    headers = [ ("Host", "https://other.example.com") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://httpbin.org/get" result.Freight.Ast.url;
  assert_equal [ ("Host", "https://other.example.com") ] result.Freight.Ast.headers

let test_apply_host_header_no_host_unchanged _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "/users";
    headers = [ ("Content-Type", "application/json") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "/users" result.Freight.Ast.url;
  assert_equal [ ("Content-Type", "application/json") ] result.Freight.Ast.headers

let test_apply_host_header_case_insensitive _ =
  let request = {
    Freight.Ast.name = None;
    method_ = Freight.Ast.Get;
    url = "/ping";
    headers = [ ("HOST", "https://api.example.com") ];
    body = Freight.Ast.Body_none;
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://api.example.com/ping" result.Freight.Ast.url;
  assert_equal [] result.Freight.Ast.headers

let suite =
  "freight"
  >::: [
         "method_to_string" >:: test_method_to_string;
         "method_of_string" >:: test_method_of_string;
         "make_request rejects empty url" >:: test_make_request_rejects_empty_url;
         "make_response rejects invalid status" >:: test_make_response_rejects_invalid_status;
         "make_response rejects negative duration" >:: test_make_response_rejects_negative_duration;
         "make_response rejects invalid request url"
         >:: test_make_response_rejects_invalid_request_url;
         "make_request rejects empty header name"
         >:: test_make_request_rejects_empty_header_name;
         "make_response rejects empty header name"
         >:: test_make_response_rejects_empty_header_name;
         "make_response rejects invalid request header name"
         >:: test_make_response_rejects_invalid_request_header_name;
         "make_request preserves fields" >:: test_make_request_preserves_fields;
         "make_response preserves fields" >:: test_make_response_preserves_fields;
         "apply_host_header_relative_url" >:: test_apply_host_header_relative_url;
         "apply_host_header_trailing_slash" >:: test_apply_host_header_trailing_slash;
         "apply_host_header_absolute_url_unchanged" >:: test_apply_host_header_absolute_url_unchanged;
         "apply_host_header_no_host_unchanged" >:: test_apply_host_header_no_host_unchanged;
         "apply_host_header_case_insensitive" >:: test_apply_host_header_case_insensitive;
         "parse_named_json_request" >:: test_parse_named_json_request;
         "parse_two_requests_with_separator" >:: test_parse_two_requests_with_separator;
         "parse_request_line_missing_url" >:: test_parse_request_line_missing_url;
         "parse error reports request line after metadata"
         >:: test_parse_error_reports_request_line_after_metadata;
         "parse error reports request line in second block"
         >:: test_parse_error_reports_request_line_in_second_block;
         "parse_body_file" >:: test_parse_body_file;
         "parse_crlf_and_trailing_whitespace"
         >:: test_parse_crlf_and_trailing_whitespace;
         "env_substitute_unknown_preserved"
         >:: test_env_substitute_unknown_preserved;
         "env_to_list" >:: test_env_to_list;
         "env_unresolved" >:: test_env_unresolved;
         "env_substitute_chaining_keys" >:: test_env_substitute_chaining_keys;
         "env_load_precedence" >:: test_env_load_precedence;
         "to_curl_inline_body" >:: test_to_curl_inline_body;
         "to_curl_file_body" >:: test_to_curl_file_body;
         "to_curl_put_file_body" >:: test_to_curl_put_file_body;
         "to_curl_applies_host_header" >:: test_to_curl_applies_host_header;
         "second_parsed_request_applies_host_header"
         >:: test_second_parsed_request_applies_host_header;
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
         "render_body" >:: test_render_body;
         "response_render_all_has_sections" >:: test_response_render_all_has_sections;
         "response_render_headers_has_heading" >:: test_response_render_headers_has_heading;
         "render_headers" >:: test_render_headers;
         "render_all" >:: test_render_all;
         "pretty_print_json" >:: test_pretty_print_json;
         "extract_body_path" >:: test_extract_body_path;
         "extract_header" >:: test_extract_header;
         "inject_named_response" >:: test_inject_named_response;
         "named_buffer_name" >:: test_named_buffer_name;
         "slugged_buffer_name" >:: test_slugged_buffer_name;
         "filetype_mapping" >:: test_filetype_mapping;
       ]

let () = run_test_tt_main suite
