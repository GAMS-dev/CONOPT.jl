###
### Structures and constants
###

include("C_wrapper.jl")

const CONOPT_INF = 1e15

mutable struct ModelData
    num_variables::Int          # the number of variables in the problem
    num_constraints::Int        # number of constraints
    num_ranged::Int             # number of ranged constraints

    variable_indices::Vector{MOI.VariableIndex} # list of variable indices
    variable_lower::Vector{Float64}             # variable lower bounds
    variable_upper::Vector{Float64}             # variable upper bounds
    variable_primal_start::Vector{Float64}      # starting values of primal variables
    var_index_to_pos::Dict{MOI.VariableIndex, Int} # positions of variables in CONOPT arrays and variable_indices (1-indexed)

    constraint_rhs::Vector{Float64}     # the rhs for the constraints
    constraint_type::Vector{Cint}       # the constraint type 0: equality, 1: geq, 2: leq, 3, free

    objective_row_index::Int    # the index for the objective row. TODO: handle the case when the objective is a variable.

    sense::MOI.OptimizationSense # objective sense

    function ModelData()
        return new(
            0,                          # number of variables
            0,                          # number of constraints
            0,                          # number of ranged rows
            MOI.VariableIndex[],        # list of variable indices
            Float64[],                  # variable lower bounds
            Float64[],                  # variable upper bounds
            Float64[],                  # primal starting values
            Dict(),                     # positions of variables
            Float64[],                  # constraint rhs
            Cint[],
            -1,                         # the objective row index
            MOI.FEASIBILITY_SENSE       # objective sense
            )
    end
end

mutable struct JacobianStructure
    start::Vector{Cint}     # the column starts of the Jacobian matrix
    index::Vector{Cint}     # the row indices for the Jacobian matrix
    values::Vector{Float64} # the values for the Jacobian matrix
    nlflag::Vector{Cint}    # the nonlinear flags for the Jacobian matrix

    function JacobianStructure()
        return new(
            Cint[],
            Cint[],
            Float64[],
            Cint[]
            )
    end
end

mutable struct HessianStructure
    cols::Vector{Cint}  # the column indices for the Hessian
    rows::Vector{Cint}  # the row indices for the Hessian

    function HessianStructure()
        return new(
            Cint[],
            Cint[]
            )
    end
end

mutable struct EvaluationCache
    row_to_jac_index::Vector{Vector{Int}}   # mapping from a row to non-linear entries in the jacobian
    cached_jac::Vector{Float64} # store for the jacobian values computed by the evaluator

    function EvaluationCache()
        return new(
            Vector{Int}[],
            Float64[]
        )
    end
end

mutable struct Optimizer <: MOI.AbstractOptimizer
    cntvect::Ref{Ptr{Cvoid}}    # pointer to the CONOPT control vector
    silent::Bool                # whether CONOPT output should be suppressed: affects the output callbacks of CONOPT
    timelimit::Real             # time limit in seconds
    name::String                # name of the model
    params::Dict{String,String} # solver parameters
    threads::Int                # number of threads (0 is default, tells CONOPT to use the maximum number of threads)

    # problem Structures
    model_data::ModelData       # a cache of the model data
    jac_structure::JacobianStructure    # a cache of the jacobian structure
    hess_structure::HessianStructure    # a cache of the hessian structure

    # evaluation cache
    eval_cache::EvaluationCache # a structure to store a cache of the function, derivative and second derivative evaluation.

    # parameters
    lim_variable::Real           # largest absolute value of a variable beyond which it is considered unbounded

    # NLP data
    nlp_model::Union{Nothing,MOI.Nonlinear.Model} # specialised NLP model structure
    nlp_data::MOI.NLPBlockData  # NLP data structure to make use of MOI's evaluation functionality
    ad_backend::MOI.Nonlinear.AbstractAutomaticDifferentiation # automatic differentiation backend

    # solution information
    rawstatus::String           # string explaining why the solver stopped
    solvetime::Float64          # solving time in seconds

    # constructor
    function Optimizer()
        cntvect = Ref{Ptr{Cvoid}}()
        coierror = LibConopt.COI_Create(cntvect)
        if coierror != 0
            error("could not create a CONOPT control vector")
        end
        model = new(
            cntvect,                # CONOPT control vector
            false,                  # silent
            1e+06,                  # time limit
            "Model",                # model name
            Dict{String,String}(),  # parameters
            0,                      # default number of threads
            ModelData(),
            JacobianStructure(),
            HessianStructure(),
            EvaluationCache(),
            1e+15,                  # CONOPT's default Lim_Variable parameter

            MOI.Nonlinear.Model(),  # NLP model
            MOI.NLPBlockData([], _EmptyNLPEvaluator(), false), # empty block data
            MOI.Nonlinear.SparseReverseMode(), # automatic differentiation

            "unknown",              # rawstatus
            0                       # solving time
        )
        finalizer(LibConopt.COI_Free, model.cntvect)
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
    return print(io, "CONOPT solver with the control vector pointer $(model.cntvect)")
end

function MOI.is_empty(model::Optimizer)
    # TODO actually check if the model is empty
    return isempty(model.params)
end

function MOI.empty!(model::Optimizer)
    # empty the model (TODO: does this also need to free the C problem?)
    empty!(model.params)
    coierror = LibConopt.COI_Free(model.cntvect)
    if coierror != 0
        error("could not free a CONOPT control vector")
    end
    coierror = LibConopt.COI_Create(model.cntvect)
    if coierror != 0
        error("could not create a CONOPT control vector")
    end
    return
end



###
### get, set and supports functions for various Optimizer attributes
###

# solver name
function MOI.get(::Optimizer, ::MOI.SolverName)::String
    return "CONOPT"
end

# solver version
function MOI.get(::Optimizer, ::MOI.SolverVersion)::String
    major = Ref{Cint}(0)
    minor = Ref{Cint}(0)
    patch = Ref{Cint}(0)
    LibConopt.COIGET_Version(major, minor, patch)
    return string(major[], ".", minor[], ".", patch[])
end

# raw solver
MOI.get(model::Optimizer, ::MOI.RawSolver) = model.cntvect

# model name
MOI.get(model::Optimizer, ::MOI.Name) = model.name
function MOI.set(model::Optimizer, ::MOI.Name, value::String)
    if value == model.name
        return
    end
    model.name = value
    return
end
MOI.supports(::Optimizer, ::MOI.Name) = true

# silent
MOI.supports(::Optimizer, ::MOI.Silent) = true
function MOI.set(model::Optimizer, ::MOI.Silent, value::Bool)
    if value == model.silent
        return
    end
    model.silent = value
    return
end
MOI.get(model::Optimizer, ::MOI.Silent) = model.silent

# time limit
MOI.supports(::Optimizer, ::MOI.TimeLimitSec) = true

function MOI.set(model::Optimizer, ::MOI.TimeLimitSec, value::Real)
    if value == model.timelimit
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

function MOI.set(model::Optimizer, param::MOI.RawOptimizerAttribute, value)
    return MOI.set(model, param, string(value))
end

function MOI.set(model::Optimizer, param::MOI.RawOptimizerAttribute, value::String)
    model.params[param.name] = value
    # TODO the actual setting of parameters will happen in the Option callback
    return
end

function MOI.get(model::Optimizer, param::MOI.RawOptimizerAttribute)
    # TODO handle non-existing parameters
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

# solve status

function MOI.get(optimizer::Optimizer, ::MOI.TerminationStatus)
    # TODO return actual status
    # Need to write a callback that stores the solution status in the
    # object. Then we will be able to query the solution status here.
    return MOI.OPTIMIZE_NOT_CALLED
end

# raw status string explaining why the solver stopped
MOI.get(model::Optimizer, ::MOI.RawStatusString) = model.rawstatus

# solving time in seconds
MOI.get(model::Optimizer, ::MOI.SolveTimeSec) = model.solvetime



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

### starting values of primal variables

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
    return model.variable_primal_start[model.var_index_to_pos[vi]]
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
    model.variable_primal_start[model.var_index_to_pos[vi]] = value
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

# updates the variable bounds and also updates the primal start to fit between the bounds
function update_variable_bounds(model_data::ModelData, var_index::Int; lower::Float64 = -Inf, upper::Float64 = Inf)
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

function setup_model(dest::Optimizer, src::MOI.ModelLike)
    # ==========================================
    # 1. Variables, Bounds, and Primal Starts
    # ==========================================
    dest.model_data.variable_indices = MOI.get(src, MOI.ListOfVariableIndices())
    n_vars = length(dest.model_data.variable_indices)
    dest.model_data.num_variables = n_vars

    # Pre-allocate variable arrays (assuming these exist in your struct)
    dest.model_data.variable_primal_start = zeros(Float64, n_vars)

    # setting the initial values of the lower and upper bounds
    dest.model_data.variable_lower = fill(-CONOPT_INF, n_vars)
    dest.model_data.variable_upper = fill(CONOPT_INF, n_vars)

    # Map index to position and extract initial guesses
    for (i, vi) in enumerate(dest.model_data.variable_indices)
        dest.model_data.var_index_to_pos[vi] = i

        # Extract the starting guess (x_0) if the user provided one
        start_val = MOI.get(src, MOI.VariablePrimalStart(), vi)
        if start_val !== nothing
            dest.model_data.variable_primal_start[i] = start_val
        else
            # Default to 0.0. (Note: some NLP solvers prefer a small non-zero
            # like 1e-5 to avoid dividing by zero in initial gradients).
            dest.model_data.variable_primal_start[i] = 0.0
        end
    end

    # ==========================================
    # 2. Constraints and Objective
    # ==========================================
    ranged_indices = Vector{Int}()
    dest.model_data.num_constraints = 0
    dest.model_data.num_ranged = 0

    # Initialize empty arrays for constraint bounds
    dest.model_data.constraint_rhs = Float64[]
    dest.model_data.constraint_type = Cint[]

    for f in Base.uniontypes(_FUNCTIONS)
        for set in Base.uniontypes(_SETS)
            nconss = MOI.get(src, MOI.NumberOfConstraints{f, set}())
            if nconss == 0; continue; end

            conss_indices = MOI.get(src, MOI.ListOfConstraintIndices{f,set}())

            for index in conss_indices
                cons_set = MOI.get(src, MOI.ConstraintSet(), index)
                cons_function = MOI.get(src, MOI.ConstraintFunction(), index)

                if f == MOI.VariableIndex
                    v_idx = dest.model_data.var_index_to_pos[cons_function]

                    if set <: MOI.GreaterThan
                        update_variable_bounds(dest.model_data, v_idx, lower=MOI.constant(cons_set))
                    elseif set <: MOI.LessThan
                        update_variable_bounds(dest.model_data, v_idx, upper=MOI.constant(cons_set))
                    elseif set <: MOI.EqualTo
                        update_variable_bounds(
                            dest.model_data,
                            v_idx,
                            lower=MOI.constant(cons_set),
                            upper=MOI.constant(cons_set)
                            )
                    elseif set <: MOI.Interval
                        update_variable_bounds(
                            dest.model_data,
                            v_idx,
                            lower=cons_set.lower,
                            upper=cons_set.upper
                            )
                    end
                else
                    # This is a real structural constraint (row in the Jacobian)
                    dest.model_data.num_constraints += 1

                    # Extract the row bounds (g_L <= g(x) <= g_U)
                    if set <: MOI.GreaterThan
                        push!(dest.model_data.constraint_rhs, MOI.constant(cons_set))
                        push!(dest.model_data.constraint_type, 1)
                    elseif set <: MOI.LessThan
                        push!(dest.model_data.constraint_rhs, MOI.constant(cons_set))
                        push!(dest.model_data.constraint_type, 2)
                    elseif set <: MOI.EqualTo
                        push!(dest.model_data.constraint_rhs, MOI.constant(cons_set))
                        push!(dest.model_data.constraint_type, 0)
                    elseif set <: MOI.Interval
                        dest.model_data.num_ranged += 1
                        push!(ranged_indices, dest.model_data.num_constraints)
                        push!(dest.model_data.constraint_rhs, 0.0)
                        push!(dest.model_data.constraint_type, 0)

                        # adding the variable information for the range slack variables
                        push!(dest.model_data.variable_lower, cons_set.lower)
                        push!(dest.model_data.variable_upper, cons_set.upper)
                        push!(dest.model_data.variable_primal_start,
                              clamp(0.0, cons_set.lower, cons_set.upper))
                    end

                    MOI.Nonlinear.add_constraint(dest.nlp_model, cons_function, cons_set)
                end
            end
        end
    end

    # Handle Objective as a constraint
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

        dest.model_data.num_constraints += 1
        dest.model_data.objective_row_index = dest.model_data.num_constraints

        # The objective row mathematically has no bounds
        push!(dest.model_data.constraint_rhs, 0.0)
        push!(dest.model_data.constraint_type, 3)
    end

    dest.model_data.sense = MOI.get(src, MOI.ObjectiveSense())

    # ==========================================
    # 3. Evaluator Initialization
    # ==========================================
    dest.nlp_data = MOI.NLPBlockData(
        MOI.Nonlinear.Evaluator(dest.nlp_model, dest.ad_backend, dest.model_data.variable_indices)
    )

    MOI.initialize(dest.nlp_data.evaluator, [:Jac, :Hess])

    # ==========================================
    # 4. Matrix and Hessian Construction
    # ==========================================
    raw_jac_str = MOI.jacobian_structure(dest.nlp_data.evaluator)
    total_jac_nnz = length(raw_jac_str)

    # 1. Evaluate Jacobian once at the primal start to extract the linear constants
    jac_vals = zeros(total_jac_nnz)
    MOI.eval_constraint_jacobian(dest.nlp_data.evaluator, jac_vals, dest.model_data.variable_primal_start)

    # 2. Sort Jacobian into Column-Major (CSC expectation)
    p_jac = sortperm(1:total_jac_nnz, by = i -> (raw_jac_str[i][2], raw_jac_str[i][1]))

    sorted_rows = Cint[raw_jac_str[i][1] - 1 for i in p_jac] # 0-based for C
    sorted_cols = Int[raw_jac_str[i][2] for i in p_jac]      # 1-based for Julia counting
    sorted_jac_vals = jac_vals[p_jac]

    # 3. Build CSC Column Pointers (0-based)
    dest.jac_structure.start = zeros(Cint, n_vars + 1)
    for c in sorted_cols
        dest.jac_structure.start[c + 1] += 1
    end
    for i in 1:n_vars
        dest.jac_structure.start[i + 1] += dest.jac_structure.start[i]
    end
    dest.jac_structure.index = sorted_rows

    # 4. Identify Nonlinear Variables PER ROW using Constraint Hessians
    # Because you added the objective as a constraint, num_constraints exactly matches
    # the evaluator's row count. This makes the loop incredibly clean.
    nonlinear_vars_in_row = [BitSet() for _ in 1:dest.model_data.num_constraints]

    for r in 1:dest.model_data.num_constraints
        # Ask MOI for the (col1, col2) pairs where the 2nd derivative is non-zero
        hess_struct_r = MOI.hessian_constraint_structure(dest.nlp_data.evaluator, r)

        for (c1, c2) in hess_struct_r
            push!(nonlinear_vars_in_row[r], c1)
            push!(nonlinear_vars_in_row[r], c2)
        end
    end

    # 5. Apply the precise Row/Col mapping to the Jacobian elements
    dest.jac_structure.nlflag = zeros(Cint, total_jac_nnz)
    dest.jac_structure.values = zeros(Float64, total_jac_nnz)
    dest.eval_cache.row_to_jac_index = [Int[] for _ in 1:dest.model_data.num_constraints]

    for i in 1:total_jac_nnz
        r = sorted_rows[i] + 1 # Convert back to 1-based to index into our Julia arrays
        c = sorted_cols[i]     # 1-based column

        # Check if column 'c' has a non-zero second derivative in this specific row 'r'
        if c in nonlinear_vars_in_row[r]
            dest.jac_structure.nlflag[i] = Cint(1)
            dest.jac_structure.values[i] = 0.0

            # Map this row so our C-callback knows exactly where to update
            push!(dest.eval_cache.row_to_jac_index[r], i)
        else
            dest.jac_structure.nlflag[i] = Cint(0)
            dest.jac_structure.values[i] = sorted_jac_vals[i] # Store the linear coefficient
        end
    end

    # 6. Add Slack Variables to the Jacobian
    slack_idx = dest.model_data.num_variables + 1
    for i in 1:dest.model_data.num_ranged
        push!(dest.jac_structure.start, dest.jac_structure.start[slack_idx - 1] + 1)
        push!(dest.jac_structure.index, Cint(ranged_indices[i] - 1))
        push!(dest.jac_structure.values, 1.0)
        push!(dest.jac_structure.nlflag, Cint(0))
        slack_idx += 1
    end

    # 7. Complete the overall Lagrangian Hessian CSC Formatting (for the actual Solve)
    raw_hess_str = MOI.hessian_lagrangian_structure(dest.nlp_data.evaluator)
    p_hess = sortperm(1:length(raw_hess_str), by = i -> (raw_hess_str[i][2], raw_hess_str[i][1]))

    dest.hess_structure.rows = Cint[raw_hess_str[i][1] - 1 for i in p_hess] # 0-based
    dest.hess_structure.cols = Cint[raw_hess_str[i][2] - 1 for i in p_hess] # 0-based
end

# TODO any special handling for the other message types beyond smsg?
function setup_message(model::Optimizer)
    # pass the callback to CONOPT
    Message_c = @cfunction(_Message_cb, Cint, (Cint, Cint, Cint, Ptr{Cstring}, Ptr{Cvoid}))
    LibConopt.COIDEF_Message(model.cntvect[], Message_c)
end

using Infiltrator

function setup_errmsg(model::Optimizer)
    # pass the callback to CONOPT
    ErrMsg_c = @cfunction(_ErrMsg_cb, Cint, (Cint, Cint, Cint, Ptr{Cchar}, Ptr{Cvoid}))
    LibConopt.COIDEF_ErrMsg(model.cntvect[], ErrMsg_c)
end

# TODO this is just a filler now, need to make this actually work
function setup_status(model::Optimizer)
    # pass the callback to CONOPT
    Status_c = @cfunction(_Status_cb, Cint, (Cint, Cint, Cint, Cdouble, Ptr{Cvoid}))
    LibConopt.COIDEF_Status(model.cntvect[], Status_c)
end

function setup_solution(model::Optimizer)
    # pass the callback to CONOPT
    Solution_c = @cfunction(_Solution_cb, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                              Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                              Cint, Cint, Ptr{Cvoid}))
    LibConopt.COIDEF_Solution(model.cntvect[], Solution_c)
end

function setup_readmatrix(model::Optimizer)
    # pass the callback to CONOPT
    ReadMatrix_c = @cfunction(_ReadMatrix_cb, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint},
                                                  Ptr{Cint}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                                  Ptr{Cint}, Ptr{Cdouble}, Ptr{Cint}, Cint,
                                                  Cint, Cint, Ptr{Cvoid}))
    LibConopt.COIDEF_ReadMatrix(model.cntvect[], ReadMatrix_c)
end

function setup_fdeval(model::Optimizer)
    # pass the callback to CONOPT
    FDEval_c = @cfunction(_FDEval_cb, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Cint,
                                          Ptr{Cint}, Cint, Cint, Ptr{Cint},
                                          Cint, Cint, Cint, Ptr{Cvoid}))
    LibConopt.COIDEF_FDEval(model.cntvect[], FDEval_c)
end

function setup_inner(model::Optimizer)
    # TODO check if we need to recreate everything

    result = 0

    # set problem sizes
    result += LibConopt.COIDEF_NumVar(model.cntvect[], model.model_data.num_variables + model.model_data.num_ranged) # add a slack variable for each ranged constraint
    result += LibConopt.COIDEF_NumCon(model.cntvect[], model.model_data.num_constraints) # objective already included here

    # number of Jacobian nonzeroes: each slack var created for a ranged row adds a Jacobian nnz;
    # objective also counts as constraint and is already included in jacobian_structure
    result += LibConopt.COIDEF_NumNz(model.cntvect[], length(model.jac_structure.index))

    # number of nonlinear Jacobian nonzeroes: both of constraints and objective (nlp_model already accounts for it)
    result += LibConopt.COIDEF_NumNlNz(model.cntvect[], sum(model.jac_structure.nlflag))

    # number of entries in the Hessian of the Lagrangian
    result += LibConopt.COIDEF_NumHess(model.cntvect[], length(model.hess_structure.cols))

    # objective information
    result += LibConopt.COIDEF_OptDir(model.cntvect[], model.model_data.sense == MOI.MAX_SENSE ? 1 : -1)
    # in model.nlp_model, we store objective as the last constraint, hence use ObjCon (not ObjVar) here
    result += LibConopt.COIDEF_ObjCon(model.cntvect[], model.model_data.objective_row_index - 1)

    # tell CONOPT that our function evaluations include the linear terms
    result += LibConopt.COIDEF_FVincLin(model.cntvect[], 1)

    # define callbacks and pass them to CONOPT
    setup_message(model)
    setup_errmsg(model)
    setup_status(model)
    setup_solution(model)
    setup_readmatrix(model)
    setup_fdeval(model)

    LibConopt.COIDEF_UsrMem(model.cntvect[], pointer_from_objref(model))

    if result != 0
        error("error when initialising CONOPT")
    end
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

    result = LibConopt.COI_Solve(dest.cntvect[])

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
