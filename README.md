# Conopt.jl

[![Build Status](https://github.com/jump-dev/Conopt.jl/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/jump-dev/Conopt.jl/actions?query=workflow%3ACI)

[Conopt.jl](https://github.com/jump-dev/Conopt.jl) is a Julia wrapper for the [CONOPT](https://conopt.gams.com/) solver.

It has two components:

- a thin wrapper around the C API
- an interface to [MathOptInterface](https://github.com/jump-dev/MathOptInterface.jl).

## Affiliation

This wrapper is maintained by the JuMP community with help from GAMS.

## License

`Conopt.jl` is licensed under the [MIT License](https://github.com/jump-dev/Conopt.jl/blob/master/LICENSE).

The underlying solver, CONOPT, is proprietary software from GAMS. You must purchase a license to use it.

## Providing a license

The underlying solver, CONOPT, is proprietary software from GAMS. You must purchase a license to use it.

There are a number of ways to provide a license to `Conopt.jl`. They are loaded with the following precedence (from highest to lowest):

#### 1. Direct in code

You can provide the license details as raw optimizer attributes when creating a `JuMP` model:
```julia
using JuMP, Conopt
model = Model(Conopt.Optimizer)
set_attribute(model, "licint1", licint1)
set_attribute(model, "licint2", licint2)
set_attribute(model, "licint3", licint3)
set_attribute(model, "licstring", "your-license-string")
```
Alternatively, when using the low-level C API, you can pass the license information directly to the `Conopt.ConoptModel` constructor.

#### 2. Project-specific license

The recommended way to provide a license is to save it to your local environment for the current project.
Use the `Conopt.set_license` function with the integers and string from your GAMS license file:
```julia
import Conopt
Conopt.set_license(licint1, licint2, licint3, "your-license-string")
```
This saves the license details to your `LocalPreferences.toml` file, so you only need to do this once per project.

#### 3. Environment variables

You can also provide the license via environment variables. This is useful for CI or other automated environments.

```bash
export CONOPT_LICENSE_INT_1=<licint1>
export CONOPT_LICENSE_INT_2=<licint2>
export CONOPT_LICENSE_INT_3=<licint3>
export CONOPT_LICENSE_STRING="<your-license-string>"
```

## Getting help

Contact [GAMS support](mailto:support@gams.com) if you encounter any problems using this interface or the solver.

If you have a reproducible example of a bug, please [open a GitHub issue](https://github.com/jump-dev/Conopt.jl/issues/new).

## Installation

To use `Conopt.jl`, you must have a local installation of the CONOPT solver libraries. Please see the [GAMS website](https://www.gams.com/download/) for information on obtaining CONOPT.

`Conopt.jl` needs to know the location of the CONOPT shared library (e.g., `libconopt.so`, `conopt.dll`, or `conopt.dylib`).
Tell `Conopt.jl` where to find the library by calling `Conopt.set_library_path`:
```julia
import Conopt
# This is an example, use the actual path to your CONOPT library
Conopt.set_library_path("/path/to/your/conopt/library/libconopt.so")
```
This preference is saved to a `LocalPreferences.toml` file in your current project. You will need to restart your Julia session for the change to take effect.

Once the library path is set, you can install `Conopt.jl` using the Julia package manager:
```julia
import Pkg
Pkg.add("Conopt")
```

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

A list of available options is provided in the [CONOPT reference manual](https://conopt.gams.com/).

Set options using `MOI.RawOptimizerAttribute`:
```julia
set_attribute(model, "time_limit", 100.0)
```

## C API

Conopt.jl provides a low-level wrapper around the CONOPT C API, which is used by the MathOptInterface implementation.

The main entry point for the low-level API is the `Conopt.ConoptModel` object. Using this object requires the user to manually manage memory and callbacks.

For a detailed example of how to use the C API, see the implementation of the MathOptInterface wrapper in `ext/ConoptMathOptInterfaceExt/MOI_wrapper.jl`.
