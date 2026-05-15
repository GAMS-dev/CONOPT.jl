###
### Structures and constants
###

const CONOPT_INF_DEFAULT = 1e15

mutable struct Optimizer <: MOI.AbstractOptimizer
    inner::CONOPT.ConoptModel
    name::String                # name of the model

    # parameters
    time_limit::Union{Real,Nothing}    # time limit in seconds
    log_level::Int              # the log level
    threads::Int                # number of threads (0 is default, tells CONOPT to use the maximum number of threads)
    silent::Bool                # should the output be disabled
    lim_variable::Real           # largest absolute value of a variable beyond which it is considered unbounded
    options::Dict{String, Any}  # options stored locally in the Optimizer.
    # These are copied across to the ConoptModel

    # license
    license_int_1::Union{Int, Nothing}
    license_int_2::Union{Int, Nothing}
    license_int_3::Union{Int, Nothing}
    license_string::Union{String, Nothing}

    # NLP data
    nlp_model::Union{Nothing, MOI.Nonlinear.Model} # specialised NLP model structure
    ad_backend::MOI.Nonlinear.AbstractAutomaticDifferentiation # automatic differentiation backend

    # variable mapping MOI to CONOPT
    variable_indices::Vector{MOI.VariableIndex} # list of variable indices
    var_index_to_pos::Array{Int, 1}

    # constraint mapping MOI to CONOPT
    con_index_to_pos::Dict{MOI.ConstraintIndex, Int}
    nlcon_index_to_pos::Dict{MOI.Nonlinear.ConstraintIndex, Int}

    solve_time::Float64         # stores the solve time

    # constructor
    function Optimizer()
        model = new(
            CONOPT.ConoptModel(),
            "Model",                # model name
            nothing,                # time limit
            2,                      # the default log level
            0,                      # default number of threads
            false,                  # silent
            CONOPT_INF_DEFAULT,     # CONOPT's default Lim_Variable parameter
            Dict{String, Any}(),    # options
            nothing,                # license int 1
            nothing,                # license int 2
            nothing,                # license int 3
            nothing,                # license string
            MOI.Nonlinear.Model(),  # NLP model
            MOI.Nonlinear.SparseReverseMode(), # automatic differentiation
            MOI.VariableIndex[],        # list of variable indices
            Int[],
            Dict{MOI.ConstraintIndex, Int}(),
            Dict{MOI.Nonlinear.ConstraintIndex, Int}(),
            NaN,
        )
        return model
    end
end

mutable struct EvaluationCache
    evaluator::Union{Nothing, MOI.Nonlinear.Evaluator}
    row_jac_start::Vector{Int}  # start indices for the row_jac mapping
    row_jac_idx::Vector{Int}    # the indices for the row_jac_mapping
    cached_g::Vector{Float64}   # store for the function values computed by the evaluator
    cached_jac::Vector{Float64} # store for the jacobian values computed by the evaluator

    hessian_map::Vector{Int}        # the permutation mapping for the hessian structure
    cons_map::Vector{Int}           # a mapping from CONOPT to MOI for the constraints
    u_buffer::Vector{Float64}       # a buffer for the multipliers when mapping between CONOPT and MOI
    cached_hess::Vector{Float64}    # store of the hessian values, used as a buffer in the evaluation method

    function EvaluationCache(
        evaluator::MOI.Nonlinear.Evaluator,
        num_constraints::Int,
        num_jac_nnz::Int,
        num_hess_nnz::Int,
    )
        return new(
            evaluator,
            zeros(num_constraints + 1),
            zeros(num_jac_nnz),
            zeros(num_constraints),
            zeros(num_jac_nnz),
            zeros(num_hess_nnz),
            zeros(num_constraints),
            zeros(num_constraints),
            zeros(num_hess_nnz),
        )
    end

    function EvaluationCache()
        return new(nothing, Int[], Float64[], Float64[], Int[], Float64[])
    end
end

function empty_cache!(cache)
    eval_cache = cache::EvaluationCache
    empty!(eval_cache.row_jac_start)
    empty!(eval_cache.row_jac_idx)
    empty!(eval_cache.cached_g)
    empty!(eval_cache.cached_jac)
    empty!(eval_cache.hessian_map)
    empty!(eval_cache.cons_map)
    empty!(eval_cache.u_buffer)
    empty!(eval_cache.cached_hess)

    return cache
end

###
### Some defines used for specifying the supported constraints
###

const _SETS = Union{
    MOI.GreaterThan{Float64},
    MOI.LessThan{Float64},
    MOI.EqualTo{Float64},
}

const _FUNCTIONS = Union{
    MOI.VariableIndex,
    MOI.ScalarAffineFunction{Float64},
    MOI.ScalarQuadraticFunction{Float64},
    MOI.ScalarNonlinearFunction,
}


###
### helper methods for the variable and constraint indices
###

_column(model::Optimizer, vi::MOI.VariableIndex) = model.var_index_to_pos[vi.value]
_row(model::Optimizer, ci::MOI.ConstraintIndex) = model.con_index_to_pos[ci]


function MOI.is_valid(model::Optimizer, vi::MOI.VariableIndex)
    return 1 <= vi.value <= length(model.var_index_to_pos) &&
           model.var_index_to_pos[vi.value] > 0
end

function MOI.is_valid(model::Optimizer, ci::MOI.ConstraintIndex{F, S}) where {F, S}
    # If it's an algebraic constraint, check the row dictionary
    return haskey(model.con_index_to_pos, ci)
end

function MOI.is_valid(
    model::Optimizer, ci::MOI.ConstraintIndex{MOI.VariableIndex, S}
) where {S}
    # A variable bound is valid if the underlying variable is valid.
    return MOI.is_valid(model, MOI.VariableIndex(ci.value))
end


###
### implementations of some basic functions
###

function Base.summary(io::IO, model::Optimizer)
    return print(io, "CONOPT solver with the control vector pointer $(model.inner.cntvect)")
end

function MOI.is_empty(model::Optimizer)
    return CONOPT.is_empty(model.inner)
end

function MOI.empty!(model::Optimizer)
    # destroying the existing CONOPT model, which will call free on the control vector
    model.inner = CONOPT.ConoptModel()

    model.nlp_model = MOI.Nonlinear.Model()
    if !isnothing(model.inner.user_data)
        empty_cache!(model.inner.user_data)
    end

    empty!(model.variable_indices)
    empty!(model.var_index_to_pos)
    empty!(model.con_index_to_pos)
    empty!(model.nlcon_index_to_pos)
    return nothing
end



###
### get, set and supports functions for various Optimizer attributes
###

# solver name
MOI.get(::Optimizer, ::MOI.SolverName) = "CONOPT"

# solver version
function MOI.get(::Optimizer, ::MOI.SolverVersion)::String
    major = Ref{Cint}(0)
    minor = Ref{Cint}(0)
    patch = Ref{Cint}(0)
    CONOPT.LibConopt.COIGET_Version(major, minor, patch)
    return string(major[], ".", minor[], ".", patch[])
end

# raw solver
MOI.get(model::Optimizer, ::MOI.RawSolver) = model.inner.cntvect


# model name
MOI.supports(::Optimizer, ::MOI.Name) = true

MOI.get(model::Optimizer, ::MOI.Name) = model.name

function MOI.set(model::Optimizer, ::MOI.Name, value::String)
    if value == model.name
        return nothing
    end
    model.name = value
    return nothing
end


# silent
MOI.supports(::Optimizer, ::MOI.Silent) = true

function MOI.get(model::Optimizer, ::MOI.Silent)
    return model.silent
end

function MOI.set(model::Optimizer, ::MOI.Silent, value::Bool)
    model.silent = value
    return nothing
end


# time limit
MOI.supports(::Optimizer, ::MOI.TimeLimitSec) = true

function MOI.set(model::Optimizer, ::MOI.TimeLimitSec, value::Real)
    model.time_limit = value
    return nothing
end

function MOI.set(model::Optimizer, ::MOI.TimeLimitSec, ::Nothing)
    # removing the time limit -> set the time limit to CONOPT's default
    model.time_limit = nothing
    return nothing
end

MOI.get(model::Optimizer, ::MOI.TimeLimitSec) = model.time_limit


# number of threads
MOI.supports(::Optimizer, ::MOI.NumberOfThreads) = true

function MOI.set(model::Optimizer, ::MOI.NumberOfThreads, value::Integer)
    if value == model.threads
        return nothing
    end
    model.threads = value
    return nothing
end

function MOI.set(model::Optimizer, ::MOI.NumberOfThreads, ::Nothing)
    if 0 == model.threads
        return nothing
    end
    model.threads = 0
    return nothing
end

MOI.get(model::Optimizer, ::MOI.NumberOfThreads) = model.threads


# gap tolerances not supported by CONOPT
MOI.supports(::Optimizer, ::MOI.AbsoluteGapTolerance) = false
MOI.supports(::Optimizer, ::MOI.RelativeGapTolerance) = false


# starting values of primal variables
function MOI.supports(::Optimizer, ::MOI.VariablePrimalStart, ::Type{MOI.VariableIndex})
    return true
end

function MOI.get(model::Optimizer, ::MOI.VariablePrimalStart, vi::MOI.VariableIndex)
    MOI.throw_if_not_valid(model, vi)
    return model.inner.model_data.variable_primal_start[_column(model, vi)]
end

function MOI.set(
    model::Optimizer,
    ::MOI.VariablePrimalStart,
    vi::MOI.VariableIndex,
    value::Union{Real, Nothing},
)
    MOI.throw_if_not_valid(model, vi)
    model.inner.model_data.variable_primal_start[_column(model, vi)] = value
    return nothing
end


# solver attributes
MOI.supports(::Optimizer, ::MOI.RawOptimizerAttribute) = true

function MOI.set(model::Optimizer, param::MOI.RawOptimizerAttribute, value)
    option_name = param.name

    if lowercase(option_name) == "log_level"
        log_level_value = Int(value)
        if log_level_value < 1 || log_level_value > 4
            @error "Invalid value for log_level <$log_level_value>. It must be between 1 and 4"
        end
        model.inner.log_level = Int(value)
    elseif startswith(lowercase(option_name), "license")
        if endswith(lowercase(option_name), "int_1")
            model.license_int_1 = value
        elseif endswith(lowercase(option_name), "int_2")
            model.license_int_2 = value
        elseif endswith(lowercase(option_name), "int_3")
            model.license_int_3 = value
        elseif endswith(lowercase(option_name), "string")
            model.license_string = value
        end
    elseif lowercase(option_name) == "lim_variable"
        # we handle lim_variable separately so that we have the value available in the Optimizer
        model.lim_variable = value
        model.options[option_name] = value
    else
        model.options[option_name] = value
    end

    return nothing
end

function MOI.get(model::Optimizer, param::MOI.RawOptimizerAttribute)
    if !haskey(model.options, param.name)
        msg = "RawOptimizerAttribute with name $(param.name) is not already set."
        throw(MOI.GetAttributeNotAllowed(param, msg))
    end
    return model.options[param.name]
end


###
### indicate which constraints CONOPT supports
###

function MOI.supports_constraint(::Optimizer, ::Type{<:_FUNCTIONS}, ::Type{<:_SETS})
    return true
end

function MOI.supports_constraint(
    ::Optimizer, ::Type{MOI.VariableIndex}, ::Type{MOI.Interval{Float64}}
)
    return true
end

###
### indicate the types of objectives that CONOPT supports
###

function MOI.supports(
    ::Optimizer,
    ::Union{
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}},
        MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}},
        MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction},
    },
)
    return true
end

function MOI.supports(::Optimizer, ::MOI.ObjectiveSense)
    return true
end

function MOI.set(model::Optimizer, ::MOI.ObjectiveSense, sense::MOI.OptimizationSense)
    _set_objective_sense!(model, sense)
    return nothing
end

###
### _EmptyNLPEvaluator
###
struct _EmptyNLPEvaluator <: MOI.AbstractNLPEvaluator end

MOI.features_available(::_EmptyNLPEvaluator) = [:Grad, :Jac, :Hess]
MOI.initialize(::_EmptyNLPEvaluator, ::Any) = nothing
MOI.eval_constraint(::_EmptyNLPEvaluator, g, x) = nothing
MOI.jacobian_structure(::_EmptyNLPEvaluator) = Tuple{Int64, Int64}[]
MOI.hessian_lagrangian_structure(::_EmptyNLPEvaluator) = Tuple{Int64, Int64}[]
MOI.eval_constraint_jacobian(::_EmptyNLPEvaluator, J, x) = nothing
MOI.eval_hessian_lagrangian(::_EmptyNLPEvaluator, H, x, σ, μ) = nothing


###
### callback functions for the evaluation of functions, Jacobian and Hessian
###


"""
    function _eval_f_ini(model::CONOPT.ConoptModel, x::Vector{Float64}, rowlist::Vector{Cint}, mode::Cint)

    callback function that is executed immediately prior to the function and derivative evaluations.
    This method is used to execute the MOI evaluators for the function and derivatives. The results
    are stored in the EvaluationCache, and then retrieved in the _eval_f and _eval_jac callback functions.
    This caching is needed because MOI evaluates all constraints or the full Jacobian at once; however,
    CONOPT only needs these row-by-row.
"""
function _eval_f_ini(
    model::CONOPT.ConoptModel, x::Vector{Float64}, ::Vector{Cint}, mode::Cint
)::Cint
    eval_cache = model.user_data::EvaluationCache

    try
        # The rowlist can be ignored if we evaluate and cache everything.
        if mode == 1 || mode == 3
            MOI.eval_constraint(eval_cache.evaluator, eval_cache.cached_g, x)
        end
        if mode == 2 || mode == 3
            MOI.eval_constraint_jacobian(eval_cache.evaluator, eval_cache.cached_jac, x)
        end
    catch e
        if e isa DomainError || e isa DivideError || e isa OverflowError
            return 1
        else
            showerror(stderr, e)
            println(stderr, "\nUnexpected error in evaluation.")
        end
    end

    return 0
end


"""
    function _eval_f(model::CONOPT.ConoptModel, rownum::Cint)

    callback function for returning the cached values for a row's function evaluation.
"""
function _eval_f(model::CONOPT.ConoptModel, rownum::Cint)
    eval_cache = model.user_data::EvaluationCache

    return eval_cache.cached_g[rownum + 1]
end


"""
    function _eval_jac(model::CONOPT.ConoptModel, rownum::Cint, jac_idx::Vector{Cint}, jac_vals::Vector{Float64})

    callback function for returning the cached values for a row's derivative evaluation.
"""
function _eval_jac(
    model::CONOPT.ConoptModel,
    rownum::Cint,
    jac_idx::Vector{Cint},
    jac_vals::Vector{Float64},
)
    eval_cache = model.user_data::EvaluationCache

    start = eval_cache.row_jac_start[rownum + 1]
    for i in 1:length(jac_idx)
        @assert start + i - 1 < eval_cache.row_jac_start[rownum + 2]
        jac_vals[jac_idx[i] + 1] = eval_cache.cached_jac[eval_cache.row_jac_idx[start + i - 1]]
    end
    return nothing
end


"""
    function _eval_hess(model::CONOPT.ConoptModel, x::Vector{Float64}, u::Vector{Float64}, rowno::Vector{Cint},
        colno::Vector{Cint}, value::Vector{Float64})

    callback function for returning the Hessian of the Lagrangian. The EvaluationCache is used here
    since it contains preallocated arrays for the Hessian evaluation. Additionally, a mapping between
    MOI and CONOPT for the Hessian is stored in the EvaluationCache.
"""
function _eval_hess(
    model::CONOPT.ConoptModel,
    x::Vector{Float64},
    u::Vector{Float64},
    ::Vector{Cint},
    ::Vector{Cint},
    value::Vector{Float64},
)::Cint
    eval_cache = model.user_data::EvaluationCache
    nnz_hess = length(eval_cache.hessian_map)

    # mapping the multipliers between CONOPT and MOI
    for i in 1:length(u)
        eval_cache.u_buffer[i] = u[eval_cache.cons_map[i]]
    end

    # calling MOI to compute numerical values
    # NOTE: CONOPT includes the objective in the constraint matrix
    try
        MOI.eval_hessian_lagrangian(
            eval_cache.evaluator, eval_cache.cached_hess, x, 0.0, eval_cache.u_buffer
        )
    catch e
        if e isa DomainError || e isa DivideError || e isa OverflowError
            return 1
        else
            showerror(stderr, e)
            println(stderr, "\nUnexpected error in evaluation.")
            return 1 # possibly have a different error code
        end
    end

    # mapping the values from the MOI order to CONOPT order via hessian_map
    fill!(value, 0.0)
    for i in 1:nnz_hess
        hess_idx = eval_cache.hessian_map[i]
        hess_val = eval_cache.cached_hess[i]

        # Store in the pointer provided by the solver
        value[hess_idx] += hess_val
    end

    return 0
end


###
### Setting up the model
###

MOI.supports_incremental_interface(::Optimizer) = false


"""
    function _setup_options(dest::Optimizer)

    copies the parameters from the Optimizer struct to the ConoptModel struct. This is needed
    because only the ConoptModel is passed as the user data to CONOPT. Further, when calling
    optimize!, the options stored in ConoptModel are removed. Having this copy allows options
    to be set prior to the optimize! call.
"""
function _setup_options!(dest::Optimizer)
    for (key, val) in dest.options
        dest.inner.options[key] = val
    end

    # writing specific options to the ConoptModel
    dest.inner.time_limit = dest.time_limit
    dest.inner.log_level = dest.log_level
    dest.inner.threads = dest.threads
    dest.inner.silent = dest.silent

    dest.inner.license.license_int_1 = dest.license_int_1
    dest.inner.license.license_int_2 = dest.license_int_2
    dest.inner.license.license_int_3 = dest.license_int_3
    return dest.inner.license.license_string = dest.license_string
end

"""
    function _update_variable_bounds!(model_data::ModelData, var_index::Int; lower::Float64 = -Inf, upper::Float64 = Inf)

    updates the variable bounds and also updates the primal start to fit between the bounds
"""
function _update_variable_bounds!(
    model_data::CONOPT.ModelData, var_index::Int; lower::Float64=(-Inf), upper::Float64=Inf
)
    if lower > -Inf
        model_data.variable_lower[var_index] = lower
    end

    if upper < Inf
        model_data.variable_upper[var_index] = upper
    end

    return model_data.variable_primal_start[var_index] = clamp(
        model_data.variable_primal_start[var_index],
        model_data.variable_lower[var_index],
        model_data.variable_upper[var_index],
    )
end


"""
    function _setup_variables!(dest::Optimizer, src::MOI.ModelLike)

    extracts the variable information from the JuMP model and stores this in a local data structure.
    This data is passed to CONOPT through the user memory pointer. The variable information is
    processed in the ReadMatrix callback.
"""
function _setup_variables!(dest::Optimizer, src::MOI.ModelLike)
    dest.variable_indices = MOI.get(src, MOI.ListOfVariableIndices())

    n_vars = length(dest.variable_indices)
    dest.inner.model_data.num_variables = n_vars

    # getting the maximum variable index for the mapping array
    max_index =
        isempty(dest.variable_indices) ? 0 : maximum(v.value for v in dest.variable_indices)
    dest.var_index_to_pos = zeros(Int, max_index)

    dest.inner.model_data.variable_primal_start = zeros(Float64, n_vars)
    dest.inner.model_data.variable_lower = fill(-dest.lim_variable, n_vars) #= ah, that's probably where you would need lim_variable, because if the user chooses a different value for CONOPT, this would not be correct =#
    dest.inner.model_data.variable_upper = fill(dest.lim_variable, n_vars)

    for (i, v) in enumerate(dest.variable_indices)
        dest.var_index_to_pos[v.value] = i

        start_val = MOI.get(src, MOI.VariablePrimalStart(), v)
        if start_val !== nothing
            dest.inner.model_data.variable_primal_start[i] = start_val
        else
            dest.inner.model_data.variable_primal_start[i] = 0.0
        end
    end

    return nothing
end



"""
    function _set_objective_sense!(model::Optimizer, sense::MOI.OptimizationSense)

    converts the objective sense from MOI to CONOPT
"""
function _set_objective_sense!(model::Optimizer, sense::MOI.OptimizationSense)
    if sense == MOI.MIN_SENSE
        model.inner.model_data.sense = CONOPT.ObjSense_Minimize
    elseif sense == MOI.MAX_SENSE
        model.inner.model_data.sense = CONOPT.ObjSense_Maximize
    elseif sense == MOI.FEASIBILITY_SENSE
        model.inner.model_data.sense = CONOPT.ObjSense_Feasibility
    else
        error("Unknown objective sense: $sense")
    end
end


"""
    function _setup_constraints!(dest::Optimizer, src::MOI.ModelLike)

    extracts the constraint data from the JuMP model and stores this in a local data structure.
    The data structure is passed as the user memory in CONOPT, and is read in the ReadMatrix method.
"""
function _setup_constraints!(dest::Optimizer, src::MOI.ModelLike)
    dest.inner.model_data.num_constraints = 0
    dest.inner.model_data.constraint_rhs = Float64[]
    dest.inner.model_data.constraint_type = Cint[]

    num_linear_cons = 0
    for (f, set) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        conss_indices = MOI.get(src, MOI.ListOfConstraintIndices{f, set}())
        if isempty(conss_indices)
            continue
        end

        if f == MOI.VariableIndex
            for index in conss_indices
                cons_set = MOI.get(src, MOI.ConstraintSet(), index)
                cons_function = MOI.get(src, MOI.ConstraintFunction(), index)
                pos = dest.var_index_to_pos[cons_function.value]
                if set <: MOI.GreaterThan
                    _update_variable_bounds!(
                        dest.inner.model_data, pos; lower=MOI.constant(cons_set)
                    )
                elseif set <: MOI.LessThan
                    _update_variable_bounds!(
                        dest.inner.model_data, pos; upper=MOI.constant(cons_set)
                    )
                elseif set <: MOI.EqualTo
                    _update_variable_bounds!(
                        dest.inner.model_data,
                        pos;
                        lower=MOI.constant(cons_set),
                        upper=MOI.constant(cons_set),
                    )
                elseif set <: MOI.Interval
                    _update_variable_bounds!(
                        dest.inner.model_data,
                        pos;
                        lower=cons_set.lower,
                        upper=cons_set.upper,
                    )
                end
            end
        else
            for index in conss_indices
                cons_set = MOI.get(src, MOI.ConstraintSet(), index)
                cons_function = MOI.get(src, MOI.ConstraintFunction(), index)

                # This counter handles linear, quadratic, AND nonlinear rows
                dest.inner.model_data.num_constraints += 1
                dest.con_index_to_pos[index] = dest.inner.model_data.num_constraints

                if set <: MOI.GreaterThan
                    push!(dest.inner.model_data.constraint_rhs, MOI.constant(cons_set))
                    push!(dest.inner.model_data.constraint_type, 1)
                elseif set <: MOI.LessThan
                    push!(dest.inner.model_data.constraint_rhs, MOI.constant(cons_set))
                    push!(dest.inner.model_data.constraint_type, 2)
                elseif set <: MOI.EqualTo
                    push!(dest.inner.model_data.constraint_rhs, MOI.constant(cons_set))
                    push!(dest.inner.model_data.constraint_type, 0)
                end

                # Add to the unified evaluator
                cons_index = MOI.Nonlinear.add_constraint(
                    dest.nlp_model, cons_function, cons_set
                )
                dest.nlcon_index_to_pos[cons_index] = dest.inner.model_data.num_constraints
            end
        end
    end

    attr_list = MOI.get(src, MOI.ListOfModelAttributesSet())
    has_objective = any(attr isa MOI.ObjectiveFunction for attr in attr_list)

    if has_objective
        F = MOI.get(src, MOI.ObjectiveFunctionType())

        obj_expr = MOI.get(src, MOI.ObjectiveFunction{F}())

        cons_index = MOI.Nonlinear.add_constraint(
            dest.nlp_model, obj_expr, MOI.Interval(-dest.lim_variable, dest.lim_variable)
        )

        dest.inner.model_data.num_constraints += 1
        dest.nlcon_index_to_pos[cons_index] = dest.inner.model_data.num_constraints
        dest.inner.model_data.objective_row_index = dest.inner.model_data.num_constraints

        #obj_constant = F <: MOI.ScalarNonlinearFunction ? 0.0 : MOI.constant(obj_expr)
        obj_constant = if obj_expr isa MOI.ScalarAffineFunction# || obj_expr isa MOI.ScalarQuadraticFunction
            MOI.constant(obj_expr)
        else
            0.0
        end

        #push!(dest.inner.model_data.constraint_rhs, -obj_constant)
        push!(dest.inner.model_data.constraint_rhs, 0.0)
        push!(dest.inner.model_data.constraint_type, 3) # CONOPT's free row flag
    end

    # setting the objective sense in the CONOPT model data
    return _set_objective_sense!(dest, MOI.get(src, MOI.ObjectiveSense()))
end


"""
    function _setup_evaluator!(dest::Optimizer, src::MOI.ModelLike)

    setup the evaluator for the NLP. This is used to idenfity the nonlinear terms in the Jacobian
    and identify the structure of the Hessian.
"""
function _setup_evaluator!(dest::Optimizer, src::MOI.ModelLike)
    evaluator = MOI.Nonlinear.Evaluator(
        dest.nlp_model, dest.ad_backend, dest.variable_indices
    )
    MOI.initialize(evaluator, [:Jac, :Hess])
    return evaluator
end


"""
    function _setup_matrices!(dest::Optimizer)

    setup up the jacobian and hessian matrices in a form that can be supplied to CONOPT. This process
    additionally involves defining mappings between the jacobian and hessian structures in the evaluator
    to support the function and derivative evaluations.

    Additionally, the constant from linear expressions is extracted and subtracted from the RHS of
    the constraint. This is needed because CONOPT doesn't evaluate purely linear expressions, since
    these are computed internally. As such, if the constant is included in the expression, and not
    on the RHS, then CONOPT will not evaluate the linear expressions correctly.
"""
function _setup_matrices!(dest::Optimizer, evaluator::MOI.Nonlinear.Evaluator)
    num_vars = dest.inner.model_data.num_variables
    num_cons = dest.inner.model_data.num_constraints

    # extracting the jacobian and hessian structure
    raw_jac_str = MOI.jacobian_structure(evaluator)
    raw_hess_str = MOI.hessian_lagrangian_structure(evaluator)

    # storing the sizes of the jacobian and hessian
    total_jac_nnz = length(raw_jac_str)
    total_hess_nnz = length(raw_hess_str)

    # initialising the evaluation cache
    eval_cache = EvaluationCache(evaluator, num_cons, total_jac_nnz, total_hess_nnz)

    # creating the matrix structure from the jacobian
    jac_vals = zeros(total_jac_nnz)
    MOI.eval_constraint_jacobian(
        evaluator, jac_vals, dest.inner.model_data.variable_primal_start
    )

    # sorting the jacobian so that it is in a column-major format
    p_jac_colwise = sortperm(
        1:total_jac_nnz; by=i -> (raw_jac_str[i][2], raw_jac_str[i][1])
    )
    sorted_rows = Cint[raw_jac_str[i][1] - 1 for i in p_jac_colwise]
    sorted_cols = Int[raw_jac_str[i][2] for i in p_jac_colwise]
    sorted_jac_vals = jac_vals[p_jac_colwise]

    # storing the jacobian structure.
    dest.inner.jac_structure.start = zeros(Cint, num_vars + 1)
    for c in sorted_cols
        dest.inner.jac_structure.start[c + 1] += 1
    end

    for i in 1:num_vars
        dest.inner.jac_structure.start[i + 1] += dest.inner.jac_structure.start[i]
    end
    dest.inner.jac_structure.index = sorted_rows

    # --- Nonlinear Mapping via Hessian ---
    nonlinear_vars_in_row = [BitSet() for _ in 1:num_cons]

    # Because ALL equations (including the objective) are now just rows in the evaluator,
    # we can do a single, clean loop from 1 to num_cons.
    for r in 1:num_cons
        # Note: MOI does not have a standard `hessian_constraint_structure` in its public API.
        # Assuming this is a custom JuMP internal function you are using, it now applies cleanly to all rows.
        hess_struct_r = MOI.hessian_constraint_structure(evaluator, r)
        for (c1, c2) in hess_struct_r
            push!(nonlinear_vars_in_row[r], c1)
            push!(nonlinear_vars_in_row[r], c2)
        end
    end

    dest.inner.jac_structure.nlflag = zeros(Cint, total_jac_nnz)
    dest.inner.jac_structure.values = zeros(Float64, total_jac_nnz)

    # getting the nonlinear structure
    for i in 1:total_jac_nnz
        r = sorted_rows[i] + 1
        c = sorted_cols[i]

        # Mark elements as nonlinear (1) or linear (0) for CONOPT
        if c in nonlinear_vars_in_row[r]
            dest.inner.jac_structure.nlflag[i] = Cint(1)
            dest.inner.jac_structure.values[i] = 0.0
        else
            dest.inner.jac_structure.nlflag[i] = Cint(0)
            dest.inner.jac_structure.values[i] = sorted_jac_vals[i]
        end
    end

    # generating a mapping between the MOI jacobian and the row-wise structure of CONOPT
    p_jac_rowwise = sortperm(
        1:total_jac_nnz; by=i -> (raw_jac_str[i][1], raw_jac_str[i][2])
    )
    # computing the row counts for the row_to_jac_index
    for i in 1:total_jac_nnz
        r = raw_jac_str[p_jac_rowwise[i]][1]
        c = raw_jac_str[p_jac_rowwise[i]][2]

        if c in nonlinear_vars_in_row[r]
            eval_cache.row_jac_start[r + 1] += 1
        end
    end

    # performing a prefix sum for the pointer start values
    eval_cache.row_jac_start[1] = 1
    for i in 1:num_cons
        eval_cache.row_jac_start[i + 1] += eval_cache.row_jac_start[i]
    end

    # storage for the current row
    current_row_pos = copy(eval_cache.row_jac_start)

    for i in 1:total_jac_nnz
        r = raw_jac_str[p_jac_rowwise[i]][1]
        c = raw_jac_str[p_jac_rowwise[i]][2]

        if c in nonlinear_vars_in_row[r]
            current_index = current_row_pos[r]

            eval_cache.row_jac_idx[current_index] = i

            current_row_pos[r] += 1
        end
    end

    # extracting the constant from linear expressions
    test_x = zeros(Float64, num_vars)

    MOI.eval_constraint(evaluator, eval_cache.cached_g, test_x)
    for c in 1:num_cons
        if isempty(nonlinear_vars_in_row[c])
            dest.inner.model_data.constraint_rhs[c] -= eval_cache.cached_g[c]
        end
    end


    # --- Lagrangian Hessian Setup ---
    # We query the evaluator directly now

    # cleaning the hessian structure to make it lower triangular
    raw_normalized = [t[1] >= t[2] ? t : (t[2], t[1]) for t in raw_hess_str]

    unique_pairs = unique(raw_normalized)
    sort!(unique_pairs; by=x -> (x[2], x[1]))

    pair_to_idx = Dict(pair => i for (i, pair) in enumerate(unique_pairs))

    hessian_map = [pair_to_idx[p] for p in raw_normalized]

    dest.inner.hess_structure.rows = Cint[p[1] - 1 for p in unique_pairs]
    dest.inner.hess_structure.cols = Cint[p[2] - 1 for p in unique_pairs]

    # storing the permutation mapping and allocating memory for the hessian evaluation
    eval_cache.hessian_map = hessian_map

    # setting up a constraint map between CONOPT indices and MOI
    constraints = dest.nlp_model.constraints
    for (i, k) in enumerate(keys(constraints))
        eval_cache.cons_map[i] = dest.nlcon_index_to_pos[k]
    end

    # setting the eval_cache as the user data
    dest.inner.user_data = eval_cache

    return nothing
end


"""
    function check_supported_attributes(dest::MOI.ModelLike, src::MOI.ModelLike)

    checks whether all attributes of a model are supported by CONOPT. If there is an unsupported
    attribute, then the solve is aborted.
"""
function check_supported_attributes(dest::MOI.ModelLike, src::MOI.ModelLike)
    # Check Model attributes
    for attr in MOI.get(src, MOI.ListOfModelAttributesSet())
        if attr isa MOI.Name
            continue # Ignore variable names
        end
        if !MOI.supports(dest, attr)
            throw(MOI.UnsupportedAttribute(attr))
        end
    end

    # Check Variable attributes
    for attr in MOI.get(src, MOI.ListOfVariableAttributesSet())
        if attr isa MOI.VariableName
            continue # Ignore variable names
        end
        if !MOI.supports(dest, attr, MOI.VariableIndex)
            throw(MOI.UnsupportedAttribute(attr))
        end
    end

    # Check Constraint attributes
    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        for attr in MOI.get(src, MOI.ListOfConstraintAttributesSet{F, S}())
            if attr isa MOI.ConstraintName
                continue # Ignore variable names
            end
            if !MOI.supports(dest, attr, MOI.ConstraintIndex{F, S})
                throw(MOI.UnsupportedAttribute(attr))
            end
        end
    end
end


"""
    function setup_model!(dest::Optimizer, src::MOI.ModelLike)

    copies the model from MOI to CONOPT structures. The ConoptModel is setup by writing model data
    from the MOI model into CONOPT related data structures. This follows the steps:
    - extract the variable information, including bounds and primal starts.
    - extract the constraints. This process also adds the constraints to the MOI.Nonlinear structure
      to be used by the evaluator. Additionally, the objective is extracted as added to CONOPT as
      a constraint.
    - initialising the evaluator with the extracted NLP model.
    - defining the matrices for CONOPT. These are the Jacobian and Hessian matrices. Additionally,
      mappings are generated that map the indices between the jacobian and hessian evaluations and
      the structure stored in CONOPT.
    - copy the options across from the Optimizer to the ConoptModel.

    Finally, the callback methods are registered with the ConoptModel.
"""
function setup_model!(dest::Optimizer, src::MOI.ModelLike)
    # storing the variables, bounds and primal starts
    _setup_variables!(dest, src)

    # storing the constraints and objective.
    # NOTE: the objective is stored as a constraint in CONOPT
    _setup_constraints!(dest, src)

    # initializing the evaluator for the non-linear expressions
    evaluator = _setup_evaluator!(dest, src)

    # constructing the Jacobian and Hessian matrices.
    _setup_matrices!(dest, evaluator)

    # copying the optimisation from the Optimizer to the ConoptModel
    _setup_options!(dest)

    # setting the callbacks
    dest.inner.callbacks.eval_f_ini = _eval_f_ini
    dest.inner.callbacks.eval_f = _eval_f
    dest.inner.callbacks.eval_jac = _eval_jac
    dest.inner.callbacks.eval_hess = _eval_hess

    return nothing
end



"""
    function setup_inner!(model::Optimizer)

    this calls all of the initialisation steps for CONOPT, such as registering the problem sizes,
    options and callback methods.
"""
function setup_inner!(model::Optimizer)
    # TODO check if we need to recreate everything

    return CONOPT.initialize!(model.inner)
end


###
### Optimize
###


"""
    function MOI.optimize!(dest::Optimizer, src::MOI.ModelLike)

    The main optimisation call for CONOPT.
"""
function MOI.optimize!(dest::Optimizer, src::MOI.ModelLike)
    MOI.empty!(dest)
    index_map = MOI.Utilities.identity_index_map(src) # this just maps variable and constraint indices to themselves

    check_supported_attributes(dest, src)

    setup_model!(dest, src)
    setup_inner!(dest)

    start_time = time()

    CONOPT.solve!(dest.inner)

    dest.solve_time = time() - start_time

    return index_map, false
end


###
### Post-optimisation methods
###

#ResultCount

# An iterate available if the model has been setup
function MOI.get(model::Optimizer, ::MOI.ResultCount)
    if CONOPT.is_empty(model.inner)
        return 0
    end

    return model.inner.solution_status.status_stored ? 1 : 0
end


# termination status
function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    # this may not actually be true, since it is possible that there is a crash.
    if !model.inner.solution_status.status_stored
        return MOI.OPTIMIZE_NOT_CALLED
    end

    model_status = model.inner.solution_status.model_status
    solve_status = model.inner.solution_status.solve_status
    if solve_status == CONOPT.SolveStatus_Normal_Completion
        if model_status == CONOPT.ModelStatus_Optimal
            #return MOI.OPTIMAL # we don't return OPTIMAL because CONOPT is considered a local solver
            return MOI.LOCALLY_SOLVED
        elseif model_status == CONOPT.ModelStatus_Locally_Optimal
            return MOI.LOCALLY_SOLVED
        elseif model_status == CONOPT.ModelStatus_Unbounded
            return MOI.DUAL_INFEASIBLE
        elseif model_status == CONOPT.ModelStatus_Infeasible
            #return MOI.INFEASIBLE_OR_UNBOUNDED # we don't return INFEASIBLE_OR_UNBOUNDED because
                                                # CONOPT is a local solver.
            return MOI.LOCALLY_INFEASIBLE
        elseif model_status == CONOPT.ModelStatus_Locally_Infeasible
            return MOI.LOCALLY_INFEASIBLE
            # TODO: there are more model statuses. Need to see if they are needed.
        end
    elseif solve_status == CONOPT.SolveStatus_Iteration_Interrupt
        return MOI.ITERATION_LIMIT
    elseif solve_status == CONOPT.SolveStatus_Timelimit
        return MOI.TIME_LIMIT
    elseif solve_status == CONOPT.SolveStatus_Terminated_Solver
        return MOI.OTHER_LIMIT
    elseif solve_status == CONOPT.SolveStatus_Evaluation_Error_Limit
        return MOI.OTHER_LIMIT
    elseif solve_status == CONOPT.SolveStatus_User_Interrupt
        return MOI.INTERRUPTED
    elseif solve_status == CONOPT.SolveStatus_Error_Setup
        return MOI.OTHER_ERROR
    elseif solve_status == CONOPT.SolveStatus_Solver_Error_NoPoint
        return MOI.OTHER_ERROR
    elseif solve_status == CONOPT.SolveStatus_Solver_Error_Point
        return MOI.OTHER_ERROR
    elseif solve_status == CONOPT.SolveStatus_General_System_Error
        return MOI.OTHER_ERROR
    elseif solve_status == CONOPT.SolveStatus_Terminated_Quick_Mode
        return MOI.OTHER_LIMIT
    end
    return MOI.OPTIMIZE_NOT_CALLED
end

# raw status string explaining why the solver stopped
MOI.get(model::Optimizer, ::MOI.RawStatusString) = model.inner.solution_status.raw_status

# solving time in seconds
MOI.get(model::Optimizer, ::MOI.SolveTimeSec) = model.solve_time

# the primal status - the status of the primal solution
function MOI.get(model::Optimizer, attr::MOI.PrimalStatus)
    if CONOPT.is_empty(model.inner)
        return MOI.NO_SOLUTION
    end

    if !(1 <= attr.result_index <= MOI.get(model, MOI.ResultCount()))
        return MOI.NO_SOLUTION
    end

    model_status = model.inner.solution_status.model_status
    if model_status == CONOPT.ModelStatus_Optimal ||
        model_status == CONOPT.ModelStatus_Locally_Optimal
        return MOI.FEASIBLE_POINT
    elseif model_status == CONOPT.ModelStatus_Infeasible ||
        model_status == CONOPT.ModelStatus_Locally_Infeasible ||
        model_status == CONOPT.ModelStatus_Intermediate_Infeasible
        return MOI.INFEASIBLE_POINT
    end

    return MOI.UNKNOWN_RESULT_STATUS
end


# dual status - the status of the dual solution
# NOTE: this is currently being taken from the model status. However, we could infer this result
# from the dual solution.
function MOI.get(model::Optimizer, attr::MOI.DualStatus)
    if CONOPT.is_empty(model.inner)
        return MOI.NO_SOLUTION
    end

    MOI.check_result_index_bounds(model, attr)

    model_status = model.inner.solution_status.model_status
    if model_status == CONOPT.ModelStatus_Optimal ||
        model_status == CONOPT.ModelStatus_Locally_Optimal
        return MOI.FEASIBLE_POINT
    elseif model_status == CONOPT.ModelStatus_Unbounded
        return MOI.NO_SOLUTION
    end

    return MOI.UNKNOWN_RESULT_STATUS
end


# the number of barrier iterations
# NOTE: CONOPT does not perform the Barrier algorithm, so this is the iterations for the GRG algorithm.
MOI.get(model::Optimizer, ::MOI.BarrierIterations) = model.inner.solution_status.iterations


# the objective value
function MOI.get(model::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(model, attr)

    return model.inner.solution_status.objective
end


# the variable primal solutions
function MOI.get(model::Optimizer, attr::MOI.VariablePrimal, vi::MOI.VariableIndex)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, vi)
    return model.inner.solution_status.x_value[_column(model, vi)]
end


# the constraint primal solutions
function MOI.get(
    model::Optimizer, attr::MOI.ConstraintPrimal, ci::MOI.ConstraintIndex{F, <:_SETS}
) where {
    F <: Union{
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarQuadraticFunction{Float64},
        MOI.ScalarNonlinearFunction,
    },
}
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    return model.inner.solution_status.y_value[_row(model, ci)]
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintPrimal,
    ci::MOI.ConstraintIndex{MOI.VariableIndex, S},
) where {S}
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    col_pos = model.var_index_to_pos[ci.value]
    return model.inner.solution_status.x_value[col_pos]
end


# the constraint dual solutions
function _dual_multiplier(model::Optimizer)
    return model.inner.model_data.sense == CONOPT.ObjSense_Minimize ? 1.0 : -1.0
end

function MOI.get(
    model::Optimizer, attr::MOI.ConstraintDual, ci::MOI.ConstraintIndex{F, <:_SETS}
) where {
    F <: Union{
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarQuadraticFunction{Float64},
        MOI.ScalarNonlinearFunction,
    },
}
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    s = _dual_multiplier(model)
    return s * model.inner.solution_status.y_marginal[_row(model, ci)]
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex, MOI.LessThan{Float64}},
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
    ci::MOI.ConstraintIndex{MOI.VariableIndex, MOI.GreaterThan{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    if model.inner.solution_status.x_basis[ci.value] == 0
        rc = model.inner.solution_status.x_marginal[ci.value]
    else
        rc = 0
    end
    return max(0.0, _dual_multiplier(model) * rc)
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex, MOI.EqualTo{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    rc = model.inner.solution_status.x_marginal[ci.value]
    return _dual_multiplier(model) * rc
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VariableIndex, MOI.Interval{Float64}},
)
    MOI.check_result_index_bounds(model, attr)
    MOI.throw_if_not_valid(model, ci)
    if model.inner.solution_status.x_basis[ci.value] == 0 ||
        model.inner.solution_status.x_basis[ci.value] == 1
        rc = model.inner.solution_status.x_marginal[ci.value]
    else
        rc = 0
    end
    return _dual_multiplier(model) * rc
end


###
### Utilities
###


"""
    function print_model_representation(jac, data)

    a helper method to writing out a model representation. Only the linear components are written out.
    The nonlinear components are written as functions, such as f(x, y, z). This is used for debugging.
"""
function print_model_representation(jac, data)
    n_vars = data.num_variables
    n_cons = data.num_constraints

    # 1. Prepare row-major storage
    # Store linear terms as (col_index, coefficient)
    linear_terms = [Tuple{Int, Float64}[] for _ in 1:n_cons]
    # Store nonlinear variables as a list of col_indices
    nonlinear_vars = [Int[] for _ in 1:n_cons]

    # 2. Transpose column-major Jacobian into row-major lists
    for col in 1:n_vars
        # Assuming jac.start is 0-based (C-style array pointers)
        idx_start = jac.start[col] + 1
        idx_end = jac.start[col + 1]

        for i in idx_start:idx_end
            # Assuming jac.index is 0-based
            row = jac.index[i] + 1
            val = jac.values[i]
            is_nl = (jac.nlflag[i] == 1)

            if is_nl
                push!(nonlinear_vars[row], col)
            else
                push!(linear_terms[row], (col, val))
            end
        end
    end

    # 3. Define the constraint sense mapping
    sense_map = Dict(0 => "==", 1 => ">=", 2 => "<=", 3 => "free")

    # 4. Build and print the representation row by row
    println()
    println("--- Algebraically Extracted Model ---")
    for row in 1:n_cons
        # Mark the objective row
        if row == data.objective_row_index
            prefix = "[OBJECTIVE] c$row:"
        else
            prefix = "c$row:"
        end

        # Sort the terms so x1 appears before x2, etc.
        sort!(linear_terms[row]; by=x -> x[1])
        sort!(nonlinear_vars[row])

        parts = String[]

        # Append linear parts
        for (col, val) in linear_terms[row]
            # Format the coefficient nicely (e.g., skip 1.0 or -1.0 if desired,
            # but keeping it simple here for clarity)
            push!(parts, "$(val)x$col")
        end

        # Append nonlinear part
        if !isempty(nonlinear_vars[row])
            args = join(["x$v" for v in nonlinear_vars[row]], ", ")
            push!(parts, "f$row($args)")
        end

        # Construct the Left-Hand Side string
        if isempty(parts)
            lhs_str = "0.0"
        else
            lhs_str = join(parts, " + ")
            # Clean up "+ -" to just "-" for readability
            lhs_str = replace(lhs_str, "+ -" => "- ")
        end

        # Construct the Right-Hand Side
        rhs_val = data.constraint_rhs[row]
        sense_str = get(sense_map, data.constraint_type[row], "??")

        # Print the final constraint string
        println(rpad(prefix, 20), "$lhs_str $sense_str $rhs_val")
    end
    println("-------------------------------------")
    return println()
end
