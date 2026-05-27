val freight_open : State.t -> unit
val freight_env : State.t -> string option -> unit
val freight_env_apply : State.t -> string option -> unit
val freight_inspect : State.t -> unit
val freight_help : State.t -> unit
val freight_run : State.t -> unit
val freight_run_all : State.t -> unit
val freight_view : State.t -> string -> unit
val freight_history : State.t -> unit
val freight_view_history : State.t -> int -> unit
