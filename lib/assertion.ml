type failure = {
  assertion : Ast.assertion;
  detail : string;
}

let lower = String.lowercase_ascii

let contains ~needle haystack =
  let nl = String.length needle and hl = String.length haystack in
  if nl = 0 then true
  else
    let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
    go 0

let lookup_header response name =
  let name = lower name in
  List.find_map
    (fun (k, v) -> if lower k = name then Some v else None)
    response.Ast.headers

let lookup_body response path =
  match Yojson.Safe.from_string response.Ast.body with
  | json -> Json_path.lookup json (Json_path.parse path)
  | exception Yojson.Json_error _ -> None

let describe = function
  | Ast.Expect_status n -> Printf.sprintf "status %d" n
  | Ast.Expect_header { header_name; header_op; header_value } ->
    let op = match header_op with Op_equals -> "equals" | Op_contains -> "contains" in
    Printf.sprintf "header %s %s %s" header_name op header_value
  | Ast.Expect_body { body_path; body_op; body_value } -> (
    match body_op, body_value with
    | Op_exists, _ -> Printf.sprintf "body %s exists" body_path
    | Op_eq, Some v -> Printf.sprintf "body %s == %s" body_path v
    | Op_neq, Some v -> Printf.sprintf "body %s != %s" body_path v
    | Op_body_contains, Some v -> Printf.sprintf "body %s contains %s" body_path v
    | (Op_eq | Op_neq | Op_body_contains), None -> Printf.sprintf "body %s" body_path)

(* [check_one] returns [Some detail] on failure, [None] on pass. *)
let check_one response = function
  | Ast.Expect_status n ->
    if response.Ast.status = n then None
    else Some (Printf.sprintf "expected status %d, got %d" n response.Ast.status)
  | Ast.Expect_header { header_name; header_op; header_value } -> (
    match lookup_header response header_name with
    | None -> Some (Printf.sprintf "header %s not present" header_name)
    | Some actual -> (
      match header_op with
      | Op_equals ->
        if actual = header_value then None
        else Some (Printf.sprintf "header %s = %S, expected %S" header_name actual header_value)
      | Op_contains ->
        if contains ~needle:header_value actual then None
        else Some (Printf.sprintf "header %s = %S does not contain %S" header_name actual header_value)))
  | Ast.Expect_body { body_path; body_op; body_value } -> (
    let actual = lookup_body response body_path in
    match body_op, body_value, actual with
    | Op_exists, _, Some _ -> None
    | Op_exists, _, None -> Some (Printf.sprintf "body %s is absent" body_path)
    | Op_eq, Some v, Some a ->
      if a = v then None else Some (Printf.sprintf "body %s = %S, expected %S" body_path a v)
    | Op_eq, Some v, None -> Some (Printf.sprintf "body %s is absent, expected %S" body_path v)
    | Op_neq, Some v, Some a ->
      if a <> v then None else Some (Printf.sprintf "body %s = %S, expected not %S" body_path a v)
    | Op_neq, Some _, None -> None (* absent value is not equal to anything *)
    | Op_body_contains, Some v, Some a ->
      if contains ~needle:v a then None
      else Some (Printf.sprintf "body %s = %S does not contain %S" body_path a v)
    | Op_body_contains, Some v, None ->
      Some (Printf.sprintf "body %s is absent, expected to contain %S" body_path v)
    | (Op_eq | Op_neq | Op_body_contains), None, _ ->
      Some (Printf.sprintf "body %s: missing comparison value" body_path))

let check response assertions =
  List.filter_map
    (fun assertion ->
      match check_one response assertion with
      | None -> None
      | Some detail -> Some { assertion; detail })
    assertions
