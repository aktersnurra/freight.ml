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

type request = {
  name : string option;
  method_ : method_;
  url : string;
  headers : (string * string) list;
  body : body;
  save_to : save option;
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

val make_request :
  ?name:string ->
  ?save_to:save ->
  method_:method_ ->
  url:string ->
  headers:(string * string) list ->
  body:body ->
  unit ->
  (request, validation_error) result

val make_response :
  status:int ->
  status_text:string ->
  headers:(string * string) list ->
  body:string ->
  duration_ms:int ->
  request:request ->
  unit ->
  (response, validation_error) result

val method_to_string : method_ -> string
val method_of_string : string -> method_
val apply_host_header : request -> request
(** If [request.url] is a relative path (starts with [/]) and a [Host] header
    is present, prepends the host value to the url and removes the [Host]
    header. Returns the request unchanged otherwise. *)
