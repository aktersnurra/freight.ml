type t

type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpck.t list }
  | Notification of { method_ : string; params : Msgpck.t list }

val create :
  sw:Eio.Switch.t ->
  stdin:_ Eio.Flow.source ->
  stdout:_ Eio.Flow.sink ->
  t

val read : t -> incoming

val reply_ok : t -> msgid:int -> Msgpck.t -> unit
val reply_error : t -> msgid:int -> string -> unit
val call : t -> string -> Msgpck.t list -> Msgpck.t
