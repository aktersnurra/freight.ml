type env = {
  now : unit -> float;
  random_int : int -> int;
  iso_of_epoch : float -> string;
}

let hex_of_byte b = Printf.sprintf "%02x" (b land 0xff)

(* RFC 4122 version-4 UUID from 16 random bytes: set the version nibble to 4 and
   the variant high bits to 10. *)
let uuid env =
  let bytes = Array.init 16 (fun _ -> env.random_int 256) in
  bytes.(6) <- (bytes.(6) land 0x0f) lor 0x40;
  bytes.(8) <- (bytes.(8) land 0x3f) lor 0x80;
  let h i = hex_of_byte bytes.(i) in
  String.concat ""
    [ h 0; h 1; h 2; h 3; "-"; h 4; h 5; "-"; h 6; h 7; "-"; h 8; h 9; "-"
    ; h 10; h 11; h 12; h 13; h 14; h 15 ]

let random_int_in env spec =
  match String.split_on_char ':' spec with
  | [ "$randomInt" ] -> Some (string_of_int (env.random_int 1000))
  | [ "$randomInt"; a; b ] -> (
    match (int_of_string_opt a, int_of_string_opt b) with
    | Some a, Some b when b > a -> Some (string_of_int (a + env.random_int (b - a)))
    | _ -> None)
  | _ -> None

let source env ref =
  match ref with
  | "$uuid" -> Some (uuid env)
  | "$timestamp" -> Some (string_of_int (int_of_float (env.now ())))
  | "$isoTimestamp" -> Some (env.iso_of_epoch (env.now ()))
  | _ when String.length ref >= 10 && String.sub ref 0 10 = "$randomInt" ->
    random_int_in env ref
  | _ -> None
