# Conopt.jl

[![Build Status](https://github.com/jump-dev/Conopt.jl/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/jump-dev/Conopt.jl/actions?query=workflow%3ACI)

[Conopt.jl](httpshttps://github.com/jump-dev/Conopt.jl) is a Julia wrapper for the [CONOPT](https://www.gams.com/latest/docs/S_CONOPT.html) solver.

It has two components:

- a thin wrapper around the C API
- an interface to [MathOptInterface](https://github.com/jump-dev/MathOptInterface.jl).

## Affiliation

This wrapper is maintained by the JuMP community.

## License

`Conopt.jl` is licensed under the [MIT License](https://github.com/jump-dev/Conopt.jl/blob/master/LICENSE).

The underlying solver, CONOPT, is a closed-source commercial product for which you must purchase a license.

## Getting help

If you need help, please ask a question on the [JuMP community forum](https://jump.dev/forum).

If you have a reproducible example of a bug, please [open a GitHub issue](https://github.com/jump-dev/Conopt.jl/issues/new).

## Installation

Install `Conopt.jl` using the Julia package manager:
```julia
import Pkg
Pkg.add("Conopt")
```

In addition to installing the `Conopt.jl` package, this will also download and
install the CONOPT binaries from [Conopt_jll.jl](https://github.com/jump-dev/Conopt_jll.jl).
**You do not need to install the CONOPT binaries separately, but you do need a license to use them.**

### Manual installation

This section explains how to opt-out of using the `Conopt_jll` binaries.

First, obtain a license and install a copy of CONOPT from [GAMS](https://www.gams.com/download/).

Once installed, set the `CONOPTDIR` environment variable to point to the
directory of your CONOPT installation, so that the file
`${CONOPTDIR}/lib/libconopt` exists.

Then, set the `CONOPT_JL_USE_CONOPT_JLL` environment variable to `"false"` and
run `Pkg.add("Conopt")`. For example:

```julia
ENV["CONOPTDIR"] = "/path/to/conopt"
ENV["CONOPT_JL_USE_CONOPT_JLL"] = "false"
import Pkg
Pkg.add("Conopt")
using Conopt
# check that the installation was successful
```

To change the location of a manual install, change the value of `CONOPTDIR`,
call `Pkg.build("Conopt")`, and then restart Julia.

To revert to the `Conopt_jll` binaries, do:
```julia
ENV["CONOPT_JL_USE_CONOPT_JLL"] = "true"
import Pkg
Pkg.build("Conopt")
```
then restart Julia.

## Use with JuMP

You can use Conopt with JuMP as follows:
```julia
using JuMP, Conopt
model = Model(Conopt.Optimizer)
set_attribute(model, "time_limit", 60.0)
set_attribute(model, "log_level", 0)
```

### Type stability

Conopt.jl moves the `Conopt.Optimizer` object to a package extension. As a
consequence, `Conopt.Optimizer` is now type unstable, and it will be inferred as
`Conopt.Optimizer()::Any`.

In most cases, this should not impact performance. If it does, there are two
work-arounds.

First, you can use a function barrier:
```julia
using JuMP, Conopt
function main(optimizer::T) where {T}
   model = Model(optimizer)
   return
end
main(Conopt.Optimizer)
```
Although the outer `Conopt.Optimizer` is type unstable, the `optimizer` inside
`main` will be properly inferred.

Second, you may explicitly get and use the extension module:
```julia
using JuMP, Conopt
const ConoptMathOptInterfaceExt =
   Base.get_extension(Conopt, :ConoptMathOptInterfaceExt)
model = Model(ConoptMathOptInterfaceExt.Optimizer)
```

## MathOptInterface API

The Conopt optimizer supports the following constraints and attributes.

List of supported objective functions:

 * [`MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}`](@ref)
 * [`MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction}`](@ref)
 * [`MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}`](@ref)

List of supported variable types:

 * [`MOI.Reals`](@ref)

List of supported constraint types:

 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.ScalarNonlinearFunction`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.ScalarNonlinearFunction`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.ScalarNonlinearFunction`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.ScalarQuadraticFunction{Float64}`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.ScalarQuadraticFunction{Float64}`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.ScalarQuadraticFunction{Float64}`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.Interval{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.VectorOfVariables`](@ref) in [`MOI.HyperRectangle{Float64}`](@ref)

List of supported model attributes:

 * [`MOI.Name`](@ref)
 * [`MOI.Silent`](@ref)
 * [`MOI.TimeLimitSec`](@ref)
 * [`MOI.NumberOfThreads`](@ref)
 * [`MOI.ObjectiveSense`](@ref)
 * [`MOI.SolveTimeSec`](@ref)
 * [`MOI.BarrierIterations`](@ref)


## Options

A list of available options is provided in the [CONOPT reference manual](https://www.gams.com/latest/docs/S_CONOPT.html).

Set options using `MOI.RawOptimizerAttribute`:
```julia
set_attribute(model, "time_limit", 100.0)
```

## C API

Conopt.jl provides a low-level wrapper around the CONOPT C API, which is used by the MathOptInterface implementation.

The main entry point for the low-level API is the `Conopt.ConoptModel` object. Using this object requires the user to manually manage memory and callbacks.

For a detailed example of how to use the C API, see the implementation of the MathOptInterface wrapper in `ext/ConoptMathOptInterfaceExt/MOI_wrapper.jl`.
