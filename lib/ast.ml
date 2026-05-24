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

type body =
  | Body_inline of string
  | Body_file of string
  | Body_none

type request = {
  name : string option;
  method_ : method_;
  url : string;
  headers : (string * string) list;
  body : body;
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
