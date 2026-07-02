type env = {
  now : unit -> float;  (** Unix epoch seconds (e.g. Unix.gettimeofday). *)
  random_int : int -> int;  (** Uniform in [0, bound). *)
  iso_of_epoch : float -> string;
      (** Format epoch seconds as ISO-8601 UTC. Injected so this module stays
          free of a [unix] dependency; the effect layer supplies it. *)
}

val source : env -> Resolver.source
(** Resolve generated references: [$uuid], [$timestamp], [$isoTimestamp],
    [$randomInt], [$randomInt:a:b]. Returns [None] for any other reference (so it
    defers to later sources in the chain). Each call produces a fresh value. *)
