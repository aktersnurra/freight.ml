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
       ]

let () = run_test_tt_main suite
