type t

val empty : t

val record : name:string -> Ast.response -> t -> t
(** Store [response] under [name]. An empty [name] is ignored (unnamed
    requests cannot be chained). Re-recording a name overwrites it. *)

val source : t -> Resolver.source
(** Resolve [<name>.response.body(.<path>)?] and
    [<name>.response.headers.<header>] references. Body paths use the
    {!Json_path} subset; header lookup is case-insensitive. Returns [None] for
    unknown names, missing paths, non-scalar leaves, or malformed JSON. *)
