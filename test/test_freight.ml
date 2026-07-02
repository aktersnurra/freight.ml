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
      save_to = None;
      assertions = [];
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
      save_to = None;
      assertions = [];
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
      save_to = None;
      assertions = [];
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
      save_to = None;
      assertions = [];
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
         save_to = None;
         assertions = [];
       });
  assert_empty_header_name
    (make_response
       {
         Freight.Ast.name = None;
         method_ = Freight.Ast.Get;
         url = "https://example.test";
         headers = [ (" \t", "value") ];
         body = Freight.Ast.Body_none;
         save_to = None;
         assertions = [];
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
      save_to = None;
      assertions = [];
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

(* Two requests separated by ###, with a leading comment block and a trailing
   comment-only block. Line indices (0-based) for request_at_cursor:
     0: # first
     1: GET https://one.test    <- request 1 line
     2: Accept: text/plain       <- request 1 header
     3: (blank)
     4: ###
     5: # second
     6: POST https://two.test    <- request 2 line
     7: (blank)
     8: ###
     9: # trailing comment only  <- no request line in this block *)
let cursor_source =
  String.concat "\n"
    [ "# first"
    ; "GET https://one.test"
    ; "Accept: text/plain"
    ; ""
    ; "###"
    ; "# second"
    ; "POST https://two.test"
    ; ""
    ; "###"
    ; "# trailing comment only"
    ]

let test_request_at_cursor_on_request_line _ =
  match Freight.Parser.request_at_cursor cursor_source 1 with
  | Some request -> assert_equal "https://one.test" request.Freight.Ast.url
  | None -> assert_failure "expected first request"

let test_request_at_cursor_on_header_line _ =
  match Freight.Parser.request_at_cursor cursor_source 2 with
  | Some request -> assert_equal "https://one.test" request.Freight.Ast.url
  | None -> assert_failure "expected first request"

let test_request_at_cursor_second_request _ =
  match Freight.Parser.request_at_cursor cursor_source 6 with
  | Some request -> assert_equal "https://two.test" request.Freight.Ast.url
  | None -> assert_failure "expected second request"

let test_request_at_cursor_leading_comment_is_none _ =
  assert_equal None (Freight.Parser.request_at_cursor cursor_source 0)

let test_request_at_cursor_blank_gap_is_none _ =
  (* line 3 is the blank line after request 1's content *)
  assert_equal None (Freight.Parser.request_at_cursor cursor_source 3)

let test_request_at_cursor_trailing_comment_is_none _ =
  (* line 9 is a comment-only block after the last request *)
  assert_equal None (Freight.Parser.request_at_cursor cursor_source 9)

let test_parse_save_redirect _ =
  let file =
    parse_ok "GET https://example.com/template\n\n>> ./out.xlsx\n"
  in
  match file.requests with
  | [ request ] ->
      assert_equal
        (Some { Freight.Ast.save_path = Some "./out.xlsx"; overwrite = false })
        request.Freight.Ast.save_to;
      assert_equal Freight.Ast.Body_none request.body
  | _ -> assert_failure "expected one request"

let test_parse_save_redirect_overwrite _ =
  let file = parse_ok "GET https://example.com/template\n\n>>! ./out.xlsx\n" in
  match file.requests with
  | [ request ] ->
      assert_equal
        (Some { Freight.Ast.save_path = Some "./out.xlsx"; overwrite = true })
        request.Freight.Ast.save_to
  | _ -> assert_failure "expected one request"

let test_parse_save_redirect_no_path _ =
  let file = parse_ok "GET https://example.com/template\n\n>>\n" in
  match file.requests with
  | [ request ] ->
      assert_equal
        (Some { Freight.Ast.save_path = None; overwrite = false })
        request.Freight.Ast.save_to
  | _ -> assert_failure "expected one request"

let test_parse_save_redirect_with_body _ =
  let file =
    parse_ok
      "POST https://example.com/x\nContent-Type: application/json\n\n{\"x\":1}\n\n>> ./out.json\n"
  in
  match file.requests with
  | [ request ] ->
      assert_equal (Freight.Ast.Body_inline "{\"x\":1}") request.body;
      assert_equal
        (Some { Freight.Ast.save_path = Some "./out.json"; overwrite = false })
        request.Freight.Ast.save_to
  | _ -> assert_failure "expected one request"

let test_to_curl_save_uses_o_and_dump _ =
  let file = parse_ok "GET https://example.com/template\n\n>> ./out.xlsx\n" in
  match file.requests with
  | [ request ] ->
      let invocation = Freight.Executor.to_curl request in
      assert_bool "dumps headers to stdout"
        (List.mem "-D" invocation.args && List.mem "-" invocation.args);
      assert_bool "writes body to file with -o"
        (List.mem "-o" invocation.args && List.mem "./out.xlsx" invocation.args);
      assert_bool "does not use -i" (not (List.mem "-i" invocation.args))
  | _ -> assert_failure "expected one request"

let test_to_curl_no_save_uses_i _ =
  let file = parse_ok "GET https://example.com/template\n" in
  match file.requests with
  | [ request ] ->
      let invocation = Freight.Executor.to_curl request in
      assert_bool "uses -i" (List.mem "-i" invocation.args);
      assert_bool "no -o" (not (List.mem "-o" invocation.args))
  | _ -> assert_failure "expected one request"

(* Golden snapshots: pin the ENTIRE curl arg vector for each request shape.
   Presence checks (List.mem) miss flag reordering, a lost -o, or a spurious
   extra arg; these full-vector assertions turn any such drift into a diff. *)
let curl_args ?name ?(method_ = Freight.Ast.Get) ?(headers = []) ?(save_to = None)
    ~url body =
  (Freight.Executor.to_curl
     { Freight.Ast.name; method_; url; headers; body; save_to; assertions = [] })
    .Freight.Executor.args

let print_args args = "[ " ^ String.concat " ; " (List.map (Printf.sprintf "%S") args) ^ " ]"

let assert_args expected actual =
  assert_equal ~printer:print_args expected actual

let test_golden_curl_inline_body _ =
  assert_args
    [ "-i"; "-s"; "-X"; "POST"; "-H"; "Content-Type: application/json"
    ; "--data-binary"; {|{"x":1}|}; "https://api.test/x"
    ; "-w"; "\n%{http_code}\n%{time_total}" ]
    (curl_args ~method_:Freight.Ast.Post
       ~headers:[ ("Content-Type", "application/json") ]
       ~url:"https://api.test/x"
       (Freight.Ast.Body_inline {|{"x":1}|}))

let test_golden_curl_get_no_body _ =
  assert_args
    [ "-i"; "-s"; "-X"; "GET"; "https://api.test/"
    ; "-w"; "\n%{http_code}\n%{time_total}" ]
    (curl_args ~url:"https://api.test/" Freight.Ast.Body_none)

let test_golden_curl_file_body_post _ =
  assert_args
    [ "-i"; "-s"; "-X"; "POST"; "--data-binary"; "@payload.json"
    ; "https://api.test/x"; "-w"; "\n%{http_code}\n%{time_total}" ]
    (curl_args ~method_:Freight.Ast.Post ~url:"https://api.test/x"
       (Freight.Ast.Body_file "payload.json"))

let test_golden_curl_file_body_put _ =
  assert_args
    [ "-i"; "-s"; "-X"; "PUT"; "-T"; "payload.json"
    ; "https://api.test/x"; "-w"; "\n%{http_code}\n%{time_total}" ]
    (curl_args ~method_:Freight.Ast.Put ~url:"https://api.test/x"
       (Freight.Ast.Body_file "payload.json"))

let test_golden_curl_multipart _ =
  assert_args
    [ "-i"; "-s"; "-X"; "POST"
    ; "-F"; "file=@./f.xlsx;type=application/vnd.ms-excel;filename=f.xlsx"
    ; "-F"; "note=hello"
    ; "https://api.test/imports"; "-w"; "\n%{http_code}\n%{time_total}" ]
    (curl_args ~method_:Freight.Ast.Post ~url:"https://api.test/imports"
       (Freight.Ast.Body_multipart
          [ { part_name = "file"
            ; filename = Some "f.xlsx"
            ; content_type = Some "application/vnd.ms-excel"
            ; content = Freight.Ast.Part_file "./f.xlsx"
            }
          ; { part_name = "note"
            ; filename = None
            ; content_type = None
            ; content = Freight.Ast.Part_text "hello"
            } ]))

let test_golden_curl_save_explicit_path _ =
  assert_args
    [ "-D"; "-"; "-o"; "./out.bin"; "-s"; "-X"; "GET"
    ; "https://api.test/dl"; "-w"; "\n%{http_code}\n%{time_total}" ]
    (curl_args ~url:"https://api.test/dl"
       ~save_to:(Some { Freight.Ast.save_path = Some "./out.bin"; overwrite = false })
       Freight.Ast.Body_none)

let test_golden_curl_save_no_path_uses_i _ =
  assert_args
    [ "-i"; "-s"; "-X"; "GET"; "https://api.test/dl"
    ; "-w"; "\n%{http_code}\n%{time_total}" ]
    (curl_args ~url:"https://api.test/dl"
       ~save_to:(Some { Freight.Ast.save_path = None; overwrite = false })
       Freight.Ast.Body_none)

let test_substitute_request_expands_save_path _ =
  let env = Freight.Env.of_list [ ("OUT", "/tmp/out") ] in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://example.com"
    ; headers = []
    ; body = Freight.Ast.Body_none
    ; save_to = Some { Freight.Ast.save_path = Some "{{OUT}}/file.bin"; overwrite = true }
    ; assertions = []
    }
  in
  let resolved = Freight.Resolve.substitute_request env request in
  assert_equal
    (Some { Freight.Ast.save_path = Some "/tmp/out/file.bin"; overwrite = true })
    resolved.save_to

let multipart_source =
  String.concat "\n"
    [ "# @name upload"
    ; "POST https://api.example.com/imports"
    ; "Content-Type: multipart/form-data; boundary=boundary"
    ; ""
    ; "--boundary"
    ; "Content-Disposition: form-data; name=\"file\"; filename=\"filled.xlsx\""
    ; "Content-Type: application/vnd.ms-excel"
    ; ""
    ; "< ./filled.xlsx"
    ; "--boundary"
    ; "Content-Disposition: form-data; name=\"note\""
    ; ""
    ; "hello from freight"
    ; "--boundary--"
    ]

let test_parse_multipart_body _ =
  let file = parse_ok multipart_source in
  match file.requests with
  | [ request ] -> (
      (* the multipart Content-Type header is dropped so curl owns the boundary *)
      assert_equal [] request.Freight.Ast.headers;
      match request.body with
      | Freight.Ast.Body_multipart [ file_part; note_part ] ->
          assert_equal "file" file_part.Freight.Ast.part_name;
          assert_equal (Some "filled.xlsx") file_part.filename;
          assert_equal (Some "application/vnd.ms-excel") file_part.content_type;
          assert_equal (Freight.Ast.Part_file "./filled.xlsx") file_part.content;
          assert_equal "note" note_part.Freight.Ast.part_name;
          assert_equal None note_part.filename;
          assert_equal (Freight.Ast.Part_text "hello from freight") note_part.content
      | _ -> assert_failure "expected two multipart parts")
  | _ -> assert_failure "expected one request"

let test_to_curl_multipart _ =
  let file = parse_ok multipart_source in
  match file.requests with
  | [ request ] ->
      let invocation = Freight.Executor.to_curl request in
      assert_bool "uses -F"
        (List.mem "-F" invocation.args);
      assert_bool "file part with type and filename"
        (List.mem
           "file=@./filled.xlsx;type=application/vnd.ms-excel;filename=filled.xlsx"
           invocation.args);
      assert_bool "text part"
        (List.mem "note=hello from freight" invocation.args);
      assert_bool "does not emit raw multipart content-type header"
        (not
           (List.mem "Content-Type: multipart/form-data; boundary=boundary"
              invocation.args));
      assert_bool "does not use --data-binary"
        (not (List.mem "--data-binary" invocation.args))
  | _ -> assert_failure "expected one request"

let test_substitute_request_expands_multipart _ =
  let env = Freight.Env.of_list [ ("DIR", "/tmp"); ("NOTE", "hi") ] in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Post
    ; url = "https://api.example.com/imports"
    ; headers = []
    ; body =
        Freight.Ast.Body_multipart
          [ { part_name = "file"
            ; filename = Some "x.txt"
            ; content_type = None
            ; content = Freight.Ast.Part_file "{{DIR}}/x.txt"
            }
          ; { part_name = "note"
            ; filename = None
            ; content_type = None
            ; content = Freight.Ast.Part_text "{{NOTE}}"
            }
          ]
    ; save_to = None
    ; assertions = []
    }
  in
  match (Freight.Resolve.substitute_request env request).body with
  | Freight.Ast.Body_multipart [ file_part; note_part ] ->
      assert_equal (Freight.Ast.Part_file "/tmp/x.txt") file_part.content;
      assert_equal (Freight.Ast.Part_text "hi") note_part.content
  | _ -> assert_failure "expected two parts"

let test_env_overlay_over_wins _ =
  let base = Freight.Env.of_list [ ("host", "base"); ("only_base", "b") ] in
  let over = Freight.Env.of_list [ ("host", "over"); ("only_over", "o") ] in
  let merged = Freight.Env.overlay ~base ~over in
  assert_equal (Some "over") (Freight.Env.find merged "host");
  assert_equal (Some "b") (Freight.Env.find merged "only_base");
  assert_equal (Some "o") (Freight.Env.find merged "only_over")

let test_unresolved_request_reports_missing _ =
  let env = Freight.Env.of_list [ ("host", "https://api.example.com") ] in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Post
    ; url = "{{host}}/imports/{{preview.response.body.id}}/apply"
    ; headers = [ ("X-Api-Key", "{{API_KEY}}") ]
    ; body = Freight.Ast.Body_inline "{ \"hash\": \"{{preview.response.body.hash}}\" }"
    ; save_to = None
    ; assertions = []
    }
  in
  assert_equal
    [ "API_KEY"; "preview.response.body.hash"; "preview.response.body.id" ]
    (Freight.Resolve.unresolved_request env request)

let test_unresolved_request_empty_when_resolved _ =
  let env = Freight.Env.of_list [ ("host", "https://api.example.com") ] in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "{{host}}/ping"
    ; headers = []
    ; body = Freight.Ast.Body_none
    ; save_to = None
    ; assertions = []
    }
  in
  assert_equal [] (Freight.Resolve.unresolved_request env request)

let test_substitute_request_expands_body_file_path _ =
  let env = Freight.Env.of_list [ ("DIR", "/tmp/payloads") ] in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Post
    ; url = "https://api.example.com/upload"
    ; headers = []
    ; body = Freight.Ast.Body_file "{{DIR}}/payload.json"
    ; save_to = None
    ; assertions = []
    }
  in
  let resolved = Freight.Resolve.substitute_request env request in
  assert_equal (Freight.Ast.Body_file "/tmp/payloads/payload.json") resolved.body

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
    save_to = None;
    assertions = [];
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
      save_to = None;
      assertions = [];
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
      save_to = None;
      assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
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
    save_to = None;
    assertions = [];
  } in
  let result = Freight.Ast.apply_host_header request in
  assert_equal "https://api.example.com/ping" result.Freight.Ast.url;
  assert_equal [] result.Freight.Ast.headers

let test_json_path_parse_dotted _ =
  assert_equal [ Freight.Json_path.Field "data"; Field "id" ]
    (Freight.Json_path.parse "data.id")

let test_json_path_parse_index_bracket _ =
  assert_equal
    [ Freight.Json_path.Field "items"; Index 0; Field "id" ]
    (Freight.Json_path.parse "items[0].id")

let test_json_path_parse_index_dotted _ =
  assert_equal
    [ Freight.Json_path.Field "items"; Index 2; Field "id" ]
    (Freight.Json_path.parse "items.2.id")

let test_json_path_lookup_nested _ =
  let json = Yojson.Safe.from_string {|{"data":{"id":"abc"}}|} in
  assert_equal (Some "abc")
    (Freight.Json_path.lookup json (Freight.Json_path.parse "data.id"))

let test_json_path_lookup_array _ =
  let json = Yojson.Safe.from_string {|{"items":[{"id":7},{"id":8}]}|} in
  assert_equal (Some "8")
    (Freight.Json_path.lookup json (Freight.Json_path.parse "items[1].id"))

let test_json_path_parse_never_raises _ =
  (* A malformed path/reference is user data — parse must be total, never raise. *)
  List.iter
    (fun bad ->
      match Freight.Json_path.parse bad with
      | _ -> ()
      | exception e ->
        assert_failure
          (Printf.sprintf "parse %S raised %s" bad (Printexc.to_string e)))
    [ "items[abc]"; "items[]"; "a[1x]"; "["; "]"; "x[99999999999999999999]"; "a..b" ]

let test_json_path_bad_index_is_no_match _ =
  (* items[abc] does not resolve to an array element; it yields None, which the
     caller surfaces as an unresolved variable (fail-fast), not a crash. *)
  let json = Yojson.Safe.from_string {|{"items":[{"id":1}]}|} in
  assert_equal None
    (Freight.Json_path.lookup json (Freight.Json_path.parse "items[abc].id"))

let test_json_path_lookup_whole_float _ =
  (* A JSON float like 9.0 must render as valid JSON "9.0", not OCaml's "9." *)
  let json = Yojson.Safe.from_string {|{"price":9.0}|} in
  assert_equal (Some "9.0")
    (Freight.Json_path.lookup json (Freight.Json_path.parse "price"))

let test_json_path_lookup_fractional_float _ =
  let json = Yojson.Safe.from_string {|{"price":9.9}|} in
  assert_equal (Some "9.9")
    (Freight.Json_path.lookup json (Freight.Json_path.parse "price"))

let test_json_path_lookup_large_float _ =
  let json = Yojson.Safe.from_string {|{"total":1234567.0}|} in
  assert_equal (Some "1234567.0")
    (Freight.Json_path.lookup json (Freight.Json_path.parse "total"))

let test_json_path_lookup_missing _ =
  let json = Yojson.Safe.from_string {|{"data":{"id":"abc"}}|} in
  assert_equal None
    (Freight.Json_path.lookup json (Freight.Json_path.parse "data.missing"))

let test_json_path_lookup_non_scalar_leaf _ =
  let json = Yojson.Safe.from_string {|{"data":{"id":"abc"}}|} in
  assert_equal None
    (Freight.Json_path.lookup json (Freight.Json_path.parse "data"))

let test_resolver_first_source_wins _ =
  let a = fun ref -> if ref = "x" then Some "A" else None in
  let b = fun ref -> if ref = "x" then Some "B" else None in
  let r = Freight.Resolver.make [ a; b ] in
  assert_equal "A" (Freight.Resolver.resolve r "{{x}}")

let test_resolver_falls_through _ =
  let a = fun ref -> if ref = "x" then Some "A" else None in
  let b = fun ref -> if ref = "y" then Some "B" else None in
  let r = Freight.Resolver.make [ a; b ] in
  assert_equal "A-B" (Freight.Resolver.resolve r "{{x}}-{{y}}")

let test_resolver_unknown_left_literal _ =
  let r = Freight.Resolver.make [ (fun _ -> None) ] in
  assert_equal "{{ missing }}" (Freight.Resolver.resolve r "{{ missing }}")

let test_resolver_trims_ref _ =
  let seen = ref "" in
  let r = Freight.Resolver.make [ (fun ref -> seen := ref; Some "v") ] in
  ignore (Freight.Resolver.resolve r "{{  spaced  }}");
  assert_equal "spaced" !seen

let test_resolver_unresolved _ =
  let a = fun ref -> if ref = "x" then Some "A" else None in
  let r = Freight.Resolver.make [ a ] in
  assert_equal [ "y"; "z" ]
    (Freight.Resolver.unresolved r "{{x}} {{z}} {{y}} {{z}}")

let test_env_source_resolves_key _ =
  let env = Freight.Env.of_list [ ("host", "example.com") ] in
  let src = Freight.Env.source env in
  assert_equal (Some "example.com") (src "host");
  assert_equal None (src "missing")

let store_response ~body ~headers =
  { Freight.Ast.status = 200
  ; status_text = "OK"
  ; headers
  ; body
  ; duration_ms = 1
  ; request =
      { Freight.Ast.name = None
      ; method_ = Freight.Ast.Get
      ; url = "https://example.com"
      ; headers = []
      ; body = Freight.Ast.Body_none
      ; save_to = None
      ; assertions = []
      }
  }

let test_response_store_top_level_body _ =
  let resp = store_response ~body:{|{"token":"abc"}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "abc") (src "login.response.body.token")

let test_response_store_nested_body _ =
  let resp = store_response ~body:{|{"data":{"id":"xyz"}}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "xyz") (src "login.response.body.data.id")

let test_response_store_array_body _ =
  let resp = store_response ~body:{|{"items":[{"id":1},{"id":2}]}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"list" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "2") (src "list.response.body.items[1].id")

let test_response_store_header _ =
  let resp = store_response ~body:"" ~headers:[ ("X-Request-Id", "req-1") ] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal (Some "req-1") (src "login.response.headers.X-Request-Id")

let test_response_store_missing_path _ =
  let resp = store_response ~body:{|{"token":"abc"}|} ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal None (src "login.response.body.nope")

let test_response_store_unknown_name _ =
  let src = Freight.Response_store.source Freight.Response_store.empty in
  assert_equal None (src "login.response.body.token")

let test_response_store_malformed_json _ =
  let resp = store_response ~body:"not json" ~headers:[] in
  let store = Freight.Response_store.record ~name:"login" resp Freight.Response_store.empty in
  let src = Freight.Response_store.source store in
  assert_equal None (src "login.response.body.token")

let test_substitute_request_with_resolver _ =
  let store = Freight.Response_store.record ~name:"login"
      (store_response ~body:{|{"data":{"id":"xyz"}}|} ~headers:[])
      Freight.Response_store.empty in
  let env = Freight.Env.of_list [ ("host", "example.com") ] in
  let resolver =
    Freight.Resolver.make
      [ Freight.Response_store.source store; Freight.Env.source env ]
  in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Post
    ; url = "https://{{host}}/items/{{login.response.body.data.id}}"
    ; headers = []
    ; body = Freight.Ast.Body_none
    ; save_to = None
    ; assertions = []
    }
  in
  let resolved = Freight.Resolve.substitute_request_r resolver request in
  assert_equal "https://example.com/items/xyz" resolved.Freight.Ast.url

let test_unresolved_request_with_resolver _ =
  let resolver = Freight.Resolver.make [] in
  let request =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://x/{{a}}"
    ; headers = [ ("H", "{{b}}") ]
    ; body = Freight.Ast.Body_none
    ; save_to = None
    ; assertions = []
    }
  in
  assert_equal [ "a"; "b" ]
    (Freight.Resolve.unresolved_request_r resolver request)

let suite =
  "freight"
  >::: [
         "env_source_resolves_key" >:: test_env_source_resolves_key;
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
         "request_at_cursor_on_request_line" >:: test_request_at_cursor_on_request_line;
         "request_at_cursor_on_header_line" >:: test_request_at_cursor_on_header_line;
         "request_at_cursor_second_request" >:: test_request_at_cursor_second_request;
         "request_at_cursor_leading_comment_is_none"
         >:: test_request_at_cursor_leading_comment_is_none;
         "request_at_cursor_blank_gap_is_none"
         >:: test_request_at_cursor_blank_gap_is_none;
         "request_at_cursor_trailing_comment_is_none"
         >:: test_request_at_cursor_trailing_comment_is_none;
         "parse_save_redirect" >:: test_parse_save_redirect;
         "parse_save_redirect_overwrite" >:: test_parse_save_redirect_overwrite;
         "parse_save_redirect_no_path" >:: test_parse_save_redirect_no_path;
         "parse_save_redirect_with_body" >:: test_parse_save_redirect_with_body;
         "to_curl_save_uses_o_and_dump" >:: test_to_curl_save_uses_o_and_dump;
         "to_curl_no_save_uses_i" >:: test_to_curl_no_save_uses_i;
         "golden_curl_inline_body" >:: test_golden_curl_inline_body;
         "golden_curl_get_no_body" >:: test_golden_curl_get_no_body;
         "golden_curl_file_body_post" >:: test_golden_curl_file_body_post;
         "golden_curl_file_body_put" >:: test_golden_curl_file_body_put;
         "golden_curl_multipart" >:: test_golden_curl_multipart;
         "golden_curl_save_explicit_path" >:: test_golden_curl_save_explicit_path;
         "golden_curl_save_no_path_uses_i" >:: test_golden_curl_save_no_path_uses_i;
         "substitute_request_expands_save_path" >:: test_substitute_request_expands_save_path;
         "parse_multipart_body" >:: test_parse_multipart_body;
         "to_curl_multipart" >:: test_to_curl_multipart;
         "substitute_request_expands_multipart" >:: test_substitute_request_expands_multipart;
         "env_overlay_over_wins" >:: test_env_overlay_over_wins;
         "unresolved_request_reports_missing" >:: test_unresolved_request_reports_missing;
         "unresolved_request_empty_when_resolved"
         >:: test_unresolved_request_empty_when_resolved;
         "substitute_request_expands_body_file_path"
         >:: test_substitute_request_expands_body_file_path;
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
         "named_buffer_name" >:: test_named_buffer_name;
         "slugged_buffer_name" >:: test_slugged_buffer_name;
         "filetype_mapping" >:: test_filetype_mapping;
         "json_path_parse_dotted" >:: test_json_path_parse_dotted;
         "json_path_parse_index_bracket" >:: test_json_path_parse_index_bracket;
         "json_path_parse_index_dotted" >:: test_json_path_parse_index_dotted;
         "json_path_lookup_nested" >:: test_json_path_lookup_nested;
         "json_path_lookup_array" >:: test_json_path_lookup_array;
         "json_path_parse_never_raises" >:: test_json_path_parse_never_raises;
         "json_path_bad_index_is_no_match" >:: test_json_path_bad_index_is_no_match;
         "json_path_lookup_whole_float" >:: test_json_path_lookup_whole_float;
         "json_path_lookup_fractional_float" >:: test_json_path_lookup_fractional_float;
         "json_path_lookup_large_float" >:: test_json_path_lookup_large_float;
         "json_path_lookup_missing" >:: test_json_path_lookup_missing;
         "json_path_lookup_non_scalar_leaf" >:: test_json_path_lookup_non_scalar_leaf;
         "resolver_first_source_wins" >:: test_resolver_first_source_wins;
         "resolver_falls_through" >:: test_resolver_falls_through;
         "resolver_unknown_left_literal" >:: test_resolver_unknown_left_literal;
         "resolver_trims_ref" >:: test_resolver_trims_ref;
         "resolver_unresolved" >:: test_resolver_unresolved;
         "response_store_top_level_body" >:: test_response_store_top_level_body;
         "response_store_nested_body" >:: test_response_store_nested_body;
         "response_store_array_body" >:: test_response_store_array_body;
         "response_store_header" >:: test_response_store_header;
         "response_store_missing_path" >:: test_response_store_missing_path;
         "response_store_unknown_name" >:: test_response_store_unknown_name;
         "response_store_malformed_json" >:: test_response_store_malformed_json;
         "substitute_request_with_resolver" >:: test_substitute_request_with_resolver;
         "unresolved_request_with_resolver" >:: test_unresolved_request_with_resolver;
       ]

let () = run_test_tt_main suite
