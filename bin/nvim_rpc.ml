open Core
open Async

type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpck.t list }
  | Notification of { method_ : string; params : Msgpck.t list }

type t = {
  writer : Writer.t;
  mutable next_msgid : int;
  pending : (int, (Msgpck.t, string) result Ivar.t) Hashtbl.t;
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

let start_reader reader pending incoming_w : unit Deferred.t =
  let buf = ref "" in
  let rec loop () =
    let tmp = Bytes.create 65536 in
    match%bind Reader.read reader tmp with
    | `Eof -> return ()
    | `Ok n ->
      let chunk = String.sub (Bytes.to_string tmp) ~pos:0 ~len:n in
      buf := !buf ^ chunk;
      drain ()
  and drain () =
    if String.length !buf > 0 then
      match (try Some (Msgpck.String.read !buf) with _ -> None) with
      | None -> loop ()
      | Some (consumed, msg) ->
        buf := String.sub !buf ~pos:consumed ~len:(String.length !buf - consumed);
        (match parse_msg msg with
         | `Reply (msgid, err, result) ->
           (* Yield so the sender can register the pending ivar before we try to fill it *)
           let%bind () = Scheduler.yield () in
           (match Hashtbl.find pending msgid with
            | None -> ()
            | Some ivar ->
              Hashtbl.remove pending msgid;
              let value = match err with
                | Msgpck.Nil -> Ok result
                | Msgpck.String s -> Error s
                | Msgpck.List [ _; Msgpck.String s ] -> Error s
                | other -> Error (Msgpck.show other)
              in
              Ivar.fill_exn ivar value);
           drain ()
         | `Request (msgid, method_, params) ->
           Pipe.write_without_pushback incoming_w (Request { msgid; method_; params });
           drain ()
         | `Notification (method_, params) ->
           Pipe.write_without_pushback incoming_w (Notification { method_; params });
           drain ()
         | `Unknown -> drain ())
    else
      loop ()
  in
  loop ()

let create () =
  let pending = Hashtbl.create (module Int) in
  let incoming_r, incoming_w = Pipe.create () in
  let t = {
    writer = Lazy.force Writer.stdout;
    next_msgid = 1;
    pending;
  } in
  let reader_done = start_reader (Lazy.force Reader.stdin) pending incoming_w in
  (t, incoming_r, reader_done)

let read incoming_r =
  match%map Pipe.read incoming_r with
  | `Ok msg -> msg
  | `Eof -> failwith "incoming pipe closed"

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
