(* End-to-end tests: drive the REAL executor -> curl -> response parser ->
   response store -> resolver pipeline against a local recording mock server
   (see mock_server.ml). No external network. Unlike unit tests, these assert on
   what freight actually PUT ON THE WIRE (via captured requests) and what curl
   actually WROTE TO DISK — the seams where this project's bugs have lived. *)

open OUnit2

(* Run curl with the exact args our Executor generates, capture stdout. *)
let run_curl invocation =
  let args = Array.of_list ("curl" :: invocation.Freight.Executor.args) in
  let stdout_read, stdout_write = Unix.pipe () in
  let pid = Unix.create_process "curl" args Unix.stdin stdout_write Unix.stderr in
  Unix.close stdout_write;
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  let rec drain () =
    let n = Unix.read stdout_read chunk 0 4096 in
    if n > 0 then begin
      Buffer.add_subbytes buf chunk 0 n;
      drain ()
    end
  in
  drain ();
  Unix.close stdout_read;
  ignore (Unix.waitpid [] pid);
  Buffer.contents buf

let base_request ~url =
  { Freight.Ast.name = Some "seed"
  ; method_ = Freight.Ast.Get
  ; url
  ; headers = []
  ; body = Freight.Ast.Body_none
  ; save_to = None
  }

(* Run [request] against [server], returning the parsed response. *)
let run_against server request =
  let raw = run_curl (Freight.Executor.to_curl request) in
  Mock_server.stop server;
  match Freight.Response.parse_curl_output raw request with
  | Error e -> assert_failure ("parse failed: " ^ e)
  | Ok response -> response

let temp_file suffix =
  let path = Filename.temp_file "freight-e2e-" suffix in
  Sys.remove path;
  (* return a path that does not yet exist *)
  path

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

(* ── Happy path: GET + parse + top-level chaining ────────────────────────── *)

let test_e2e_get_and_parse _ =
  let server = Mock_server.start (fun _ -> Mock_server.json_response {|{"token":"abc","n":7}|}) in
  let response = run_against server (base_request ~url:(Mock_server.url server "/")) in
  assert_equal ~printer:string_of_int 200 response.Freight.Ast.status;
  let store =
    Freight.Response_store.record ~name:"seed" response Freight.Response_store.empty
  in
  let src = Freight.Response_store.source store in
  assert_equal (Some "abc") (src "seed.response.body.token");
  assert_equal (Some "7") (src "seed.response.body.n")

(* ── Deep chaining + float rendering ─────────────────────────────────────── *)

let test_e2e_deep_chaining_and_float _ =
  let server =
    Mock_server.start (fun _ ->
        Mock_server.json_response {|{"data":{"id":"abc123"},"price":9.0}|})
  in
  let response = run_against server (base_request ~url:(Mock_server.url server "/")) in
  let store =
    Freight.Response_store.record ~name:"seed" response Freight.Response_store.empty
  in
  let resolver = Freight.Resolver.make [ Freight.Response_store.source store ] in
  let next =
    { Freight.Ast.name = None
    ; method_ = Freight.Ast.Get
    ; url = "https://api/items/{{seed.response.body.data.id}}?price={{seed.response.body.price}}"
    ; headers = []
    ; body = Freight.Ast.Body_none
    ; save_to = None
    }
  in
  let resolved = Freight.Resolve.substitute_request_r resolver next in
  assert_equal ~printer:Fun.id "https://api/items/abc123?price=9.0"
    resolved.Freight.Ast.url;
  assert_equal [] (Freight.Resolve.unresolved_request_r resolver next)

(* ── What freight SENT: headers + inline JSON body arrive intact ─────────── *)

let test_e2e_records_request_body_and_headers _ =
  let server = Mock_server.start (fun _ -> Mock_server.json_response {|{"ok":true}|}) in
  let request =
    { Freight.Ast.name = Some "post"
    ; method_ = Freight.Ast.Post
    ; url = Mock_server.url server "/widgets"
    ; headers = [ ("X-Api-Key", "secret123"); ("Content-Type", "application/json") ]
    ; body = Freight.Ast.Body_inline {|{"name":"gadget"}|}
    ; save_to = None
    }
  in
  ignore (run_against server request);
  match Mock_server.requests server with
  | [ rec_ ] ->
    assert_equal ~printer:Fun.id "POST" rec_.Mock_server.meth;
    assert_equal ~printer:Fun.id "/widgets" rec_.Mock_server.path;
    assert_equal (Some "secret123") (Mock_server.header rec_ "X-Api-Key");
    assert_equal ~printer:Fun.id {|{"name":"gadget"}|} rec_.Mock_server.body
  | other ->
    assert_failure (Printf.sprintf "expected 1 request, got %d" (List.length other))

(* ── Multipart upload: parts arrive as multipart/form-data on the wire ────── *)

let test_e2e_multipart_upload _ =
  let server = Mock_server.start (fun _ -> Mock_server.json_response {|{"ok":true}|}) in
  let request =
    { Freight.Ast.name = Some "upload"
    ; method_ = Freight.Ast.Post
    ; url = Mock_server.url server "/imports"
    ; headers = []
    ; body =
        Freight.Ast.Body_multipart
          [ { part_name = "note"
            ; filename = None
            ; content_type = None
            ; content = Freight.Ast.Part_text "hello from freight"
            }
          ]
    ; save_to = None
    }
  in
  ignore (run_against server request);
  match Mock_server.requests server with
  | [ rec_ ] ->
    (match Mock_server.header rec_ "Content-Type" with
     | Some ct ->
       assert_bool ("expected multipart/form-data, got: " ^ ct)
         (String.length ct >= 19
          && String.sub ct 0 19 = "multipart/form-data")
     | None -> assert_failure "no Content-Type on multipart request");
    let contains needle =
      let hay = rec_.Mock_server.body in
      let nl = String.length needle and hl = String.length hay in
      let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
      nl = 0 || go 0
    in
    assert_bool "body carries the part name" (contains "name=\"note\"");
    assert_bool "body carries the part value" (contains "hello from freight")
  | other ->
    assert_failure (Printf.sprintf "expected 1 request, got %d" (List.length other))

(* ── Save to file: binary body is written byte-identical (the ">>" path) ──── *)

let test_e2e_save_binary_body_byte_identical _ =
  (* A body with NUL and high bytes — the kind of thing the text renderer mangles. *)
  let payload = "PK\003\004\000\255\254\253binary\000bytes\n" in
  let server =
    Mock_server.start (fun _ ->
        Mock_server.raw_response
          ~headers:[ ("Content-Type", "application/octet-stream") ]
          payload)
  in
  let path = temp_file ".bin" in
  let request =
    { Freight.Ast.name = Some "dl"
    ; method_ = Freight.Ast.Get
    ; url = Mock_server.url server "/download"
    ; headers = []
    ; body = Freight.Ast.Body_none
    ; save_to = Some { Freight.Ast.save_path = Some path; overwrite = true }
    }
  in
  (* Executor emits -o path, so curl writes the body straight to disk. *)
  ignore (run_curl (Freight.Executor.to_curl request));
  Mock_server.stop server;
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      assert_bool "saved file exists" (Sys.file_exists path);
      assert_equal ~printer:(Printf.sprintf "%S") payload (read_file path))

(* ── Error status round-trips as a parseable response, not a crash ────────── *)

let test_e2e_error_status _ =
  let server =
    Mock_server.start (fun _ ->
        Mock_server.raw_response ~status:404 ~status_text:"Not Found"
          ~headers:[ ("Content-Type", "application/json") ]
          {|{"error":"missing"}|})
  in
  let response = run_against server (base_request ~url:(Mock_server.url server "/x")) in
  assert_equal ~printer:string_of_int 404 response.Freight.Ast.status

(* ── Malformed JSON body: chaining refs resolve to None, no crash ─────────── *)

let test_e2e_malformed_json_body _ =
  let server = Mock_server.start (fun _ -> Mock_server.json_response "not json at all") in
  let response = run_against server (base_request ~url:(Mock_server.url server "/")) in
  assert_equal ~printer:string_of_int 200 response.Freight.Ast.status;
  let store =
    Freight.Response_store.record ~name:"seed" response Freight.Response_store.empty
  in
  let src = Freight.Response_store.source store in
  (* No exception; the ref simply does not resolve. *)
  assert_equal None (src "seed.response.body.anything")

let suite =
  "e2e"
  >::: [ "e2e_get_and_parse" >:: test_e2e_get_and_parse
       ; "e2e_deep_chaining_and_float" >:: test_e2e_deep_chaining_and_float
       ; "e2e_records_request_body_and_headers" >:: test_e2e_records_request_body_and_headers
       ; "e2e_multipart_upload" >:: test_e2e_multipart_upload
       ; "e2e_save_binary_body_byte_identical" >:: test_e2e_save_binary_body_byte_identical
       ; "e2e_error_status" >:: test_e2e_error_status
       ; "e2e_malformed_json_body" >:: test_e2e_malformed_json_body
       ]

let () = run_test_tt_main suite
