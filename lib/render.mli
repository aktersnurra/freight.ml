val request : Ast.request -> string
(** Serialize a request back to canonical [.http] text. This is the inverse of
    {!Parser.parse_string} for parser-reachable requests: for such a request [r],
    [Parser.parse_string (request r)] yields a single request equal to [r].

    Layout: optional [# @name], any [# @expect] lines, the request line, headers,
    a blank line then the body (inline verbatim, a file body as [< path], omitted
    for [Body_none], multipart as boundary blocks), then an optional [>>]/[>>!]
    save redirect. *)
