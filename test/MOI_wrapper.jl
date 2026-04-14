# ============================ /test/MOI_wrapper.jl ============================
module TestConopt

using Conopt
using Test

import MathOptInterface as MOI

const OPTIMIZER = MOI.instantiate(
        MOI.OptimizerWithAttributes(Conopt.Optimizer, MOI.Silent() => true),
        )

const BRIDGED = MOI.instantiate(
        MOI.OptimizerWithAttributes(Conopt.Optimizer, MOI.Silent() => true),
        with_bridge_type = Float64,
        )

# See the docstring of MOI.Test.Config for other arguments.
const CONFIG = MOI.Test.Config(
        # Modify tolerances as necessary.
        atol = 1e-6,
        rtol = 1e-6,
        infeasible_status = MOI.LOCALLY_INFEASIBLE,
        optimal_status = MOI.LOCALLY_SOLVED,
        # Pass attributes or MOI functions to `exclude` to skip tests that
        # rely on this functionality.
        exclude = Any[
            MOI.VariableName,
            MOI.delete,
            MOI.ConstraintDual,
            MOI.ConstraintBasisStatus,
            MOI.DualObjectiveValue
            ],
        )

"""
    runtests()

This function runs all functions in the this Module starting with `test_`.
"""
function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$(name)", "test_")
            @testset "$(name)" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
end

"""
    test_runtests()

This function runs all the tests in MathOptInterface.Test.

Pass arguments to `exclude` to skip tests for functionality that is not
implemented or that your solver doesn't support.
"""
function test_runtests()
    MOI.Test.runtests(
        BRIDGED,
        CONFIG,
        include = String[
                 "test_linear_",
                 "test_quadratic_",
                 "test_nonlinear",
                 "test_model_",
                 "test_solver_",
                 "test_variable_",
                 "test_objective_",
               ],
        exclude = [
                "test_nonlinear_hs071_global", # CONOPT is a local solver
                "test_nonlinear_invalid", # TODO: need to revisit this later!!!
                ],
        # This argument is useful to prevent tests from failing on future
        # releases of MOI that add new tests. Don't let this number get too far
        # behind the current MOI release though. You should periodically check
        # for new tests to fix bugs and implement new features.
        #exclude_tests_after = v"0.10.5",
        verbose = true
        )
    return
end

"""
    test_SolverName()

You can also write new tests for solver-specific functionality. Write each new
test as a function with a name beginning with `test_`.
"""
function test_SolverName()
    @test MOI.get(Conopt.Optimizer(), MOI.SolverName()) == "CONOPT"
    return
end

function test_Name_and_Silent()
    model = Conopt.Optimizer()

    # Test Name
    @test MOI.supports(model, MOI.Name())
    @test MOI.get(model, MOI.Name()) == "Model" # Your default
    MOI.set(model, MOI.Name(), "MyConoptModel")
    @test MOI.get(model, MOI.Name()) == "MyConoptModel"

    # Test Silent
    @test MOI.supports(model, MOI.Silent())
    MOI.set(model, MOI.Silent(), true)
    @test MOI.get(model, MOI.Silent()) == true
    @test model.inner.silent == true

    MOI.set(model, MOI.Silent(), false)
    @test MOI.get(model, MOI.Silent()) == false
    @test model.inner.silent == false
    return
end

function test_TimeLimitSec()
    model = Conopt.Optimizer()

    @test MOI.supports(model, MOI.TimeLimitSec())
    @test MOI.get(model, MOI.TimeLimitSec()) == 1e+06 # Your default

    # Test setting a limit
    MOI.set(model, MOI.TimeLimitSec(), 500.0)
    @test MOI.get(model, MOI.TimeLimitSec()) == 500.0
    @test model.timelimit == 500.0

    # Test resetting to default
    MOI.set(model, MOI.TimeLimitSec(), nothing)
    @test MOI.get(model, MOI.TimeLimitSec()) == 1e+06
    return
end

function test_NumberOfThreads()
    model = Conopt.Optimizer()

    @test MOI.supports(model, MOI.NumberOfThreads())
    @test MOI.get(model, MOI.NumberOfThreads()) == 0 # Your default

    # Test setting threads
    MOI.set(model, MOI.NumberOfThreads(), 4)
    @test MOI.get(model, MOI.NumberOfThreads()) == 4
    @test model.threads == 4

    # Test resetting to default
    MOI.set(model, MOI.NumberOfThreads(), nothing)
    @test MOI.get(model, MOI.NumberOfThreads()) == 0
    return
end

function test_RawOptimizerAttribute()
    model = Conopt.Optimizer()

    @test MOI.supports(model, MOI.RawOptimizerAttribute("AnyString"))

    # Test standard parameter setting
    attr = MOI.RawOptimizerAttribute("my_custom_tol")
    MOI.set(model, attr, 1e-5)
    @test MOI.get(model, attr) == 1e-5
    @test model.params["my_custom_tol"] == 1e-5

    # Test getting an unset parameter throws an error
    bad_attr = MOI.RawOptimizerAttribute("does_not_exist")
    @test_throws MOI.GetAttributeNotAllowed MOI.get(model, bad_attr)

    # Test the custom LogLevel interceptor
    log_attr = MOI.RawOptimizerAttribute("LogLevel")

    # Valid LogLevel
    MOI.set(model, log_attr, 2)
    @test model.inner.log_level == 2

    # Invalid LogLevel triggers @error macro
    # (Testing that Julia's @error logging system catches your error message)
    @test_logs (:error, r"Invalid value for LogLevel") MOI.set(model, log_attr, 5)
    @test_logs (:error, r"Invalid value for LogLevel") MOI.set(model, log_attr, 0)
    return
end

function test_Unsupported_Limits()
    model = Conopt.Optimizer()

    # Ensure CONOPT explicitly rejects attributes it doesn't support
    @test !MOI.supports(model, MOI.ObjectiveLimit())
    @test !MOI.supports(model, MOI.SolutionLimit())
    @test !MOI.supports(model, MOI.NodeLimit())
    @test !MOI.supports(model, MOI.AbsoluteGapTolerance())
    @test !MOI.supports(model, MOI.RelativeGapTolerance())
    return
end

function test_Status_Mappings()
    model = Conopt.Optimizer()

    # Before solve
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

    model.inner.model_data.num_variables = 1

    # Mocking the C-API internal state to test the mapping logic safely
    model.inner.solution_status.status_stored = true

    # Test: LOCALLY_SOLVED
    model.inner.solution_status.solve_status = Conopt.SolveStatus_Normal_Completion
    model.inner.solution_status.model_status = Conopt.ModelStatus_Locally_Optimal
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT

    # Test: INFEASIBLE_OR_UNBOUNDED
    model.inner.solution_status.model_status = Conopt.ModelStatus_Infeasible
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.INFEASIBLE_OR_UNBOUNDED
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.INFEASIBLE_POINT

    # Test: TIME_LIMIT
    model.inner.solution_status.solve_status = Conopt.SolveStatus_Timelimit
    # Model status shouldn't matter for termination if it hit a time limit in your current logic
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.TIME_LIMIT

    # Test: ITERATION_LIMIT
    model.inner.solution_status.solve_status = Conopt.SolveStatus_Iteration_Interrupt
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
    return
end

function test_Objective_Sense_Mappings()
    model = Conopt.Optimizer()

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    @test model.inner.model_data.sense == Conopt.ObjSense_Minimize

    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    @test model.inner.model_data.sense == Conopt.ObjSense_Maximize

    MOI.set(model, MOI.ObjectiveSense(), MOI.FEASIBILITY_SENSE)
    @test model.inner.model_data.sense == Conopt.ObjSense_Feasibility
    return
end

end # module TestConopt

# This line at the end of the file runs all the tests!
TestConopt.runtests()
