type t

type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpck.t list }
  | Notification of { method_ : string; params : Msgpck.t list }

val create : unit -> t * incoming Async.Pipe.Reader.t * unit Async.Deferred.t
(** Start the background reader. Returns the rpc handle and a pipe of incoming messages. *)

val read : incoming Async.Pipe.Reader.t -> incoming Async.Deferred.t
(** Read one incoming message. *)

val reply_ok : t -> msgid:int -> Msgpck.t -> unit
val reply_error : t -> msgid:int -> string -> unit
val call : t -> string -> Msgpck.t list -> (Msgpck.t, string) result Async.Deferred.t
