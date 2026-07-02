(* End-to-end tests: drive the REAL executor -> curl -> response parser ->
   response store -> resolver pipeline against a local mock HTTP server. No
   external network; a tiny Unix HTTP/1.1 responder is spun up per test on an
   OS-assigned port. This is the layer unit tests cannot reach: it proves the
   curl arg vector we generate actually produces the response we parse. *)

open OUnit2

(* A minimal single-request HTTP/1.1 server. Binds 127.0.0.1:0 (ephemeral port),
   serves exactly [count] connections with [response_bytes], then closes. Runs on
   its own thread so the test can drive curl against it. Returns the chosen port. *)
let serve ~count response_bytes =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen sock 8;
  let port =
    match Unix.getsockname sock with
    | Unix.ADDR_INET (_, port) -> port
    | Unix.ADDR_UNIX _ -> assert false
  in
  let serve_one () =
    let client, _ = Unix.accept sock in
    (* Drain the request (best effort) so curl's write side does not block. *)
    let buf = Bytes.create 4096 in
    (try ignore (Unix.recv client buf 0 4096 []) with _ -> ());
    let bytes = Bytes.of_string response_bytes in
    ignore (Unix.write client bytes 0 (Bytes.length bytes));
    Unix.close client
  in
  let thread =
    Thread.create
      (fun () ->
        for _ = 1 to count do
          serve_one ()
        done;
        Unix.close sock)
      ()
  in
  (port, thread)

let http_response ~body =
  let body_len = String.length body in
  Printf.sprintf
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
    body_len body

(* Run curl with the exact args our Executor generates, capture stdout. *)
let run_curl invocation =
  let args = Array.of_list ("curl" :: invocation.Freight.Executor.args) in
  let stdout_read, stdout_write = Unix.pipe () in
  let pid =
    Unix.create_process "curl" args Unix.stdin stdout_write Unix.stderr
  in
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

let get_request ~url =
  { Freight.Ast.name = Some "seed"
  ; method_ = Freight.Ast.Get
  ; url
  ; headers = []
  ; body = Freight.Ast.Body_none
  ; save_to = None
  }

(* Real round-trip: GET a JSON body from the mock, parse it, and confirm status
   and a top-level field survive the executor -> curl -> parser path. *)
let test_e2e_get_and_parse _ =
  let body = {|{"token":"abc","n":7}|} in
  let port, thread = serve ~count:1 (http_response ~body) in
  let request = get_request ~url:(Printf.sprintf "http://127.0.0.1:%d/" port) in
  let raw = run_curl (Freight.Executor.to_curl request) in
  Thread.join thread;
  match Freight.Response.parse_curl_output raw request with
  | Error e -> assert_failure ("parse failed: " ^ e)
  | Ok response ->
    assert_equal ~printer:string_of_int 200 response.Freight.Ast.status;
    let store =
      Freight.Response_store.record ~name:"seed" response
        Freight.Response_store.empty
    in
    let src = Freight.Response_store.source store in
    assert_equal (Some "abc") (src "seed.response.body.token");
    assert_equal (Some "7") (src "seed.response.body.n")

(* Deep chaining + float: a nested id and a JSON float from a real response must
   resolve into a second request's URL, with the float rendered as valid JSON. *)
let test_e2e_deep_chaining_and_float _ =
  let body = {|{"data":{"id":"abc123"},"price":9.0}|} in
  let port, thread = serve ~count:1 (http_response ~body) in
  let request = get_request ~url:(Printf.sprintf "http://127.0.0.1:%d/" port) in
  let raw = run_curl (Freight.Executor.to_curl request) in
  Thread.join thread;
  match Freight.Response.parse_curl_output raw request with
  | Error e -> assert_failure ("parse failed: " ^ e)
  | Ok response ->
    let store =
      Freight.Response_store.record ~name:"seed" response
        Freight.Response_store.empty
    in
    let resolver = Freight.Resolver.make [ Freight.Response_store.source store ] in
    let next =
      { Freight.Ast.name = None
      ; method_ = Freight.Ast.Get
      ; url =
          "https://api/items/{{seed.response.body.data.id}}?price={{seed.response.body.price}}"
      ; headers = []
      ; body = Freight.Ast.Body_none
      ; save_to = None
      }
    in
    let resolved = Freight.Resolve.substitute_request_r resolver next in
    assert_equal ~printer:Fun.id
      "https://api/items/abc123?price=9.0" resolved.Freight.Ast.url;
    assert_equal [] (Freight.Resolve.unresolved_request_r resolver next)

let suite =
  "e2e"
  >::: [ "e2e_get_and_parse" >:: test_e2e_get_and_parse
       ; "e2e_deep_chaining_and_float" >:: test_e2e_deep_chaining_and_float
       ]

let () = run_test_tt_main suite
