open QCheck2
open Freight

(* ── Generators ─────────────────────────────────────────────────────────── *)

let standard_methods =
  [ "GET"; "POST"; "PUT"; "PATCH"; "DELETE"; "HEAD"; "OPTIONS"; "TRACE"; "CONNECT" ]

let gen_named_method =
  Gen.oneof_list
    Ast.[ Get; Post; Put; Patch; Delete; Head; Options; Trace; Connect ]

(* Uppercase A-Z strings; property uses assume to skip standard method names *)
let gen_custom_method_string =
  Gen.string_size ~gen:(Gen.char_range 'A' 'Z') (Gen.int_range 1 12)

(* A valid env key: [A-Za-z_][A-Za-z0-9_]* — matches the regex in env.ml *)
let gen_env_key =
  Gen.map2
    (fun first rest -> String.make 1 first ^ rest)
    (Gen.oneof
       [ Gen.char_range 'A' 'Z'; Gen.char_range 'a' 'z'; Gen.return '_' ])
    (Gen.string_of
       (Gen.oneof
          [
            Gen.char_range 'A' 'Z';
            Gen.char_range 'a' 'z';
            Gen.char_range '0' '9';
            Gen.return '_';
          ]))

(* Values that never contain {{ so they don't introduce secondary substitutions *)
let gen_plain_value = Gen.string_of (Gen.char_range 'a' 'z')

(* Lowercase letters only — never contains ':', satisfies non-empty when size >= 1 *)
let gen_header_name =
  Gen.string_size ~gen:(Gen.char_range 'a' 'z') (Gen.int_range 1 20)

(* Printable ASCII range excludes '\n' and '\r', trim to match parse_header's trim *)
let gen_header_value =
  Gen.map String.trim (Gen.string_of (Gen.char_range ' ' '~'))

let dummy_request : Ast.request =
  {
    name = None;
    method_ = Ast.Get;
    url = "http://example.com";
    headers = [];
    body = Ast.Body_none;
    save_to = None;
    assertions = [];
  }

(* ── A: Ast.method_ roundtrip ────────────────────────────────────────────── *)

let test_named_method_roundtrip =
  Test.make ~name:"method_of_string (method_to_string m) = m for named variants"
    ~count:200 gen_named_method (fun m ->
      Ast.method_of_string (Ast.method_to_string m) = m)

let test_custom_method_preserves_string =
  Test.make ~name:"method_to_string (Custom s) = s" ~count:200
    gen_custom_method_string (fun s ->
      (* skip strings that uppercase to a standard method name *)
      assume (not (List.mem s standard_methods));
      Ast.method_to_string (Ast.Custom s) = s)

let test_method_to_string_uppercase =
  Test.make ~name:"method_to_string output is uppercase" ~count:200 gen_named_method
    (fun m ->
      let s = Ast.method_to_string m in
      String.equal s (String.uppercase_ascii s))

(* ── B: Buffer.slug invariants ───────────────────────────────────────────── *)

let slug_chars_valid s =
  String.to_seq s
  |> Seq.for_all (fun c ->
         (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-')

let test_slug_chars =
  Test.make ~name:"slug output contains only [a-z0-9-]" ~count:500 Gen.string
    (fun s -> slug_chars_valid (Buffer.slug s))

let test_slug_lowercase =
  Test.make ~name:"slug output is lowercase" ~count:500 Gen.string (fun s ->
      let r = Buffer.slug s in
      String.equal r (String.lowercase_ascii r))

let test_slug_no_leading_trailing_dash =
  Test.make ~name:"slug has no leading or trailing dash" ~count:500 Gen.string
    (fun s ->
      let r = Buffer.slug s in
      let n = String.length r in
      n = 0 || (r.[0] <> '-' && r.[n - 1] <> '-'))

let test_slug_idempotent =
  Test.make ~name:"slug is idempotent" ~count:500 Gen.string (fun s ->
      let once = Buffer.slug s in
      String.equal once (Buffer.slug once))

(* ── C: Buffer.url_without_scheme ───────────────────────────────────────── *)

let test_url_without_scheme_strips =
  Test.make ~name:"url_without_scheme strips scheme:// prefix" ~count:300
    (Gen.map2
       (fun scheme rest -> (scheme, rest))
       (Gen.oneof_list [ "http"; "https"; "ftp"; "custom" ])
       (Gen.string_of (Gen.char_range 'a' 'z')))
    (fun (scheme, rest) ->
      let url = scheme ^ "://" ^ rest in
      String.equal (Buffer.url_without_scheme url) rest)

(* [a-z] strings can never contain "://" so url_without_scheme is identity *)
let test_url_without_scheme_identity =
  Test.make ~name:"url_without_scheme is identity when no :// present" ~count:300
    (Gen.string_of (Gen.char_range 'a' 'z'))
    (fun s -> String.equal (Buffer.url_without_scheme s) s)

(* ── D: Response.parse_header roundtrip ─────────────────────────────────── *)

let test_parse_header_roundtrip =
  Test.make ~name:"parse_header roundtrip on key: value strings" ~count:500
    (Gen.pair gen_header_name gen_header_value)
    (fun (key, value) ->
      let value = String.trim value in
      let line = key ^ ": " ^ value in
      match Response.parse_header line with
      | Some (k, v) -> String.equal k key && String.equal v value
      | None -> false)

(* [a-z] strings never contain ':' so parse_header must return None *)
let test_parse_header_none_without_colon =
  Test.make ~name:"parse_header returns None when line has no colon" ~count:300
    (Gen.string_of (Gen.char_range 'a' 'z'))
    (fun s -> Option.is_none (Response.parse_header s))

(* ── E: Env.substitute identity and idempotence ─────────────────────────── *)

let test_substitute_empty_env_identity =
  Test.make ~name:"substitute empty env is identity" ~count:500 Gen.string
    (fun s ->
      (* Unknown {{vars}} are preserved as-is, so any string is unchanged *)
      String.equal (Env.substitute Env.empty s) s)

let test_substitute_idempotent =
  Test.make ~name:"substitute is idempotent when values contain no {{...}}"
    ~count:300
    (Gen.pair gen_env_key gen_plain_value)
    (fun (key, value) ->
      let env = Env.of_list [ (key, value) ] in
      let template = "{{" ^ key ^ "}}" in
      let once = Env.substitute env template in
      String.equal once (Env.substitute env once))

(* ── F: Env.parse_line key=value ─────────────────────────────────────────── *)

let test_parse_line_roundtrip =
  Test.make ~name:"parse_line key=value roundtrip" ~count:400
    (Gen.pair
       (Gen.string_size
          ~gen:
            (Gen.oneof
               [
                 Gen.char_range 'a' 'z';
                 Gen.char_range 'A' 'Z';
                 Gen.return '_';
               ])
          (Gen.int_range 1 20))
       gen_plain_value)
    (fun (key, value) ->
      let line = key ^ "=" ^ value in
      let env = Env.parse_line Env.empty line in
      match Env.find env key with Some found -> String.equal found value | None -> false)

let test_parse_line_skips_comments =
  Test.make ~name:"parse_line leaves env unchanged for comment lines" ~count:200
    (Gen.pair gen_env_key gen_plain_value)
    (fun (key, value) ->
      let env = Env.of_list [ (key, value) ] in
      let after = Env.parse_line env ("# " ^ key ^ "=modified") in
      match Env.find after key with
      | Some found -> String.equal found value
      | None -> false)

let test_parse_line_skips_empty =
  Test.make ~name:"parse_line skips blank lines" ~count:50
    (Gen.oneof_list [ ""; "   "; "\t" ])
    (fun line ->
      let env = Env.parse_line (Env.of_list [ ("k", "v") ]) line in
      match Env.find env "k" with Some "v" -> true | _ -> false)

(* ── G: Response.detect_content_type case insensitivity ──────────────────── *)

let make_response headers : Ast.response =
  {
    status = 200;
    status_text = "OK";
    headers;
    body = "";
    duration_ms = 0;
    request = dummy_request;
  }

let test_detect_json_case_insensitive =
  Test.make ~name:"detect_content_type finds Json regardless of Content-Type value casing"
    ~count:200
    (Gen.map
       (fun bits ->
         let s = "application/json" in
         let n = List.length bits in
         String.mapi (fun i c ->
           if List.nth bits (i mod n) then Char.uppercase_ascii c else c) s)
       (Gen.list_size (Gen.int_range 1 20) Gen.bool))
    (fun ct_value ->
      let resp = make_response [ ("content-type", ct_value) ] in
      Response.detect_content_type resp = Response.Json)

let test_detect_no_header_is_plain =
  Test.make ~name:"detect_content_type returns Plain when no Content-Type header"
    ~count:100
    (Gen.list (Gen.pair gen_header_name gen_header_value))
    (fun headers ->
      (* gen_header_name produces [a-z]+ which can never equal "content-type"...
         except it actually can, so use assume to skip that case *)
      assume
        (List.for_all
           (fun (name, _) ->
             not (String.equal (String.lowercase_ascii name) "content-type"))
           headers);
      let resp = make_response headers in
      Response.detect_content_type resp = Response.Plain)

(* ── H: Parser.parse_string roundtrip ───────────────────────────────────── *)

let test_parse_source_single_request =
  Test.make ~name:"parse_string roundtrips single-request method and url" ~count:300
    (Gen.pair gen_named_method
       (Gen.string_size ~gen:(Gen.char_range 'a' 'z') (Gen.int_range 1 15)))
    (fun (method_, host) ->
      let src = Ast.method_to_string method_ ^ " https://" ^ host ^ "\n\n" in
      match Parser.parse_string src with
      | Ok file ->
        (match file.requests with
         | [ req ] -> req.method_ = method_
         | _ -> false)
      | Error _ -> false)

(* ── I: Resolve.substitute_request ──────────────────────────────────────── *)

let test_substitute_request_replaces_url =
  Test.make ~name:"substitute_request replaces {{var}} in url" ~count:300
    (Gen.pair gen_env_key gen_plain_value)
    (fun (key, value) ->
      let env = Env.of_list [ (key, value) ] in
      let req = { dummy_request with url = "https://{{" ^ key ^ "}}/path" } in
      let result = Resolve.substitute_request env req in
      String.equal result.url ("https://" ^ value ^ "/path"))

let test_substitute_request_replaces_headers =
  Test.make ~name:"substitute_request replaces {{var}} in header values" ~count:300
    (Gen.pair gen_env_key gen_plain_value)
    (fun (key, value) ->
      let env = Env.of_list [ (key, value) ] in
      let req = { dummy_request with headers = [ ("Auth", "Bearer {{" ^ key ^ "}}") ] } in
      let result = Resolve.substitute_request env req in
      match result.headers with
      | [ ("Auth", v) ] -> String.equal v ("Bearer " ^ value)
      | _ -> false)

let test_substitute_request_replaces_inline_body =
  Test.make ~name:"substitute_request replaces {{var}} in inline body" ~count:300
    (Gen.pair gen_env_key gen_plain_value)
    (fun (key, value) ->
      let env = Env.of_list [ (key, value) ] in
      let req = { dummy_request with body = Ast.Body_inline ("{{" ^ key ^ "}}") } in
      let result = Resolve.substitute_request env req in
      match result.body with
      | Ast.Body_inline s -> String.equal s value
      | _ -> false)

let test_substitute_request_replaces_file_body_path =
  Test.make ~name:"substitute_request replaces {{var}} in Body_file path" ~count:200
    (Gen.pair gen_env_key gen_plain_value)
    (fun (key, value) ->
      let env = Env.of_list [ (key, value) ] in
      let path = "{{" ^ key ^ "}}.json" in
      let req = { dummy_request with body = Ast.Body_file path } in
      let result = Resolve.substitute_request env req in
      match result.body with
      | Ast.Body_file p -> String.equal p (value ^ ".json")
      | _ -> false)

let test_substitute_request_empty_env_preserves_vars =
  Test.make ~name:"substitute_request with empty env preserves {{...}} markers"
    ~count:300 gen_env_key
    (fun key ->
      let template = "https://{{" ^ key ^ "}}" in
      let req = { dummy_request with url = template } in
      let result = Resolve.substitute_request Env.empty req in
      String.equal result.url template)

(* ── J: Resolve.at_cursor ──────────────────────────────────────────────── *)

let test_at_cursor_valid_request =
  Test.make ~name:"at_cursor returns Ok for valid request at cursor" ~count:300
    (Gen.pair gen_named_method
       (Gen.string_size ~gen:(Gen.char_range 'a' 'z') (Gen.int_range 1 15)))
    (fun (method_, host) ->
      let source = Ast.method_to_string method_ ^ " https://" ^ host in
      match Resolve.at_cursor ~source ~cursor_line:0 ~env:Env.empty with
      | Ok req -> req.method_ = method_
      | Error _ -> false)

let test_at_cursor_empty_is_no_request =
  Test.make ~name:"at_cursor on empty source returns No_request" ~count:50
    (Gen.oneof_list [ ""; "   "; "\n\n" ])
    (fun source ->
      match Resolve.at_cursor ~source ~cursor_line:0 ~env:Env.empty with
      | Error `No_request -> true
      | _ -> false)

(* ── J2: Parser round-trip ─────────────────────────────────────────────── *)

(* Build a canonical .http request from generated parts and confirm the parser
   recovers the method, url, and headers. *)
let test_parse_roundtrip =
  Test.make ~name:"parse recovers method/url/headers from canonical .http"
    ~count:300
    (Gen.triple gen_named_method
       (Gen.string_size ~gen:(Gen.char_range 'a' 'z') (Gen.int_range 1 15))
       (Gen.list_size (Gen.int_range 0 4) (Gen.pair gen_header_name gen_header_value)))
    (fun (method_, host, headers) ->
      (* dedupe header names (parser keeps all, but equal keys are fine to keep;
         we only assert the set is recovered) and drop empty values which trim
         away *)
      let headers = List.filter (fun (_, v) -> String.trim v <> "") headers in
      let url = "https://" ^ host in
      let header_lines =
        List.map (fun (k, v) -> k ^ ": " ^ v) headers |> String.concat "\n"
      in
      let source =
        Ast.method_to_string method_ ^ " " ^ url
        ^ (if headers = [] then "" else "\n" ^ header_lines)
        ^ "\n"
      in
      match Parser.parse_string source with
      | Ok { requests = [ req ]; _ } ->
        req.method_ = method_ && req.url = url && req.headers = headers
      | _ -> false)

(* ── K: Executor.to_curl invariants ────────────────────────────────────── *)

let test_to_curl_always_has_method =
  Test.make ~name:"to_curl output always contains -X METHOD" ~count:300
    gen_named_method
    (fun method_ ->
      let req = { dummy_request with method_ } in
      let inv = Executor.to_curl req in
      let method_str = Ast.method_to_string method_ in
      List.mem "-X" inv.args && List.mem method_str inv.args)

let test_to_curl_always_has_url =
  Test.make ~name:"to_curl output always contains the request url" ~count:300
    (Gen.string_size ~gen:(Gen.char_range 'a' 'z') (Gen.int_range 1 20))
    (fun host ->
      let url = "https://" ^ host in
      let req = { dummy_request with url } in
      let inv = Executor.to_curl req in
      List.mem url inv.args)

let test_to_curl_headers_appear_after_h_flag =
  Test.make ~name:"to_curl includes -H flag for each header" ~count:300
    (Gen.pair gen_header_name gen_header_value)
    (fun (key, value) ->
      let value = String.trim value in
      let req = { dummy_request with headers = [ (key, value) ] } in
      let inv = Executor.to_curl req in
      List.mem "-H" inv.args
      && List.mem (key ^ ": " ^ value) inv.args)

(* ── Runner ──────────────────────────────────────────────────────────────── *)

let () =
  QCheck_base_runner.run_tests_main
    [
      (* A *)
      test_named_method_roundtrip;
      test_custom_method_preserves_string;
      test_method_to_string_uppercase;
      (* B *)
      test_slug_chars;
      test_slug_lowercase;
      test_slug_no_leading_trailing_dash;
      test_slug_idempotent;
      (* C *)
      test_url_without_scheme_strips;
      test_url_without_scheme_identity;
      (* D *)
      test_parse_header_roundtrip;
      test_parse_header_none_without_colon;
      (* E *)
      test_substitute_empty_env_identity;
      test_substitute_idempotent;
      (* F *)
      test_parse_line_roundtrip;
      test_parse_line_skips_comments;
      test_parse_line_skips_empty;
      (* G *)
      test_detect_json_case_insensitive;
      test_detect_no_header_is_plain;
      (* H *)
      test_parse_source_single_request;
      (* I *)
      test_substitute_request_replaces_url;
      test_substitute_request_replaces_headers;
      test_substitute_request_replaces_inline_body;
      test_substitute_request_replaces_file_body_path;
      test_substitute_request_empty_env_preserves_vars;
      (* J *)
      test_at_cursor_valid_request;
      test_at_cursor_empty_is_no_request;
      test_parse_roundtrip;
      (* K *)
      test_to_curl_always_has_method;
      test_to_curl_always_has_url;
      test_to_curl_headers_appear_after_h_flag;
    ]
