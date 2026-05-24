val freight_open
  :  client:[ `blocking ] Vcaml.Client.t
  -> State.t
  -> unit Async.Deferred.Or_error.t

val freight_env
  :  client:[ `blocking ] Vcaml.Client.t
  -> State.t
  -> string option
  -> unit Async.Deferred.Or_error.t

val freight_inspect
  :  client:[ `blocking ] Vcaml.Client.t
  -> State.t
  -> unit Async.Deferred.Or_error.t

val freight_run
  :  client:[ `blocking ] Vcaml.Client.t
  -> State.t
  -> unit Async.Deferred.Or_error.t
