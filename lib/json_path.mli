type step =
  | Field of string
  | Index of int

val parse : string -> step list
(** Parse a dotted/bracketed path. [.field], [[n]] and [.n] are all accepted:
    ["data.items[0].id"] and ["data.items.0.id"] both parse to the same steps. *)

val lookup : Yojson.Safe.t -> step list -> string option
(** Walk [json] along the steps. Returns the scalar leaf rendered as a string
    (string/int/float/bool/null), or [None] if the path is missing or the leaf
    is a non-scalar (object/array). *)
