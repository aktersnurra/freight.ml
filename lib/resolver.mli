type source = string -> string option
(** Given the trimmed reference text inside [{{...}}], return a value or [None]
    to defer to the next source. *)

type t

val make : source list -> t
(** Build a resolver from an ordered source list; earlier sources win. *)

val resolve : t -> string -> string
(** Replace every [{{ref}}] using the source chain. Unresolved refs are left
    literal. Single pass: substituted values are not re-scanned. *)

val unresolved : t -> string -> string list
(** Sorted, deduped [{{ref}}]s that no source resolved. *)
