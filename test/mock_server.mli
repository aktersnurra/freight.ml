(* A recording HTTP/1.1 mock server for end-to-end tests. Binds an ephemeral
   loopback port, serves a fixed number of connections on a background thread,
   and captures each incoming request (method, path, headers, and full body via
   Content-Length) so tests can assert on exactly what freight sent — not just
   on the response it got back. Dependency-free (Unix + threads only). *)

type recorded =
  { meth : string
  ; path : string
  ; headers : (string * string) list  (** header names lowercased *)
  ; body : string
  }

type response =
  { status : int
  ; status_text : string
  ; resp_headers : (string * string) list
  ; resp_body : string
  }

type t

val json_response : ?status:int -> string -> response
(** A 200 (or [status]) response with Content-Type: application/json and the
    given body. *)

val raw_response :
  ?status:int ->
  ?status_text:string ->
  ?headers:(string * string) list ->
  string ->
  response
(** Build an arbitrary response. Content-Length is added automatically; extra
    [headers] (e.g. Content-Disposition, a binary Content-Type) are included. *)

val start : ?count:int -> (recorded -> response) -> t
(** Start a server that serves [count] connections (default 1). The handler maps
    each captured request to the response to send. Returns immediately; the
    server runs on its own thread. *)

val port : t -> int
val url : t -> string -> string
(** [url t path] is [http://127.0.0.1:<port><path>]. *)

val stop : t -> unit
(** Join the server thread and close the listening socket. Call after driving
    all expected requests. *)

val requests : t -> recorded list
(** The captured requests, in the order received. Meaningful after [stop]. *)

val header : recorded -> string -> string option
(** Case-insensitive lookup of a captured request header. *)
