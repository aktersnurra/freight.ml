type recorded =
  { meth : string
  ; path : string
  ; headers : (string * string) list
  ; body : string
  }

type response =
  { status : int
  ; status_text : string
  ; resp_headers : (string * string) list
  ; resp_body : string
  }

type t =
  { port : int
  ; thread : Thread.t
  ; recorded : recorded list ref
  ; mutex : Mutex.t
  }

let lower = String.lowercase_ascii

let json_response ?(status = 200) body =
  { status
  ; status_text = "OK"
  ; resp_headers = [ ("Content-Type", "application/json") ]
  ; resp_body = body
  }

let raw_response ?(status = 200) ?(status_text = "OK") ?(headers = []) body =
  { status; status_text; resp_headers = headers; resp_body = body }

(* Read from [fd] until [marker] appears; return (bytes-through-marker,
   leftover-after-marker). Used to consume the header block up to CRLFCRLF. *)
let read_until fd marker =
  let buf = Buffer.create 1024 in
  let chunk = Bytes.create 1 in
  let marker_len = String.length marker in
  let rec loop () =
    let contents = Buffer.contents buf in
    let len = String.length contents in
    if len >= marker_len && String.sub contents (len - marker_len) marker_len = marker
    then contents
    else
      let n = Unix.read fd chunk 0 1 in
      if n = 0 then contents (* peer closed *)
      else begin
        Buffer.add_subbytes buf chunk 0 n;
        loop ()
      end
  in
  loop ()

let read_exact fd n =
  let buf = Bytes.create n in
  let rec loop off =
    if off >= n then Bytes.to_string buf
    else
      let r = Unix.read fd buf off (n - off) in
      if r = 0 then Bytes.sub_string buf 0 off else loop (off + r)
  in
  loop 0

let parse_header_line line =
  match String.index_opt line ':' with
  | None -> None
  | Some i ->
    let name = String.sub line 0 i |> String.trim |> lower in
    let value =
      String.sub line (i + 1) (String.length line - i - 1) |> String.trim
    in
    Some (name, value)

let strip_cr s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s

let parse_request fd =
  let head = read_until fd "\r\n\r\n" in
  let lines =
    head |> String.split_on_char '\n' |> List.map strip_cr
    |> List.filter (fun l -> l <> "")
  in
  let meth, path =
    match lines with
    | request_line :: _ -> (
      match String.split_on_char ' ' request_line with
      | m :: p :: _ -> (m, p)
      | _ -> ("", ""))
    | [] -> ("", "")
  in
  let headers =
    match lines with
    | _ :: header_lines -> List.filter_map parse_header_line header_lines
    | [] -> []
  in
  let body =
    match List.assoc_opt "content-length" headers with
    | Some len -> (
      match int_of_string_opt (String.trim len) with
      | Some n when n > 0 -> read_exact fd n
      | _ -> "")
    | None -> ""
  in
  { meth; path; headers; body }

let response_bytes { status; status_text; resp_headers; resp_body } =
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "HTTP/1.1 %d %s\r\n" status status_text);
  List.iter
    (fun (k, v) -> Buffer.add_string buf (Printf.sprintf "%s: %s\r\n" k v))
    resp_headers;
  Buffer.add_string buf
    (Printf.sprintf "Content-Length: %d\r\n" (String.length resp_body));
  Buffer.add_string buf "Connection: close\r\n\r\n";
  Buffer.add_string buf resp_body;
  Buffer.contents buf

let start ?(count = 1) handler =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen sock 8;
  let port =
    match Unix.getsockname sock with
    | Unix.ADDR_INET (_, port) -> port
    | Unix.ADDR_UNIX _ -> assert false
  in
  let recorded = ref [] in
  let mutex = Mutex.create () in
  let serve_one () =
    let client, _ = Unix.accept sock in
    Fun.protect
      ~finally:(fun () -> try Unix.close client with _ -> ())
      (fun () ->
        let request = parse_request client in
        Mutex.lock mutex;
        recorded := request :: !recorded;
        Mutex.unlock mutex;
        let bytes = Bytes.of_string (response_bytes (handler request)) in
        ignore (Unix.write client bytes 0 (Bytes.length bytes)))
  in
  let thread =
    Thread.create
      (fun () ->
        Fun.protect
          ~finally:(fun () -> try Unix.close sock with _ -> ())
          (fun () ->
            for _ = 1 to count do
              serve_one ()
            done))
      ()
  in
  { port; thread; recorded; mutex }

let port t = t.port
let url t path = Printf.sprintf "http://127.0.0.1:%d%s" t.port path
let stop t = Thread.join t.thread
let requests t = List.rev !(t.recorded)

let header recorded name =
  let name = lower name in
  List.assoc_opt name recorded.headers
