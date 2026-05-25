type incoming =
  | Request of { msgid : int; method_ : string; params : Msgpck.t list }
  | Notification of { method_ : string; params : Msgpck.t list }

type write_fn = Msgpck.t -> unit

type t =
  { mutable next_msgid : int
  ; pending : (int, Msgpck.t Eio.Promise.u) Hashtbl.t
  ; write_mutex : Eio.Mutex.t
  ; write_msg : write_fn
  ; incoming : incoming Eio.Stream.t
  }

let serialize_write t msg =
  Eio.Mutex.use_rw t.write_mutex ~protect:true (fun () ->
    t.write_msg msg)

let parse_rpc msg =
  match msg with
  | Msgpck.List [ Int 0; Int msgid; String method_; List params ] ->
    `Request (msgid, method_, params)
  | Msgpck.List [ Int 2; String method_; List params ] ->
    `Notification (method_, params)
  | Msgpck.List [ Int 1; Int msgid; err; result ] ->
    `Reply (msgid, err, result)
  | _ -> `Unknown

let resolve_pending t msgid result error =
  match Hashtbl.find_opt t.pending msgid with
  | None -> ()
  | Some resolver ->
    Hashtbl.remove t.pending msgid;
    let value =
      match error with
      | Msgpck.Nil -> result
      | Msgpck.String s -> failwith ("nvim rpc error: " ^ s)
      | Msgpck.List [ _; Msgpck.String s ] -> failwith ("nvim rpc error: " ^ s)
      | other -> failwith ("nvim rpc error: " ^ Msgpck.show other)
    in
    Eio.Promise.resolve resolver value

let reader_loop ~read_msg t =
  while true do
    let msg = read_msg () in
    match parse_rpc msg with
    | `Reply (msgid, err, result) ->
      resolve_pending t msgid result err
    | `Request (msgid, method_, params) ->
      Eio.Stream.add t.incoming (Request { msgid; method_; params })
    | `Notification (method_, params) ->
      Eio.Stream.add t.incoming (Notification { method_; params })
    | `Unknown -> ()
  done

let make_writer sink =
  fun msg ->
    let bytes = Msgpck.String.to_string msg in
    Eio.Flow.copy_string (Bytes.to_string bytes) sink

let make_reader source =
  let buf = Buffer.create 65536 in
  let tmp = Bytes.create 65536 in
  fun () ->
    let rec loop () =
      let s = Buffer.contents buf in
      if String.length s > 0 then
        match (try Some (Msgpck.String.read s) with _ -> None) with
        | Some (consumed, msg) ->
          let rest = String.sub s consumed (String.length s - consumed) in
          Buffer.clear buf;
          Buffer.add_string buf rest;
          msg
        | None -> read_more ()
      else
        read_more ()
    and read_more () =
      let n = Eio.Flow.single_read source tmp in
      Buffer.add_subbytes buf tmp 0 n;
      loop ()
    in
    loop ()

let create ~sw ~stdin ~stdout =
  let incoming = Eio.Stream.create 64 in
  let t =
    { next_msgid = 1
    ; pending = Hashtbl.create 16
    ; write_mutex = Eio.Mutex.create ()
    ; write_msg = make_writer stdout
    ; incoming
    }
  in
  let read_msg = make_reader stdin in
  Eio.Fiber.fork ~sw (fun () ->
    try reader_loop ~read_msg t
    with End_of_file -> ());
  t

let read t = Eio.Stream.take t.incoming

let reply_ok t ~msgid result =
  serialize_write t (Msgpck.List [ Int 1; Int msgid; Nil; result ])

let reply_error t ~msgid err =
  serialize_write t (Msgpck.List [ Int 1; Int msgid; String err; Nil ])

let call t method_ params =
  let msgid = t.next_msgid in
  t.next_msgid <- msgid + 1;
  let promise, resolver = Eio.Promise.create () in
  Hashtbl.replace t.pending msgid resolver;
  serialize_write t (Msgpck.List [ Int 0; Int msgid; String method_; List params ]);
  Eio.Promise.await promise
