type failure = {
  assertion : Ast.assertion;
  detail : string;  (** why it failed, e.g. "expected status 200, got 404" *)
}

val check : Ast.response -> Ast.assertion list -> failure list
(** One failure per unmet assertion, in order; [] when all pass. *)

val describe : Ast.assertion -> string
(** Human-readable one-liner, e.g. "status 201" / "body data.id exists". *)
