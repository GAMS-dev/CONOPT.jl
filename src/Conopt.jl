module Conopt

using Preferences

const libconopt = @load_preference("libconopt_path", "conopt")

"""
    set_library_path(path::String)

Sets the path to the CONOPT shared library (`.so`, `.dll`, or `.dylib`).
You must restart Julia after calling this for the changes to take effect.
"""
function set_library_path(path::String)
    if !isfile(path)
        @warn "The provided path does not point to an existing file: $path"
    end

    # This writes the path to a LocalPreferences.toml file in the user's environment
    @set_preferences!("libconopt_path" => path)

    @info "CONOPT library path set to $path. Please restart Julia."
end


"""
    set_license(licint1::Int, licint2::Int, licint3::Int, licstring::String)

Saves your CONOPT license details permanently to your current Julia project environment.
"""
function set_license(licint1::Int, licint2::Int, licint3::Int, licstring::String)
    @set_preferences!(
        "licint1" => licint1,
        "licint2" => licint2,
        "licint3" => licint3,
        "licstring" => licstring
    )
    @info "CONOPT license securely saved to LocalPreferences.toml."
end

function __init__()
    if libconopt == "conopt" || !isfile(libconopt)
        @warn """
        CONOPT library not found!
        Please set the path to the CONOPT shared library using:
        `Conopt.set_library_path("/path/to/libconopt.so")`
        and then restart Julia.
        """
        # Return early so we don't attempt to load or verify the missing library
        return
    end
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
