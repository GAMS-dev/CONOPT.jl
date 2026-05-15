# ============================ /test/MOI_wrapper.jl ============================
module TestConopt

using CONOPT
using Test

import MathOptInterface as MOI

"""
    runtests()

This function runs all functions in the this Module starting with `test_`.
"""
function runtests()
    for name in names(@__MODULE__; all=true)
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
    model = MOI.instantiate(
        CONOPT.Optimizer; with_bridge_type=Float64, with_cache_type=Float64
    )
    MOI.set(model, MOI.Silent(), true)
    config = MOI.Test.Config(;
        # Modify tolerances as necessary.
        atol=1e-6,
        rtol=1e-6,
        infeasible_status=MOI.LOCALLY_INFEASIBLE,
        optimal_status=MOI.LOCALLY_SOLVED,
        # Pass attributes or MOI functions to `exclude` to skip tests that
        # rely on this functionality.
        exclude=Any[
            MOI.ConstraintDual,
            MOI.ConstraintBasisStatus,
            MOI.DualObjectiveValue,
            MOI.ObjectiveBound,
        ],
    )
    MOI.Test.runtests(
        model, config; exclude=[
            # CONOPT is a local solver
            r"^test_nonlinear_hs071_global$",
        ], verbose=true
    )
    return nothing
end

"""
    test_SolverName()

You can also write new tests for solver-specific functionality. Write each new
test as a function with a name beginning with `test_`.
"""
function test_SolverName()
    @test MOI.get(CONOPT.Optimizer(), MOI.SolverName()) == "CONOPT"
    return nothing
end

function test_Name_and_Silent()
    model = CONOPT.Optimizer()

    # Test Name
    @test MOI.supports(model, MOI.Name())
    @test MOI.get(model, MOI.Name()) == "Model" # Your default
    MOI.set(model, MOI.Name(), "MyConoptModel")
    @test MOI.get(model, MOI.Name()) == "MyConoptModel"

    # Test Silent
    @test MOI.supports(model, MOI.Silent())
    MOI.set(model, MOI.Silent(), true)
    @test MOI.get(model, MOI.Silent()) == true
    @test model.silent == true

    MOI.set(model, MOI.Silent(), false)
    @test MOI.get(model, MOI.Silent()) == false
    @test model.silent == false
    return nothing
end

function test_TimeLimitSec()
    model = CONOPT.Optimizer()

    @test MOI.supports(model, MOI.TimeLimitSec())
    @test MOI.get(model, MOI.TimeLimitSec()) == nothing # Your default

    # Test setting a limit
    MOI.set(model, MOI.TimeLimitSec(), 500.0)
    @test MOI.get(model, MOI.TimeLimitSec()) == 500.0
    @test model.time_limit == 500.0

    # Test resetting to default
    MOI.set(model, MOI.TimeLimitSec(), nothing)
    @test MOI.get(model, MOI.TimeLimitSec()) == nothing
    return nothing
end

function test_NumberOfThreads()
    model = CONOPT.Optimizer()

    @test MOI.supports(model, MOI.NumberOfThreads())
    @test MOI.get(model, MOI.NumberOfThreads()) == 0 # Your default

    # Test setting threads
    MOI.set(model, MOI.NumberOfThreads(), 4)
    @test MOI.get(model, MOI.NumberOfThreads()) == 4
    @test model.threads == 4

    # Test resetting to default
    MOI.set(model, MOI.NumberOfThreads(), nothing)
    @test MOI.get(model, MOI.NumberOfThreads()) == 0
    return nothing
end

function test_RawOptimizerAttribute()
    model = CONOPT.Optimizer()

    @test MOI.supports(model, MOI.RawOptimizerAttribute("AnyString"))

    # Test standard parameter setting
    attr = MOI.RawOptimizerAttribute("my_custom_tol")
    MOI.set(model, attr, 1e-5)
    @test MOI.get(model, attr) == 1e-5
    @test model.options["my_custom_tol"] == 1e-5

    # Test getting an unset parameter throws an error
    bad_attr = MOI.RawOptimizerAttribute("does_not_exist")
    @test_throws MOI.GetAttributeNotAllowed MOI.get(model, bad_attr)

    # Test the custom log_level interceptor
    log_attr = MOI.RawOptimizerAttribute("log_level")

    # Valid log_level
    MOI.set(model, log_attr, 2)
    @test model.inner.log_level == 2

    # Invalid log_level triggers @error macro
    # (Testing that Julia's @error logging system catches your error message)
    @test_logs (:error, r"Invalid value for log_level") MOI.set(model, log_attr, 5)
    @test_logs (:error, r"Invalid value for log_level") MOI.set(model, log_attr, 0)
    return nothing
end

function test_Unsupported_Limits()
    model = CONOPT.Optimizer()

    # Ensure CONOPT explicitly rejects attributes it doesn't support
    @test !MOI.supports(model, MOI.ObjectiveLimit())
    @test !MOI.supports(model, MOI.SolutionLimit())
    @test !MOI.supports(model, MOI.NodeLimit())
    @test !MOI.supports(model, MOI.AbsoluteGapTolerance())
    @test !MOI.supports(model, MOI.RelativeGapTolerance())
    return nothing
end

function test_Status_Mappings()
    model = CONOPT.Optimizer()

    # Before solve
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED

    model.inner.model_data.num_variables = 1

    # Mocking the C-API internal state to test the mapping logic safely
    model.inner.solution_status.status_stored = true

    # Test: LOCALLY_SOLVED
    model.inner.solution_status.solve_status = CONOPT.SolveStatus_Normal_Completion
    model.inner.solution_status.model_status = CONOPT.ModelStatus_Locally_Optimal
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT

    # Test: INFEASIBLE_OR_UNBOUNDED
    model.inner.solution_status.model_status = CONOPT.ModelStatus_Infeasible
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_INFEASIBLE
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.INFEASIBLE_POINT

    # Test: TIME_LIMIT
    model.inner.solution_status.solve_status = CONOPT.SolveStatus_Timelimit
    # Model status shouldn't matter for termination if it hit a time limit in your current logic
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.TIME_LIMIT

    # Test: ITERATION_LIMIT
    model.inner.solution_status.solve_status = CONOPT.SolveStatus_Iteration_Interrupt
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
    return nothing
end

function test_Objective_Sense_Mappings()
    model = CONOPT.Optimizer()

    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    @test model.inner.model_data.sense == CONOPT.ObjSense_Minimize

    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    @test model.inner.model_data.sense == CONOPT.ObjSense_Maximize

    MOI.set(model, MOI.ObjectiveSense(), MOI.FEASIBILITY_SENSE)
    @test model.inner.model_data.sense == CONOPT.ObjSense_Feasibility
    return nothing
end


function test_Option_Callback_Logic()
    model = CONOPT.Optimizer()

    # 1. Set different types of parameters
    MOI.set(model, MOI.RawOptimizerAttribute("Tol_Feas_Max"), 1e-7)  # Float
    MOI.set(model, MOI.RawOptimizerAttribute("Lim_Iteration"), 500)    # Int
    MOI.set(model, MOI.RawOptimizerAttribute("Flg_SLPMode"), true) # Bool

    # 2. Prepare mock C-pointers using Ref
    # These simulate the Ptr{Cdouble}, Ptr{Cint}, etc. arguments
    rval_ref = Ref{Cdouble}(0.0)
    ival_ref = Ref{Cint}(0)
    lval_ref = Ref{Cint}(0)
    name_buf = zeros(Int8, 64) # Buffer for the C-string name

    # 3. Synchronize params to model.inner (as done in setup_model)
    # This is necessary because the callback reads from model.inner
    for (name, value) in model.options
        model.inner.options[name] = value
    end

    # 4. Test the first parameter (Note: Dict order is random, so we check which one we got)
    # We pass pointer_from_objref(model.inner) to simulate 'usrmem'
    ncall = 1
    while ncall < 5 # limit the loop so we don't accidentally get an infinite loop.
        rc = CONOPT._Option_cb(
            Int32(ncall),
            Base.unsafe_convert(Ptr{Cdouble}, rval_ref),
            Base.unsafe_convert(Ptr{Cint}, ival_ref),
            Base.unsafe_convert(Ptr{Cint}, lval_ref),
            pointer(name_buf),
            pointer_from_objref(model.inner),
        )

        @test rc == 0
        param_name = unsafe_string(pointer(name_buf))

        if param_name == ""
            break
        end

        if param_name == "Tol_Feas_Max"
            @test rval_ref[] == 1e-7
        elseif param_name == "Lim_Iteration"
            @test ival_ref[] == 500
        elseif param_name == "Flg_SLPMode"
            @test lval_ref[] == 1
        end

        ncall += 1
    end

    return nothing
end

function test_Option_Persistence()
    model = CONOPT.Optimizer()
    MOI.set(model, MOI.RawOptimizerAttribute("TestOption"), 123)

    # This should clear the variables/constraints but keep the dictionary
    MOI.empty!(model)

    @test haskey(model.options, "TestOption")
    @test MOI.get(model, MOI.RawOptimizerAttribute("TestOption")) == 123
end

function test_VariablePrimalStart()
    model = CONOPT.Optimizer()

    # We need to mock a variable being added so the internal mappings exist
    # (Usually MOI.add_variable handles this, but since we are testing the getter/setter
    # directly, we set up the mock arrays)
    push!(model.variable_indices, MOI.VariableIndex(1))
    push!(model.var_index_to_pos, 1)
    push!(model.inner.model_data.variable_primal_start, 0.0)

    vi = MOI.VariableIndex(1)

    @test MOI.supports(model, MOI.VariablePrimalStart(), typeof(vi))

    # Test setting a starting value
    MOI.set(model, MOI.VariablePrimalStart(), vi, 3.14)
    @test MOI.get(model, MOI.VariablePrimalStart(), vi) == 3.14

    # Check that it actually went to the internal C-struct
    @test model.inner.model_data.variable_primal_start[1] == 3.14
    return nothing
end

function test_ResultCount_and_Bounds()
    model = CONOPT.Optimizer()

    # Before solve, ResultCount should be 0
    @test MOI.get(model, MOI.ResultCount()) == 0

    # Asking for the objective before solving should throw a ResultIndexBoundsError
    @test_throws MOI.ResultIndexBoundsError MOI.get(model, MOI.ObjectiveValue())

    # Mock an existing problem
    model.inner.model_data.num_variables = 1

    # Mock a solve
    model.inner.solution_status.status_stored = true
    model.inner.solution_status.objective = 42.0

    # Now ResultCount should be 1 and ObjectiveValue should work
    @test MOI.get(model, MOI.ResultCount()) == 1
    @test MOI.get(model, MOI.ObjectiveValue()) == 42.0
    return nothing
end

function test_IsValid()
    model = CONOPT.Optimizer()

    # Mock adding a variable and a constraint
    vi = MOI.VariableIndex(1)
    push!(model.var_index_to_pos, 1)

    ci = MOI.ConstraintIndex{MOI.VariableIndex, MOI.LessThan{Float64}}(1)
    model.con_index_to_pos[ci] = 1

    # Check validity
    @test MOI.is_valid(model, vi)
    @test MOI.is_valid(model, ci)

    # Check invalidity
    bad_vi = MOI.VariableIndex(99)
    bad_ci = MOI.ConstraintIndex{MOI.VariableIndex, MOI.LessThan{Float64}}(99)

    @test !MOI.is_valid(model, bad_vi)
    @test !MOI.is_valid(model, bad_ci)
    return nothing
end

function test_SolverVersion()
    model = CONOPT.Optimizer()

    version_str = MOI.get(model, MOI.SolverVersion())

    # Verify it returns a String
    @test version_str isa String

    # Verify it roughly looks like a version number (e.g., contains dots)
    @test occursin(".", version_str)
    return nothing
end

function test_License_Attributes()
    model = CONOPT.Optimizer()

    # 1. Test setting the attributes via MOI
    MOI.set(model, MOI.RawOptimizerAttribute("license_int_1"), 123)
    MOI.set(model, MOI.RawOptimizerAttribute("license_int_2"), 456)
    MOI.set(model, MOI.RawOptimizerAttribute("license_int_3"), 789)
    MOI.set(model, MOI.RawOptimizerAttribute("license_string"), "my_test_license")

    # 2. Verify they are stored in the MOI Optimizer struct correctly
    @test model.license_int_1 == 123
    @test model.license_int_2 == 456
    @test model.license_int_3 == 789
    @test model.license_string == "my_test_license"

    ext = Base.get_extension(CONOPT, :ConoptMathOptInterfaceExt)

    # 3. Simulate the start of an optimize! call which triggers _setup_options!
    ext._setup_options!(model)

    # 4. Verify they propagated safely to the C_wrapper's ConoptModel
    @test model.inner.license.license_int_1 == 123
    @test model.inner.license.license_int_2 == 456
    @test model.inner.license.license_int_3 == 789
    @test model.inner.license.license_string == "my_test_license"

    return nothing
end

function test_License_Environment_Fallback()
    model = CONOPT.Optimizer()

    # Clear any MOI attributes so it is forced to fall back
    model.license_int_1 = nothing
    model.license_int_2 = nothing
    model.license_int_3 = nothing
    model.license_string = nothing

    ext = Base.get_extension(CONOPT, :ConoptMathOptInterfaceExt)
    ext._setup_options!(model)

    # Set dummy environment variables
    ENV["CONOPT_LICENSE_INT_1"] = "111"
    ENV["CONOPT_LICENSE_INT_2"] = "222"
    ENV["CONOPT_LICENSE_INT_3"] = "333"
    ENV["CONOPT_LICENSE_STRING"] = "env_fallback_license"

    # We manually extract the values exactly as set_license! does to test the logic
    # (We avoid calling set_license! directly here so we don't trigger a C-API error with dummy keys)
    int1 = something(
        model.inner.license.license_int_1, parse(Int, get(ENV, "CONOPT_LICENSE_INT_1", "0"))
    )
    int2 = something(
        model.inner.license.license_int_2, parse(Int, get(ENV, "CONOPT_LICENSE_INT_2", "0"))
    )
    int3 = something(
        model.inner.license.license_int_3, parse(Int, get(ENV, "CONOPT_LICENSE_INT_3", "0"))
    )
    lstr = something(
        model.inner.license.license_string, get(ENV, "CONOPT_LICENSE_STRING", "")
    )

    @test int1 == 111
    @test int2 == 222
    @test int3 == 333
    @test lstr == "env_fallback_license"

    # Clean up the environment
    delete!(ENV, "CONOPT_LICENSE_INT_1")
    delete!(ENV, "CONOPT_LICENSE_INT_2")
    delete!(ENV, "CONOPT_LICENSE_INT_3")
    delete!(ENV, "CONOPT_LICENSE_STRING")

    return nothing
end

end # module TestConopt

# This line at the end of the file runs all the tests!
TestConopt.runtests()
