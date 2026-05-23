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
       ]

let () = run_test_tt_main suite
