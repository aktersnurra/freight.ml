open Async
open Vcaml

let show ~client ~name ~filetype ~lines =
  let open Deferred.Or_error.Let_syntax in
  let%bind buf = Buffer.create [%here] client ~listed:false ~scratch:true in
  let%bind () = Buffer.set_name [%here] client (Buffer.Or_current.Id buf) name in
  (* Use exec_viml to open the buffer in a vertical split and make it current *)
  let buf_id = (buf :> int) in
  let%bind () =
    Nvim.exec_viml [%here] client (Printf.sprintf "vsplit | buffer %d" buf_id)
  in
  let%bind () =
    Buffer.set_lines
      [%here]
      client
      (Buffer.Or_current.Id buf)
      ~start:0
      ~end_:(-1)
      ~strict_indexing:false
      lines
  in
  let%bind () =
    Buffer.Option.set [%here] client (Buffer.Or_current.Id buf) Filetype filetype
  in
  Buffer.Option.set [%here] client (Buffer.Or_current.Id buf) Modifiable false
