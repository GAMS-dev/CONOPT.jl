#=
Running this script generates the .jl Conopt library in the location specified in generator.toml.
=#

using Clang.Generators

cd(@__DIR__)

include_dir = "/home/ksenia/repos/conopt-new/build/install/include"

options = load_options(joinpath(@__DIR__, "generator.toml"))

args = String[]

headers = [
    joinpath(include_dir, header) for
    header in readdir(include_dir) if endswith(header, ".h")
]

ctx = create_context(headers, args, options)

build!(ctx)
