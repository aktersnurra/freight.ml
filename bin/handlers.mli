val freight_open    : rpc:Nvim_rpc.t -> State.t -> unit Async.Deferred.t
val freight_env     : rpc:Nvim_rpc.t -> State.t -> string option -> unit Async.Deferred.t
val freight_inspect : rpc:Nvim_rpc.t -> State.t -> unit Async.Deferred.t
val freight_run     : rpc:Nvim_rpc.t -> State.t -> unit Async.Deferred.t
