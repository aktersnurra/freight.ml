val show :
  call:(string -> Msgpck.t list -> Msgpck.t) ->
  name:string ->
  filetype:string ->
  lines:string list ->
  int

val update :
  call:(string -> Msgpck.t list -> Msgpck.t) ->
  int ->
  filetype:string ->
  lines:string list ->
  unit

val set_keymap :
  call:(string -> Msgpck.t list -> Msgpck.t) ->
  int ->
  key:string ->
  command:string ->
  unit
