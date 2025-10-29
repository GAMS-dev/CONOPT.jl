module Conopt

import MathOptInterface as MOI

function __init__()
    major = Ref{Cint}(0)
    minor = Ref{Cint}(0)
    patch = Ref{Cint}(0)
    retcode = LibConopt.COIGET_Version(major, minor, patch)
    version = VersionNumber(major[], minor[], patch[])
    return
end

include("gen/libconopt.jl")
include("MOI_wrapper/MOI_wrapper.jl")
using .LibConopt

for sym in filter(s -> startswith("$s", "Conopt_"), names(@__MODULE__, all = true))
    @eval export $sym
end

end
