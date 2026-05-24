type t

val empty : t
val of_list : (string * string) list -> t
val find : t -> string -> string option
val add : t -> key:string -> data:string -> t
val load : dir:string -> active_env:string option -> t
val parse_line : t -> string -> t
val substitute : t -> string -> string
val to_list : t -> (string * string) list
(** All key-value pairs in the env, sorted by key. *)

val unresolved : t -> string -> string list
(** [unresolved env source] returns the sorted, deduplicated list of
    variable names referenced in [source] via [{{name}}] syntax that
    are not present in [env]. *)
