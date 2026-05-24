open Core
open Async

type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpck.t list }
  | Notification of { method_ : string; params : Msgpck.t list }

type t = {
  reader : Reader.t;
  writer : Writer.t;
  mutable next_msgid : int;
  mutable buf : string;
  pending : (int, (Msgpck.t, string) result Ivar.t) Hashtbl.t;
}

let create () =
  { reader = Lazy.force Reader.stdin
  ; writer = Lazy.force Writer.stdout
  ; next_msgid = 1
  ; buf = ""
  ; pending = Hashtbl.create (module Int)
  }

let write_msg t msg =
  let bytes = Msgpck.String.to_string msg in
  Writer.write t.writer (Bytes.to_string bytes)

let parse_msg msg =
  match msg with
  | Msgpck.List [ Int 0; Int msgid; String method_; List params ] ->
    `Request (msgid, method_, params)
  | Msgpck.List [ Int 2; String method_; List params ] ->
    `Notification (method_, params)
  | Msgpck.List [ Int 1; Int msgid; err; result ] ->
    `Reply (msgid, err, result)
  | _ -> `Unknown

let read t =
  let rec loop () =
    (* Try to parse from buffer first *)
    if String.length t.buf > 0 then begin
      match (try Some (Msgpck.String.read t.buf) with _ -> None) with
      | Some (consumed, msg) ->
        t.buf <- String.sub t.buf ~pos:consumed ~len:(String.length t.buf - consumed);
        (match parse_msg msg with
         | `Reply (msgid, err, result) ->
           (match Hashtbl.find t.pending msgid with
            | None -> loop ()
            | Some ivar ->
              Hashtbl.remove t.pending msgid;
              let value = match err with
                | Msgpck.Nil -> Ok result
                | Msgpck.String s -> Error s
                | _ -> Error "rpc error"
              in
              Ivar.fill ivar value;
              loop ())
         | `Request (msgid, method_, params) ->
           return (Request { msgid; method_; params })
         | `Notification (method_, params) ->
           return (Notification { method_; params })
         | `Unknown -> loop ())
      | None ->
        (* Need more data *)
        read_more t
    end else
      read_more t
  and read_more t =
    match%bind Reader.read_available t.reader with
    | `Eof -> failwith "stdin EOF"
    | `Ok buf ->
      t.buf <- t.buf ^ buf;
      loop ()
  in
  loop ()

let reply_ok t ~msgid result =
  write_msg t (Msgpck.List [ Int 1; Int msgid; Nil; result ])

let reply_error t ~msgid err =
  write_msg t (Msgpck.List [ Int 1; Int msgid; String err; Nil ])

let call t method_ params =
  let msgid = t.next_msgid in
  t.next_msgid <- msgid + 1;
  let ivar = Ivar.create () in
  Hashtbl.set t.pending ~key:msgid ~data:ivar;
  write_msg t (Msgpck.List [ Int 0; Int msgid; String method_; List params ]);
  Ivar.read ivar
