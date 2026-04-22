# Copyright (c) 2013: Iain Dunning, Miles Lubin, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module ConoptMathOptInterfaceExt

import Conopt
import MathOptInterface as MOI
import PrecompileTools

function __init__()
    setglobal!(Conopt, :Optimizer, Optimizer)
    return nothing
end

include("MOI_wrapper.jl")

PrecompileTools.@setup_workload begin
    # 1. Build a pure-Julia model with zero C-dependencies
    src = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())

    x = MOI.add_variables(src, 3)
    MOI.set(src, MOI.VariableName(), x[1], "x1")
    MOI.set(src, MOI.VariablePrimalStart(), x[1], 0.0)

    MOI.add_constraint(src, x[1], MOI.GreaterThan(0.0))
    MOI.add_constraint(src, x[2], MOI.LessThan(0.0))
    MOI.add_constraint(src, x[3], MOI.EqualTo(0.0))

    # Add a linear constraint
    f_lin = 1.0 * x[1] + x[2] + x[3]
    MOI.add_constraint(src, f_lin, MOI.GreaterThan(0.0))

    # Add a nonlinear objective
    MOI.set(src, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    f_nl = MOI.ScalarNonlinearFunction(
        :+,
        Any[MOI.ScalarNonlinearFunction(:sin, Any[x[i]]) for i in 1:3],
    )
    MOI.set(src, MOI.ObjectiveFunction{typeof(f_nl)}(), f_nl)

    PrecompileTools.@compile_workload begin
        try
            # 2. Instantiate your specific Optimizer
            # (Note: This calls ConoptModel(), which triggers COI_Create.
            # If the user hasn't configured their library path yet, this will
            # safely throw an error and be caught by the block below.)
            dest = Optimizer()

            # 3. Explicitly compile the heavy lifting!
            # This forces Julia to JIT compile the variable extraction, matrix
            # sorting, and nonlinear evaluator setup.
            setup_model!(dest, src)

        catch
            # Silently catch any missing library errors so the user's
            # package installation doesn't fail.
        end
    end
end

end  # module ConoptMathOptInterfaceExt
