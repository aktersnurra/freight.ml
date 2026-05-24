type extraction_path =
  | Response_body of string list
  | Response_header of string

val extract : Ast.response -> extraction_path -> string option
val inject : name:string -> Ast.response -> Env.t -> Env.t
