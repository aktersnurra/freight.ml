let ext_to_int s =
  String.fold_left (fun acc c -> (acc lsl 8) lor Char.code c) 0 s

let buf_handle_int buf =
  match buf with
  | Msgpck.Int n -> n
  | Msgpck.Ext (_, s) -> ext_to_int s
  | _ -> failwith "expected buffer handle"

let set_window_chrome ~call =
  ignore (call "nvim_command"
    [ Msgpck.String "setlocal nonumber norelativenumber signcolumn=no foldcolumn=0" ]);
  let set name value =
    ignore (call "nvim_set_option_value"
      [ Msgpck.String name; value; Msgpck.Map [ (Msgpck.String "scope", Msgpck.String "local") ] ])
  in
  set "number" (Msgpck.Bool false);
  set "relativenumber" (Msgpck.Bool false);
  set "signcolumn" (Msgpck.String "no");
  set "foldcolumn" (Msgpck.String "0")

let float_width ~screen_width ~line_widths =
  let content_width = List.fold_left max 1 line_widths in
  let available_width = max 1 (screen_width - 2) in
  min content_width available_width

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
    [ Msgpck.String
        (Printf.sprintf
           "vsplit | buffer %d | setlocal nonumber norelativenumber signcolumn=no foldcolumn=0"
           handle_int)
    ]);
  set_window_chrome ~call;
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
  let line_widths =
    List.map
      (fun line ->
        match call "nvim_strwidth" [ Msgpck.String line ] with
        | Msgpck.Int width -> width
        | _ -> 0)
      flat_lines
  in
  let width = float_width ~screen_width:screen_w ~line_widths in
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
  ignore (call "nvim_open_win" [ buf; Msgpck.Bool true; opts ]);
  ignore (call "nvim_buf_set_keymap"
    [ buf
    ; Msgpck.String "n"
    ; Msgpck.String "q"
    ; Msgpck.String ":close<CR>"
    ; Msgpck.Map
        [ (Msgpck.String "noremap", Msgpck.Bool true)
        ; (Msgpck.String "silent",  Msgpck.Bool true)
        ]
    ]);
  ignore (call "nvim_buf_set_keymap"
    [ buf
    ; Msgpck.String "n"
    ; Msgpck.String "g?"
    ; Msgpck.String ":FreightHelp<CR>"
    ; Msgpck.Map
        [ (Msgpck.String "noremap", Msgpck.Bool true)
        ; (Msgpck.String "silent",  Msgpck.Bool true)
        ]
    ])
