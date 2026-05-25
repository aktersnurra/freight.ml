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

let show_float ~call ~lines =
  let buf = call "nvim_create_buf" [ Msgpck.Bool false; Msgpck.Bool true ] in
  let handle_int = buf_handle_int buf in
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "buftype"; Msgpck.String "nofile" ]);
  ignore (call "nvim_buf_set_option"
    [ buf; Msgpck.String "filetype"; Msgpck.String "freight" ]);
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
  let width = 40 in
  let height = List.length flat_lines in
  let ui_info = call "nvim_list_uis" [] in
  let screen_w, screen_h =
    match ui_info with
    | Msgpck.List (Msgpck.Map pairs :: _) ->
      let find key =
        match List.assoc_opt (Msgpck.String key) pairs with
        | Some (Msgpck.Int n) -> n
        | _ -> 80
      in
      (find "width", find "height")
    | _ -> (80, 24)
  in
  let row = (screen_h - height) / 2 in
  let col = (screen_w - width) / 2 in
  let opts =
    Msgpck.Map
      [ (Msgpck.String "relative", Msgpck.String "editor")
      ; (Msgpck.String "width",    Msgpck.Int width)
      ; (Msgpck.String "height",   Msgpck.Int height)
      ; (Msgpck.String "row",      Msgpck.Int row)
      ; (Msgpck.String "col",      Msgpck.Int col)
      ; (Msgpck.String "style",    Msgpck.String "minimal")
      ; (Msgpck.String "border",   Msgpck.String "rounded")
      ; (Msgpck.String "focusable", Msgpck.Bool true)
      ]
  in
  let win = call "nvim_open_win" [ buf; Msgpck.Bool true; opts ] in
  let win_id = match win with Msgpck.Int n -> n | _ -> 0 in
  ignore (call "nvim_buf_set_keymap"
    [ buf
    ; Msgpck.String "n"
    ; Msgpck.String "q"
    ; Msgpck.String (Printf.sprintf ":lua vim.api.nvim_win_close(%d, true)<CR>" win_id)
    ; Msgpck.Map
        [ (Msgpck.String "noremap", Msgpck.Bool true)
        ; (Msgpck.String "silent",  Msgpck.Bool true)
        ]
    ]);
  ignore handle_int
