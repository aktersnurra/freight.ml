val freight_open    : rpc:Rpc.t -> State.t -> unit Async.Deferred.t
val freight_env     : rpc:Rpc.t -> State.t -> string option -> unit Async.Deferred.t
val freight_inspect : rpc:Rpc.t -> State.t -> unit Async.Deferred.t
val freight_run     : rpc:Rpc.t -> State.t -> unit Async.Deferred.t
