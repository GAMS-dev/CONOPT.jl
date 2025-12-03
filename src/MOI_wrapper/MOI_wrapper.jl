###
### Structures and constants
###

mutable struct Optimizer <: MOI.AbstractOptimizer
    cntvect::Ref{Ptr{Cvoid}}    # pointer to the CONOPT control vector
    silent::Bool                # whether CONOPT output should be suppressed: affects the output callbacks of CONOPT
    timelimit::Real             # time limit in seconds
    name::String                # name of the model
    params::Dict{String,String} # solver parameters
    threads::Int                # number of threads (0 is default, tells CONOPT to use the maximum number of threads)
    variables::MOI.Utilities.VariablesContainer{Float64} # problem variables
    variable_indices::Vector{MOI.VariableIndex} # list of variable indices
    num_variables::Int          # number of variables
    num_constraints::Int        # number of constraints
    
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
            cntvect, # CONOPT control vector
            false,                 # silent
            1e+06,                 # time limit
            "Model",               # model name
            Dict{String,String}(), # parameters
            0,                     # default number of threads
            MOI.Utilities.VariablesContainer{Float64}(), # variables
            MOI.VariableIndex[],   # list of variable indices
            0,                     # number of variables
            0,                     # number of constraints
            
            MOI.Nonlinear.Model(), # NLP model
            MOI.NLPBlockData([], _EmptyNLPEvaluator(), false), # empty block data
            MOI.Nonlinear.SparseReverseMode(), # automatic differentiation

            "unknown",             # rawstatus
            0                      # solving time
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
    return isempty(model.params) &&
           MOI.is_empty(model.variables)
end

function MOI.empty!(model::Optimizer)
    # empty the model (TODO: does this also need to free the C problem?)
    empty!(model.params)
    MOI.empty!(model.variables)
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

MOI.get(model::Optimizer, ::MOI.NumberOfThreads) = model.threads

# gap tolerances not supported by CONOPT
MOI.supports(::Optimizer, ::MOI.AbsoluteGapTolerance) = false
MOI.supports(::Optimizer, ::MOI.RelativeGapTolerance) = false

# solve status

function MOI.get(optimizer::Optimizer, ::MOI.TerminationStatus)
    # TODO return actual status
    return MOI.OPTIMIZE_NOT_CALLED
end

# raw status string explaining why the solver stopped
MOI.get(model::Optimizer, ::MOI.RawStatusString) = model.rawstatus

# solving time in seconds
MOI.get(model::Optimizer, ::MOI.SolveTimeSec) = model.solvetime



###
### indicate which constraints CONOPT supports
###

# support constraints of the form x in S, where S = {x | l <= f(x) <= u}
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.VectorNonlinearOracle{Float64}},
)
    return true
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:_FUNCTIONS,},
    ::Type{<:_SETS},
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

# TODO probably remove this
#function MOI.copy_to(model::Optimizer, src::MOI.ModelLike)
#    return MOI.Utilities.default_copy_to(model, src)
#end

# setup the model
function setup_model(dest::Optimizer, src::MOI.ModelLike)
    # Variables
    dest.num_variables = MOI.get(src, MOI.NumberOfVariables())
    dest.variable_indices = MOI.get(src, MOI.ListOfVariableIndices())
    
    # Constraints of type f is set
    num_conss = 0
    for f in Base.uniontypes(_FUNCTIONS)
        for set in Base.uniontypes(_SETS)
            num_conss += MOI.get(src, MOI.NumberOfConstraints{f, set}())
            #conss = constraints(src, f, set)
            #show(conss)
        end
    end
    num_conss += MOI.get(src, MOI.NumberOfConstraints{MOI.VectorOfVariables, MOI.VectorNonlinearOracle{Float64}}())
    println("\nnumber of constraints is ", num_conss)

    # Add constraints to NLP model
    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        conss_indices = MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
        println("\nconss indices: ")
        show(conss_indices)
        for index in conss_indices
           println("\ncons function: ")
           cons_function = MOI.get(src, MOI.ConstraintFunction(), index)
           show(cons_function)
           println("\ncons set: ")
           cons_set = MOI.get(src, MOI.ConstraintSet(), index)
           show(cons_set)
           MOI.Nonlinear.add_constraint(dest.nlp_model, cons_function, cons_set)
        end
    end
    
    #index = MOI.Nonlinear.add_constraint(model.nlp_model, f, s)
    
    # NLP evaluation data
    dest.nlp_data = MOI.NLPBlockData(MOI.Nonlinear.Evaluator(dest.nlp_model, dest.ad_backend, dest.variable_indices),)
    println("\nnlp_data:\n")
    show(dest.nlp_data)
    
    error("For now just terminating here")
    
    jacobian_sparsity = MOI.jacobian_structure(src)
    println("\nJacobian:\n")
    show(jacobian_sparsity)
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
    obj_attr = nothing
    for attr in MOI.get(src, MOI.ListOfModelAttributesSet())
        if attr isa MOI.ObjectiveFunction
            obj_attr = attr
        end
    end
    obj = MOI.get(src, obj_attr)
    println("\nobjective: ")
    show(obj)
    for term in obj.terms
        println("\nvalue = ", term.variable.value, " coef = ", term.coefficient)
    end
    
    setup_model(dest, src)
    
    result = LibConopt.COI_Solve(model.cntvect[])
    
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
