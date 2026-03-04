module Conopt

function __init__()
    major = Ref{Cint}(0)
    minor = Ref{Cint}(0)
    patch = Ref{Cint}(0)
    retcode = LibConopt.COIGET_Version(major, minor, patch)
    version = VersionNumber(major[], minor[], patch[])
    return
end

include("libconopt.jl")
include("C_wrapper.jl")

export LibConopt

for sym in filter(s -> startswith("$s", "Conopt_"), names(@__MODULE__, all = true))
    @eval export $sym
end

global Optimizer

end
