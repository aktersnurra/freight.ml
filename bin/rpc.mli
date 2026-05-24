type t

type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpck.t list }
  | Notification of { method_ : string; params : Msgpck.t list }

val create : unit -> t

val read : t -> incoming Async.Deferred.t
(** Read one msgpack-rpc message from stdin. Loops past reply messages. *)

val reply_ok : t -> msgid:int -> Msgpck.t -> unit
(** Send [1, msgid, nil, result] to stdout. *)

val reply_error : t -> msgid:int -> string -> unit
(** Send [1, msgid, error_str, nil] to stdout. *)

val call : t -> string -> Msgpck.t list -> (Msgpck.t, string) result Async.Deferred.t
(** Send a request to Neovim and wait for its reply. *)
