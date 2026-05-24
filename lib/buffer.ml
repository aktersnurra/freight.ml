let buffer_prefix = "freight://response/"

let is_alphanumeric = function
  | 'a' .. 'z' | '0' .. '9' -> true
  | _ -> false

let slug text =
  let text = String.lowercase_ascii text in
  let buffer = Stdlib.Buffer.create (String.length text) in
  let pending_dash = ref false in
  String.iter
    (fun char ->
      if is_alphanumeric char then begin
        if !pending_dash && Stdlib.Buffer.length buffer > 0 then
          Stdlib.Buffer.add_char buffer '-';
        pending_dash := false;
        Stdlib.Buffer.add_char buffer char
      end
      else pending_dash := true)
    text;
  Stdlib.Buffer.contents buffer

let url_without_scheme url =
  match String.index_opt url ':' with
  | Some index
    when index + 2 < String.length url
         && Char.equal url.[index + 1] '/'
         && Char.equal url.[index + 2] '/' ->
      String.sub url (index + 3) (String.length url - index - 3)
  | _ -> url

let buffer_name request =
  let suffix =
    match request.Ast.name with
    | Some name -> name
    | None ->
        slug
          (Ast.method_to_string request.method_
          ^ "-"
          ^ url_without_scheme request.url)
  in
  buffer_prefix ^ suffix

let filetype_of_content_type = function
  | Response.Json -> "json"
  | Xml -> "xml"
  | Html -> "html"
  | Plain | Other _ -> "text"
