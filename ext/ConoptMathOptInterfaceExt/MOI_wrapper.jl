###
### Structures and constants
###

const CONOPT_INF = 1e15

mutable struct Optimizer <: MOI.AbstractOptimizer
    inner::Conopt.ConoptModel
    timelimit::Real             # time limit in seconds
    name::String                # name of the model
    params::Dict{String,Any}    # solver parameters
    threads::Int                # number of threads (0 is default, tells CONOPT to use the maximum number of threads)

    # parameters
    lim_variable::Real           # largest absolute value of a variable beyond which it is considered unbounded

    # NLP data
    nlp_model::Union{Nothing,MOI.Nonlinear.Model} # specialised NLP model structure
    nlp_data::MOI.NLPBlockData  # NLP data structure to make use of MOI's evaluation functionality
    ad_backend::MOI.Nonlinear.AbstractAutomaticDifferentiation # automatic differentiation backend

    # variable mapping MOI to Conopt
    variable_indices::Vector{MOI.VariableIndex} # list of variable indices

    solve_time::Float64         # stores the solve time

    # constructor
    function Optimizer()
        model = new(
            Conopt.ConoptModel(),
            1e+06,                  # time limit
            "Model",                # model name
            Dict{String,String}(),  # parameters
            0,                      # default number of threads
            1e+15,                  # CONOPT's default Lim_Variable parameter

            MOI.Nonlinear.Model(),  # NLP model
            MOI.NLPBlockData([], _EmptyNLPEvaluator(), false), # empty block data
            MOI.Nonlinear.SparseReverseMode(), # automatic differentiation

            MOI.VariableIndex[],        # list of variable indices
            NaN,
        )
        return model
    end
end

const _SETS = Union{
    MOI.GreaterThan{Float64},
    MOI.LessThan{Float64},
    MOI.EqualTo{Float64},
    MOI.Interval{Float64},
}

const _FUNCTIONS = Union{
    MOI.VariableIndex,
    MOI.ScalarAffineFunction{Float64},
    MOI.ScalarQuadraticFunction{Float64},
    MOI.ScalarNonlinearFunction,
}



###
### implementations of some basic functions
###

function Base.summary(io::IO, model::Optimizer)
    return print(io, "CONOPT solver with the control vector pointer $(model.inner.cntvect)")
end

function MOI.is_empty(model::Optimizer)
    # TODO actually check if the model is empty
    return Conopt.is_empty(model.inner)
end

function MOI.empty!(model::Optimizer)
    empty!(model.params)

    # destroying the existing Conopt model, which will call free on the control vector
    model.inner = Conopt.ConoptModel()

    model.nlp_model = MOI.Nonlinear.Model()
    model.nlp_data = MOI.NLPBlockData([], _EmptyNLPEvaluator(), false)

    empty!(model.variable_indices)
    return
end



###
### get, set and supports functions for various Optimizer attributes
###

# solver name
MOI.get(::Optimizer, ::MOI.SolverName) = "Conopt"

# solver version
function MOI.get(::Optimizer, ::MOI.SolverVersion)::String
    major = Ref{Cint}(0)
    minor = Ref{Cint}(0)
    patch = Ref{Cint}(0)
    LibConopt.COIGET_Version(major, minor, patch)
    return string(major[], ".", minor[], ".", patch[])
end

# raw solver
MOI.get(model::Optimizer, ::MOI.RawSolver) = model.inner.cntvect

# model name
MOI.supports(::Optimizer, ::MOI.Name) = true

MOI.get(model::Optimizer, ::MOI.Name) = model.name

function MOI.set(model::Optimizer, ::MOI.Name, value::String)
    if value == model.name
        return
    end
    model.name = value
    return
end

# silent
MOI.supports(::Optimizer, ::MOI.Silent) = true

MOI.get(model::Optimizer, ::MOI.Silent) = model.silent

function MOI.set(model::Optimizer, ::MOI.Silent, value::Bool)
    model.inner.silent = value
    return
end

# time limit
# TODO: consider whether this should be moved to ConoptModel
MOI.supports(::Optimizer, ::MOI.TimeLimitSec) = true

function MOI.set(model::Optimizer, ::MOI.TimeLimitSec, value::Real)
    if value == mode
        return
    end
    model.timelimit = value
    coierror = LibConopt.COIDEF_ResLim(model.cntvect[], value);
    if coierror != 0
        error("could not set CONOPT time limit")
    end
    return
end

function MOI.set(model::Optimizer, ::MOI.TimeLimitSec, ::Nothing)
    # removing the time limit -> set the time limit to CONOPT's default
    if 1e+06 == model.timelimit
        return
    end
    model.timelimit = 1e+06
    coierror = LibConopt.COIDEF_ResLim(model.cntvect[], 1e+06);
    if coierror != 0
        error("could not reset CONOPT time limit")
    end
    return
end

MOI.get(model::Optimizer, ::MOI.TimeLimitSec) = model.timelimit

# objective and solution limits - currently no way to set these in CONOPT
MOI.supports(::Optimizer, ::MOI.ObjectiveLimit) = false
MOI.supports(::Optimizer, ::MOI.SolutionLimit) = false

# node limit - CONOPT isn't a branch and bound solver, so this makes no sense
MOI.supports(::Optimizer, ::MOI.NodeLimit) = false

# solver attributes
MOI.supports(::Optimizer, ::MOI.RawOptimizerAttribute) = true


"""
    function MOI.set(model::Optimizer, param::MOI.RawOptimizerAttribute, value)

    method for setting raw attributes the Conopt. This is used to pass attributed through to the
    options callback. However, it also intercepts additional options, such as "LogLevel"
"""
function MOI.set(model::Optimizer, param::MOI.RawOptimizerAttribute, value)
    option_name = attr.name

    if option_name == "LogLevel"
        log_level_value = Int(value)
        if log_level_value < 1 || log_level_value > 4
            @error "Invalid value for LogLevel <" * log_level_value * ">. It must be between 1 and 4"
        end
        model.log_level = Int(value)
    else
        model.params[param.name] = value
    end

    return
end

function MOI.get(model::Optimizer, param::MOI.RawOptimizerAttribute)
    if !haskey(model.options, param.name)
        msg = "RawOptimizerAttribute with name $(param.name) is not already set."
        throw(MOI.GetAttributeNotAllowed(param, msg))
    end
    return model.params[param.name]
end

# number of threads
MOI.supports(::Optimizer, ::MOI.NumberOfThreads) = true

function MOI.set(model::Optimizer, ::MOI.NumberOfThreads, value::Integer)
    coierror = LibConopt.COIDEF_ThreadS(model.cntvect[], value);
    if coierror != 0
        error("could not set CONOPT number of threads")
    end
    model.threads = value
    return
end

function MOI.set(model::Optimizer, ::MOI.NumberOfThreads, ::Nothing)
    coierror = LibConopt.COIDEF_ThreadS(model.cntvect[], 0);
    if coierror != 0
        error("could not reset CONOPT number of threads")
    end
    model.threads = 0
    return
end

MOI.get(model::Optimizer, ::MOI.NumberOfThreads) = model.threads

# gap tolerances not supported by CONOPT
MOI.supports(::Optimizer, ::MOI.AbsoluteGapTolerance) = false
MOI.supports(::Optimizer, ::MOI.RelativeGapTolerance) = false

###
### indicate which constraints CONOPT supports
###

# TODO implement support for these
# support constraints of the form x in S, where S = {x | l <= f(x) <= u}
#function MOI.supports_constraint(
#    ::Optimizer,
#    ::Type{MOI.VectorOfVariables},
#    ::Type{MOI.VectorNonlinearOracle{Float64}},
#)
#    return true
#end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:_FUNCTIONS},
    ::Type{<:_SETS}
)
    return true
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VariableIndex},
    ::Type{MOI.Interval{Float64}}
)
    return true
end


function MOI.supports(
    ::Optimizer,
    ::Union{
        MOI.ObjectiveSense,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}},
        MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}},
        MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction},
    },
)
    return true
end

_column(vi::MOI.VariableIndex) = vi.value
_row(ci::MOI.ConstraintIndex) = ci.value

### starting values of primal variables

function MOI.is_valid(model::Optimizer, vi::MOI.VariableIndex)
    # The variable is valid if its index is greater than 0
    # and less than or equal to the total number of variables.
    return 1 <= vi.value <= model.inner.model_data.num_variables
end

function MOI.is_valid(model::Optimizer, ci::MOI.ConstraintIndex)
    # The variable is valid if its index is greater than 0
    # and less than or equal to the total number of variables.
    return 1 <= ci.value <= model.inner.model_data.num_constraints
end

function MOI.supports(
    ::Optimizer,
    ::MOI.VariablePrimalStart,
    ::Type{MOI.VariableIndex},
)
    return true
end

function MOI.get(
    model::Optimizer,
    attr::MOI.VariablePrimalStart,
    vi::MOI.VariableIndex,
)
    if _is_parameter(vi)
        throw(MOI.GetAttributeNotAllowed(attr, "Variable is a Parameter"))
    end
    MOI.throw_if_not_valid(model, vi)
    return model.inner.model_data.variable_primal_start[vi.value]
end

function MOI.set(
    model::Optimizer,
    attr::MOI.VariablePrimalStart,
    vi::MOI.VariableIndex,
    value::Union{Real,Nothing},
)
    if _is_parameter(vi)
        throw(MOI.SetAttributeNotAllowed(attr, "Variable is a Parameter"))
    end
    MOI.throw_if_not_valid(model, vi)
    model.inner.model_data.variable_primal_start[vi.value] = value
    return
end

###
### _EmptyNLPEvaluator
###
struct _EmptyNLPEvaluator <: MOI.AbstractNLPEvaluator end

MOI.features_available(::_EmptyNLPEvaluator) = [:Grad, :Jac, :Hess]
MOI.initialize(::_EmptyNLPEvaluator, ::Any) = nothing
MOI.eval_constraint(::_EmptyNLPEvaluator, g, x) = nothing
MOI.jacobian_structure(::_EmptyNLPEvaluator) = Tuple{Int64,Int64}[]
MOI.hessian_lagrangian_structure(::_EmptyNLPEvaluator) = Tuple{Int64,Int64}[]
MOI.eval_constraint_jacobian(::_EmptyNLPEvaluator, J, x) = nothing
MOI.eval_hessian_lagrangian(::_EmptyNLPEvaluator, H, x, σ, μ) = nothing



###
### Setting up the model
###

MOI.supports_incremental_interface(::Optimizer) = false

"""
    function _update_variable_bounds(model_data::ModelData, var_index::Int; lower::Float64 = -Inf, upper::Float64 = Inf)

    updates the variable bounds and also updates the primal start to fit between the bounds
"""
function _update_variable_bounds(model_data::Conopt.ModelData, var_index::Int; lower::Float64 = -Inf, upper::Float64 = Inf)
    if lower > -Inf
        model_data.variable_lower[var_index] = lower
    end

    if upper < Inf
        model_data.variable_upper[var_index] = upper
    end

    model_data.variable_primal_start[var_index] = clamp(
            model_data.variable_primal_start[var_index],
            model_data.variable_lower[var_index],
            model_data.variable_upper[var_index]
           )
end


"""
    function _setup_variables!(dest::Optimizer, src::MOI.ModelLike)

    extracts the variable information from the JuMP model and stores this in a local data structure.
    This data is passed to Conopt through the user memory pointer. The variable information is
    processed in the ReadMatrix callback.
"""
function _setup_variables!(dest::Optimizer, src::MOI.ModelLike)
    dest.variable_indices = MOI.get(src, MOI.ListOfVariableIndices())
    n_vars = length(dest.variable_indices)
    dest.inner.model_data.num_variables = n_vars

    dest.inner.model_data.variable_primal_start = zeros(Float64, n_vars)
    dest.inner.model_data.variable_lower = fill(-CONOPT_INF, n_vars)
    dest.inner.model_data.variable_upper = fill(CONOPT_INF, n_vars)

    for v in dest.variable_indices
        index = v.value

        start_val = MOI.get(src, MOI.VariablePrimalStart(), v)
        if start_val !== nothing
            dest.inner.model_data.variable_primal_start[index] = start_val
        else
            dest.inner.model_data.variable_primal_start[index] = 0.0
        end
    end
    return
end


function _get_objective_constant(model::Optimizer)::Float64
    #F = MOI.get(model, MOI.ObjectiveFunctionType())

    #if F == MOI.VariableIndex
        ## e.g., @objective(model, Min, x) -> No constant
        #return 0.0

    #elseif F == MOI.ScalarAffineFunction{Float64} || F == MOI.ScalarQuadraticFunction{Float64}
        # e.g., @objective(model, Min, 2x + 5) -> Constant is 5.0
        obj_func = MOI.get(model, MOI.ObjectiveFunction())
        return obj_func.constant

    #else
        ## If it's a purely nonlinear objective managed by the NLPBlock,
        ## the constant is baked into the evaluator tree.
        #return 0.0
    #end
end


function _set_objective_sense!(model::Optimizer, sense::MOI.OptimizationSense)
    if sense == MOI.MIN_SENSE
        model.inner.model_data.sense = Conopt.ObjSense_Minimize
    elseif sense == MOI.MAX_SENSE
        model.inner.model_data.sense = Conopt.ObjSense_Maximize
    elseif sense == MOI.FEASIBILITY_SENSE
        model.inner.model_data.sense = Conopt.ObjSense_Feasibility
    else
        error("Unknown objective sense: $sense")
    end
end

"""
    function _setup_constraints!(dest::Optimizer, src::MOI.ModelLike)

    extracts the constraint data from the JuMP model and stores this in a local data structure.
    The data structure is passed as the user memory in Conopt, and is read in the ReadMatrix method.
"""
function _setup_constraints!(dest::Optimizer, src::MOI.ModelLike)::Vector{Int}
    ranged_indices = Vector{Int}()
    dest.inner.model_data.num_constraints = 0
    dest.inner.model_data.num_ranged = 0

    dest.inner.model_data.constraint_rhs = Float64[]
    dest.inner.model_data.constraint_type = Cint[]

    for f in Base.uniontypes(_FUNCTIONS)
        for set in Base.uniontypes(_SETS)
            nconss = MOI.get(src, MOI.NumberOfConstraints{f, set}())
            if nconss == 0; continue; end

            conss_indices = MOI.get(src, MOI.ListOfConstraintIndices{f,set}())

            for index in conss_indices
                cons_set = MOI.get(src, MOI.ConstraintSet(), index)
                cons_function = MOI.get(src, MOI.ConstraintFunction(), index)

                if f == MOI.VariableIndex
                    index = cons_function.value

                    if set <: MOI.GreaterThan
                        _update_variable_bounds(dest.inner.model_data, index, lower=MOI.constant(cons_set))
                    elseif set <: MOI.LessThan
                        _update_variable_bounds(dest.inner.model_data, index, upper=MOI.constant(cons_set))
                    elseif set <: MOI.EqualTo
                        _update_variable_bounds(dest.inner.model_data, index, lower=MOI.constant(cons_set), upper=MOI.constant(cons_set))
                    elseif set <: MOI.Interval
                        println("Interval")
                        _update_variable_bounds(dest.inner.model_data, index, lower=cons_set.lower, upper=cons_set.upper)
                    end
                else
                    dest.inner.model_data.num_constraints += 1

                    if set <: MOI.GreaterThan
                        push!(dest.inner.model_data.constraint_rhs, MOI.constant(cons_set))
                        push!(dest.inner.model_data.constraint_type, 1)
                    elseif set <: MOI.LessThan
                        push!(dest.inner.model_data.constraint_rhs, MOI.constant(cons_set))
                        push!(dest.inner.model_data.constraint_type, 2)
                    elseif set <: MOI.EqualTo
                        push!(dest.inner.model_data.constraint_rhs, MOI.constant(cons_set))
                        push!(dest.inner.model_data.constraint_type, 0)
                    elseif set <: MOI.Interval
                        dest.inner.model_data.num_ranged += 1
                        push!(ranged_indices, dest.inner.model_data.num_constraints)
                        push!(dest.inner.model_data.constraint_rhs, 0.0)
                        push!(dest.inner.model_data.constraint_type, 0)

                        push!(dest.inner.model_data.variable_lower, cons_set.lower)
    push!(dest.inner.model_data.variable_upper, cons_set.upper)
                        push!(dest.inner.model_data.variable_primal_start, clamp(0.0, cons_set.lower, cons_set.upper))
                    end

                    MOI.Nonlinear.add_constraint(dest.nlp_model, cons_function, cons_set)
                end
            end
        end
    end

    # Handle Objective
    obj_attr = nothing
    for attr in MOI.get(src, MOI.ListOfModelAttributesSet())
        if attr isa MOI.ObjectiveFunction
            obj_attr = attr
            break
        end
    end

    if obj_attr !== nothing
        obj = MOI.get(src, obj_attr)
        MOI.Nonlinear.add_constraint(dest.nlp_model, obj, MOI.Interval(-CONOPT_INF, CONOPT_INF))

        dest.inner.model_data.num_constraints += 1
        dest.inner.model_data.objective_row_index = dest.inner.model_data.num_constraints
        push!(dest.inner.model_data.constraint_rhs, -obj.constant)
        push!(dest.inner.model_data.constraint_type, 3)
    end

    # setting the objective sense in the Conopt model data
    _set_objective_sense!(dest, MOI.get(src, MOI.ObjectiveSense()))

    return ranged_indices
end


"""
    function _setup_evaluator!(dest::Optimizer)

    setup the evaluator for the NLP. This is used to idenfity the nonlinear terms in the Jacobian
    and identify the structure of the Hessian.
"""
function _setup_evaluator!(dest::Optimizer)
    dest.nlp_data = MOI.NLPBlockData(
        MOI.Nonlinear.Evaluator(dest.nlp_model, dest.ad_backend, dest.variable_indices)
    )
    MOI.initialize(dest.nlp_data.evaluator, [:Jac, :Hess])
    return
end


"""
    function _setup_matrices!(dest::Optimizer, ranged_indices::Vector{Int})

    setup up the jacobian and hessian matrices in a form that can be supplied to Conopt
"""
function _setup_matrices!(dest::Optimizer, ranged_indices::Vector{Int})
    n_vars = dest.inner.model_data.num_variables

    # --- Jacobian Extraction and Setup ---
    raw_jac_str = MOI.jacobian_structure(dest.nlp_data.evaluator)
    total_jac_nnz = length(raw_jac_str)

    jac_vals = zeros(total_jac_nnz)
    MOI.eval_constraint_jacobian(dest.nlp_data.evaluator, jac_vals, dest.inner.model_data.variable_primal_start)

    p_jac = sortperm(1:total_jac_nnz, by = i -> (raw_jac_str[i][2], raw_jac_str[i][1]))
    sorted_rows = Cint[raw_jac_str[i][1] - 1 for i in p_jac]
    sorted_cols = Int[raw_jac_str[i][2] for i in p_jac]
    sorted_jac_vals = jac_vals[p_jac]

    dest.inner.jac_structure.start = zeros(Cint, n_vars + 1)
    for c in sorted_cols
        dest.inner.jac_structure.start[c + 1] += 1
    end
    for i in 1:n_vars
        dest.inner.jac_structure.start[i + 1] += dest.inner.jac_structure.start[i]
    end
    dest.inner.jac_structure.index = sorted_rows

    # --- Nonlinear Mapping via Hessian ---
    nonlinear_vars_in_row = [BitSet() for _ in 1:dest.inner.model_data.num_constraints]
    for r in 1:dest.inner.model_data.num_constraints
        hess_struct_r = MOI.hessian_constraint_structure(dest.nlp_data.evaluator, r)
        for (c1, c2) in hess_struct_r
            push!(nonlinear_vars_in_row[r], c1)
            push!(nonlinear_vars_in_row[r], c2)
        end
    end

    dest.inner.jac_structure.nlflag = zeros(Cint, total_jac_nnz)
    dest.inner.jac_structure.values = zeros(Float64, total_jac_nnz)
    dest.inner.eval_cache.row_to_jac_index = [Int[] for _ in 1:dest.inner.model_data.num_constraints]

    for i in 1:total_jac_nnz
        r = sorted_rows[i] + 1
        c = sorted_cols[i]
        if c in nonlinear_vars_in_row[r]
            dest.inner.jac_structure.nlflag[i] = Cint(1)
            dest.inner.jac_structure.values[i] = 0.0
            push!(dest.inner.eval_cache.row_to_jac_index[r], i)
        else
            dest.inner.jac_structure.nlflag[i] = Cint(0)
            dest.inner.jac_structure.values[i] = sorted_jac_vals[i]
        end
    end

    # --- Slack Variables ---
    slack_idx = dest.inner.model_data.num_variables + 1
    for i in 1:dest.inner.model_data.num_ranged
        push!(dest.inner.jac_structure.start, dest.inner.jac_structure.start[slack_idx - 1] + 1)
        push!(dest.inner.jac_structure.index, Cint(ranged_indices[i] - 1))
        push!(dest.inner.jac_structure.values, 1.0)
        push!(dest.inner.jac_structure.nlflag, Cint(0))
        slack_idx += 1
    end

    # --- Lagrangian Hessian Setup ---
    raw_hess_str = MOI.hessian_lagrangian_structure(dest.nlp_data.evaluator)
    p_hess = sortperm(1:length(raw_hess_str), by = i -> (raw_hess_str[i][2], raw_hess_str[i][1]))

    dest.inner.hess_structure.rows = Cint[raw_hess_str[i][1] - 1 for i in p_hess]
    dest.inner.hess_structure.cols = Cint[raw_hess_str[i][2] - 1 for i in p_hess]

    return
end

function setup_model(dest::Optimizer, src::MOI.ModelLike)
    # 1. Variables, Bounds, and Primal Starts
    _setup_variables!(dest, src)

    # 2. Constraints and Objective
    ranged_indices = _setup_constraints!(dest, src)

    # 3. Evaluator Initialization
    _setup_evaluator!(dest)

    # 4. Matrix and Hessian Construction
    _setup_matrices!(dest, ranged_indices)

    return
end



function setup_inner(model::Optimizer)
    # TODO check if we need to recreate everything

    Conopt.initialize!(model.inner)
end

# this allows to use Utilities.CachingOptimizer to get the model; copies the model from src to dest
function MOI.optimize!(dest::Optimizer, src::MOI.ModelLike)
    # TODO: what we need to get here: matrix of affine terms, obj and conss functions to evaluate, numbers of variables, nonzeroes, etc., Jacobian and Hessian structure, first and second derivative evaluations

    println("optimize! call for moving stuff")
    #MOI.empty!(dest)
    index_map = MOI.Utilities.identity_index_map(src) # this just maps variable and constraint indices to themselves

    show(src)
    println("\nmodel: ")
    show(src.model)

    setup_model(dest, src)
    setup_inner(dest)

    println("\ncalling solve!")

    start_time = time()

    result = Conopt.solve!(dest.inner)

    dest.solve_time = time() - start_time

    #error("stopping for now, result = ", string(result))

    return index_map, false
end

###
### Optimize and post-optimize functions
###

function MOI.optimize!(model::Optimizer)
    setup_model(model)
    #t = time()
    #model.variable_primal = nothing
    #model.constraint_primal = nothing
    #model.Cbc_solve_return_code = Cbc_solve(model)
    #model.has_solution = _result_count(model)
    #model.solve_time = time() - t
    #model.termination_status = _termination_status(model)
    return
end


### MOI.ResultCount

# Ipopt always has an iterate available.
function MOI.get(model::Optimizer, ::MOI.ResultCount)
    if Conopt.is_empty(model.inner)
        return 0
    end

    return model.inner.solution_status.status_stored ? 1 : 0
end


# solve status

function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    # this may not actually be true, since it is possible that there is a crash.
    if !model.inner.solution_status.status_stored
        return MOI.OPTIMIZE_NOT_CALLED
    end

    model_status = model.inner.solution_status.model_status
    solve_status = model.inner.solution_status.solve_status
    if solve_status == Conopt.SolveStatus_Normal_Completion
        if model_status == Conopt.ModelStatus_Optimal
            return MOI.OPTIMAL
        elseif model_status == Conopt.ModelStatus_Locally_Optimal
            return MOI.LOCALLY_SOLVED
        elseif model_status == Conopt.ModelStatus_Unbounded
            return MOI.DUAL_INFEASIBLE
        elseif model_status == Conopt.ModelStatus_Infeasible
            return MOI.INFEASIBLE_POINT
        elseif model_status == Conopt.ModelStatus_Locally_Infeasible
            return MOI.LOCALLY_INFEASIBLE
        # TODO: there are more model statuses. Need to see if they are needed.
        end
    elseif solve_status == Conopt.SolveStatus_Iteration_Interrupt
        return MOI.ITERATION_LIMIT
    elseif solve_status == Conopt.SolveStatus_Timelimit
        return MOI.TIME_LIMIT
    elseif solve_status == Conopt.SolveStatus_Terminated_Solver
        return MOI.OTHER_LIMIT
    elseif solve_status == Conopt.SolveStatus_Evaluation_Error_Limit
        return MOI.OTHER_LIMIT
    elseif solve_status == Conopt.SolveStatus_User_Interrupt
        return MOI.INTERRUPTED
    elseif solve_status == Conopt.SolveStatus_Error_Setup
        return MOI.OTHER_ERROR
    elseif solve_status == Conopt.SolveStatus_Solver_Error_NoPoint
        return MOI.OTHER_ERROR
    elseif solve_status == Conopt.SolveStatus_Solver_Error_Point
        return MOI.OTHER_ERROR
    elseif solve_status == Conopt.SolveStatus_General_System_Error
        return MOI.OTHER_ERROR
    elseif solve_status == Conopt.SolveStatus_Terminated_Quick_Mode
        return MOI.OTHER_LIMIT
    end
    return MOI.OPTIMIZE_NOT_CALLED
end

# raw status string explaining why the solver stopped
MOI.get(model::Optimizer, ::MOI.RawStatusString) = model.inner.raw_status

# solving time in seconds
MOI.get(model::Optimizer, ::MOI.SolveTimeSec) = model.solve_time

# the primal status - the status of the primal solution
function MOI.get(model::Optimizer, attr::MOI.PrimalStatus)
    MOI.check_result_index_bounds(model, attr)

    model_status = model.inner.solution_status.model_status
    if model_status == Conopt.ModelStatus_Optimal ||
        model_status == Conopt.ModelStatus_Locally_Optimal
        return MOI.FEASIBLE_POINT
    elseif model_status == Conopt.ModelStatus_Infeasible ||
        model_status == Conopt.ModelStatus_Locally_Infeasible ||
        model_status == Conopt.ModelStatus_Intermediate_Infeasible
        return MOI.INFEASIBLE_POINT
    end

    return MOI.UNKNOWN_RESULT_STATUS
end


# the dual status - the status of the dual solution
# NOTE: this is currently being taken from the model status. However, we could infer this result
# from the dual solution.
function MOI.get(model::Optimizer, attr::MOI.DualStatus)
    MOI.check_result_index_bounds(model, attr)

    model_status = model.inner.solution_status.model_status
    if model_status == Conopt.ModelStatus_Optimal ||
        model_status == Conopt.ModelStatus_Locally_Optimal
        return MOI.FEASIBLE_POINT
    elseif model_status == Conopt.ModelStatus_Unbounded
        return MOI.NO_SOLUTION
    end

    return MOI.UNKNOWN_RESULT_STATUS
end

### MOI.BarrierIterations
# NOTE: Conopt does perform the Barrier algorithm, so this is the iterations for the GRG algorithm.

MOI.get(model::Optimizer, ::MOI.BarrierIterations) = model.inner.solution_status.iterations

### MOI.ObjectiveValue

function MOI.get(model::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(model, attr)

    return model.inner.solution_status.objective
end

### MOI.VariablePrimal

function MOI.get(
    model::Optimizer,
    attr::MOI.VariablePrimal,
    vi::MOI.VariableIndex,
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, vi)
    return model.inner.solution_status.x_value[_column(vi)]
end


### MOI.ConstraintPrimal

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{F,<:_SETS},
) where {
    F<:Union{
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarQuadraticFunction{Float64},
        MOI.ScalarNonlinearFunction,
    },
}
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    return model.inner.solution_status.y_value[_row(ci)]
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,<:_SETS},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    return model.inner.solution_status.x_value[ci.value]
end

### MOI.ConstraintDual

_dual_multiplier(model::Optimizer) = model.inner.model_data.sense == Conopt.ObjSense_Minimize ? 1.0 : -1.0

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{F,<:_SETS},
) where {
    F<:Union{
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarQuadraticFunction{Float64},
        MOI.ScalarNonlinearFunction,
    },
}
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    s = _dual_multiplier(model)
    return s * model.inner.solution_status.y_marginal[_row(ci)]
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    if model.inner.solution_status.x_basis[ci.value] == 1
        rc = model.inner.solution_status.x_marginal[ci.value]
    else
        rc = 0
    end
    return min(0.0, _dual_multiplier(model) * rc)
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    if model.inner.solution_status.x_basis[ci.value] == 0
        rc = -model.inner.solution_status.x_marginal[ci.value]
    else
        rc = 0
    end
    return max(0.0, _dual_multiplier(model) * rc)
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    rc = model.inner.solution_status.x_marginal[ci.value]
    return _dual_multiplier(model) * rc
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex,MOI.Interval{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    if model.inner.solution_status.x_basis[ci.value] == 0 # on the lower bound
        rc = -model.inner.solution_status.x_marginal[ci.value]
    elseif model.inner.solution_status.x_basis[ci.value] == 1 # on the upper bound
        rc = model.inner.solution_status.x_marginal[ci.value]
    else
        rc = 0
    end
    return _dual_multiplier(model) * rc
end
