let ext_to_int s =
  String.fold_left (fun acc c -> (acc lsl 8) lor Char.code c) 0 s

let buf_handle_int buf =
  match buf with
  | Msgpck.Int n -> n
  | Msgpck.Ext (_, s) -> ext_to_int s
  | _ -> failwith "expected buffer handle"

let show ~call ~name ~filetype ~lines =
  let buf = call "nvim_create_buf" [ Msgpck.Bool false; Msgpck.Bool true ] in
  let handle_int = buf_handle_int buf in
  ignore (call "nvim_command"
    [ Msgpck.String (Printf.sprintf "silent! bwipeout %s" name) ]);
  ignore (call "nvim_buf_set_name" [ buf; Msgpck.String name ]);
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "buftype"; Msgpck.String "nofile" ]);
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "filetype"; Msgpck.String filetype ]);
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ]);
  let flat_lines = List.concat_map (String.split_on_char '\n') lines in
  let msgpack_lines =
    Msgpck.List (List.map (fun l -> Msgpck.String l) flat_lines)
  in
  ignore (call "nvim_buf_set_lines"
    [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; msgpack_lines ]);
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ]);
  ignore (call "nvim_command"
    [ Msgpck.String (Printf.sprintf "split | buffer %d" handle_int) ]);
  handle_int

let update ~call buf_id ~filetype ~lines =
  let buf = Msgpck.Int buf_id in
  let flat_lines = List.concat_map (String.split_on_char '\n') lines in
  let msgpack_lines =
    Msgpck.List (List.map (fun l -> Msgpck.String l) flat_lines)
  in
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "modifiable"; Msgpck.Bool true ]);
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "filetype"; Msgpck.String filetype ]);
  ignore (call "nvim_buf_set_lines"
    [ buf; Msgpck.Int 0; Msgpck.Int (-1); Msgpck.Bool false; msgpack_lines ]);
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "modifiable"; Msgpck.Bool false ])

let set_keymap ~call buf_id ~key ~command =
  let buf = Msgpck.Int buf_id in
  ignore (call "nvim_buf_set_keymap"
    [ buf
    ; Msgpck.String "n"
    ; Msgpck.String key
    ; Msgpck.String command
    ; Msgpck.Map
        [ (Msgpck.String "noremap", Msgpck.Bool true)
        ; (Msgpck.String "silent", Msgpck.Bool true)
        ]
    ])
