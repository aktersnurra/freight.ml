type t

val empty : t
val of_list : (string * string) list -> t
val find : t -> string -> string option
val add : t -> key:string -> data:string -> t
val load : dir:string -> active_env:string option -> t
val parse_line : t -> string -> t
val substitute : t -> string -> string
