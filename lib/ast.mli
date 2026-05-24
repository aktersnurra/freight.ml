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

val method_to_string : method_ -> string
val method_of_string : string -> method_
val apply_host_header : request -> request
(** If [request.url] is a relative path (starts with [/]) and a [Host] header
    is present, prepends the host value to the url and removes the [Host]
    header. Returns the request unchanged otherwise. *)
