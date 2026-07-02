type method_ =
  | Get
  | Post
  | Put
  | Patch
  | Delete
  | Head
  | Options
  | Trace
  | Connect
  | Custom of string

type part_content =
  | Part_text of string
  | Part_file of string

type multipart_part = {
  part_name : string;
  filename : string option;
  content_type : string option;
  content : part_content;
}

type body =
  | Body_inline of string
  | Body_file of string
  | Body_multipart of multipart_part list
  | Body_none

type save = {
  save_path : string option;  (** [None] derives the name from Content-Disposition. *)
  overwrite : bool;  (** [>>!] overwrites; [>>] refuses to clobber. *)
}

type header_op = Op_equals | Op_contains

type body_op = Op_exists | Op_eq | Op_neq | Op_body_contains

type assertion =
  | Expect_status of int
  | Expect_header of { header_name : string; header_op : header_op; header_value : string }
  | Expect_body of { body_path : string; body_op : body_op; body_value : string option }

type request = {
  name : string option;
  method_ : method_;
  url : string;
  headers : (string * string) list;
  body : body;
  save_to : save option;
  assertions : assertion list;
}

type response = {
  status : int;
  status_text : string;
  headers : (string * string) list;
  body : string;
  duration_ms : int;
  request : request;
}

type parse_error = {
  message : string;
  line : int;
  snippet : string;
}

type http_file = {
  requests : request list;
  path : string;
}

type validation_error =
  | Empty_url
  | Empty_header_name
  | Invalid_status
  | Negative_duration

let has_empty_header_name headers =
  List.exists (fun (name, _) -> String.trim name = "") headers

let validate_request_fields ~url ~headers =
  if String.trim url = "" then Error Empty_url
  else if has_empty_header_name headers then Error Empty_header_name
  else Ok ()

let make_request ?name ?save_to ?(assertions = []) ~method_ ~url ~headers ~body () =
  match validate_request_fields ~url ~headers with
  | Error error -> Error error
  | Ok () -> Ok { name; method_; url; headers; body; save_to; assertions }

let make_response ~status ~status_text ~headers ~body ~duration_ms ~request () =
  if status < 100 || status > 599 then Error Invalid_status
  else if duration_ms < 0 then Error Negative_duration
  else if has_empty_header_name headers then Error Empty_header_name
  else
    match validate_request_fields ~url:request.url ~headers:request.headers with
    | Error error -> Error error
    | Ok () -> Ok { status; status_text; headers; body; duration_ms; request }

let method_to_string = function
  | Get -> "GET"
  | Post -> "POST"
  | Put -> "PUT"
  | Patch -> "PATCH"
  | Delete -> "DELETE"
  | Head -> "HEAD"
  | Options -> "OPTIONS"
  | Trace -> "TRACE"
  | Connect -> "CONNECT"
  | Custom method_ -> method_

let method_of_string method_ =
  match String.uppercase_ascii method_ with
  | "GET" -> Get
  | "POST" -> Post
  | "PUT" -> Put
  | "PATCH" -> Patch
  | "DELETE" -> Delete
  | "HEAD" -> Head
  | "OPTIONS" -> Options
  | "TRACE" -> Trace
  | "CONNECT" -> Connect
  | custom -> Custom custom

let apply_host_header request =
  if not (String.length request.url > 0 && request.url.[0] = '/') then request
  else
    match
      List.partition
        (fun (k, _) -> String.equal (String.lowercase_ascii k) "host")
        request.headers
    with
    | [], _ -> request
    | (_, host_value) :: _, rest_headers ->
      let host = String.trim host_value in
      let base =
        if String.length host > 0 && host.[String.length host - 1] = '/' then
          String.sub host 0 (String.length host - 1)
        else host
      in
      { request with url = base ^ request.url; headers = rest_headers }
