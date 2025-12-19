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
    variable_indices::Vector{MOI.VariableIndex} # list of variable indices
    variable_lower::Dict{MOI.VariableIndex, Real} # variable lower bounds
    variable_upper::Dict{MOI.VariableIndex, Real} # variable upper bounds
    var_index_to_pos::Dict{MOI.VariableIndex, Int} # positions of variables in CONOPT arrays
    num_constraints::Int        # number of constraints
    num_ranged::Int             # number of ranged constraints
    jacobian_structure::Vector{Tuple{Int,Int}} # Jacobian sparsity structure as a vector of tuples (row,column)
    jacobian_nonlinear_structure::Vector{Tuple{Int,Int}} # Jacobian sparsity structure as a vector of tuples (row,column), only nonlinear terms
    hessian_structure::Vector{Tuple{Int,Int}} # Hessian Lagrangian sparsity structure as a vector of tuples (row,column)
    sense::MOI.OptimizationSense # objective sense
    variable_primal_start::Vector{Union{Nothing,Float64}} # starting values of primal variables
    
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
            cntvect, # CONOPT control vector
            false,                 # silent
            1e+06,                 # time limit
            "Model",               # model name
            Dict{String,String}(), # parameters
            0,                     # default number of threads
            MOI.VariableIndex[],   # list of variable indices
            Dict{MOI.VariableIndex, Real}(), # variable lower bounds
            Dict{MOI.VariableIndex, Real}(), # variable upper bounds
            Dict{MOI.VariableIndex, Int}(), # positions of variables in CONOPT arrays
            0,                     # number of constraints
            0,                     # number of ranged constraints
            Tuple{Int,Int}[],      # Jacobian sparsity structure
            Tuple{Int,Int}[],      # Jacobian nonlinear sparsity structure
            Tuple{Int,Int}[],      # Hessian sparsity structure
            MOI.FEASIBILITY_SENSE, # objective sense
            Union{Nothing,Float64}[], # primal starting values
            
            1e+15,                 # CONOPT's default Lim_Variable parameter
            
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
    return model.variable_primal_start[vi] #TODO handle index properly
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
    model.variable_primal_start[vi] = value #TODO handle index properly
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

# setup the model
function setup_model(dest::Optimizer, src::MOI.ModelLike)
    # Variables
    dest.variable_indices = MOI.get(src, MOI.ListOfVariableIndices())
    
    # Map index to position in CONOPT arrays (this helps more efficient handling of sparse information)
    for i in 1:length(dest.variable_indices)
        dest.var_index_to_pos[dest.variable_indices[i]] = i-1
    end

    # Constraints of type (f in set); count and add to NLP model
    for f in Base.uniontypes(_FUNCTIONS)
        for set in Base.uniontypes(_SETS)
            nconss = MOI.get(src, MOI.NumberOfConstraints{f, set}())
            
            if set == MOI.Interval{Float64}
                dest.num_ranged += nconss
            end
            dest.num_constraints += nconss
            conss_indices = MOI.get(src, MOI.ListOfConstraintIndices{f,set}())
            
            for index in conss_indices
                cons_set = MOI.get(src, MOI.ConstraintSet(), index)
                cons_function = MOI.get(src, MOI.ConstraintFunction(), index)
                if f == MOI.VariableIndex
                    if set == MOI.GreaterThan{Float64}
                        dest.variable_lower[cons_function] = MOI.constant(cons_set)
                    elseif set == MOI.LessThan{Float64}
                        dest.variable_upper[cons_function] = MOI.constant(cons_set)
                    elseif set == MOI.EqualTo{Float64}
                        dest.variable_lower[cons_function] = MOI.constant(cons_set)
                        dest.variable_upper[cons_function] = MOI.constant(cons_set)
                    else set == MOI.Interval{Float64}
                        dest.variable_lower[cons_function] = cons_set.lower
                        dest.variable_upper[cons_function] = cons_set.upper
                    end
                end
                MOI.Nonlinear.add_constraint(dest.nlp_model, cons_function, cons_set)
            end
        end
    end
    #dest.num_constraints += MOI.get(src, MOI.NumberOfConstraints{MOI.VectorOfVariables, MOI.VectorNonlinearOracle{Float64}}()) # TODO implement support for these
    println("\nNumber of constraints is ", dest.num_constraints)
    
    # Add objective to NLP model (as constraint, since this is what CONOPT expects)
    obj_attr = nothing
    for attr in MOI.get(src, MOI.ListOfModelAttributesSet())
        if attr isa MOI.ObjectiveFunction
            obj_attr = attr
        end
    end
    obj = MOI.get(src, obj_attr)
    #MOI.Nonlinear.set_objective(dest.nlp_model, obj)
    MOI.Nonlinear.add_constraint(dest.nlp_model, obj, MOI.Interval(-Inf, Inf))
    
    println("\nNLP model: ")
    show(dest.nlp_model)
    
    println("\nNLP model constraints count: ")
    show(length(dest.nlp_model.constraints))
    
    # NLP evaluation data
    dest.nlp_data = MOI.NLPBlockData(MOI.Nonlinear.Evaluator(dest.nlp_model, dest.ad_backend, dest.variable_indices),)
    println("\nnlp_data:\n")
    show(dest.nlp_data)
    
    # initialise the evaluator before we can use it
    MOI.initialize(dest.nlp_data.evaluator, [:Grad, :Jac, :JacVec, :Hess, :ExprGraph])
    
    # get Jacobian sparsity structure as a vector of tuples (row, column)
    dest.jacobian_structure = MOI.jacobian_structure(dest.nlp_data.evaluator)
    
    # get nonlinear Jacobian entries: use Hessian for this, if, for a given constraint, a variable has at
    # least one Hessian nonzero corresponding to it, then this constraint is nonlinear in this variable
    for (index, constraint) in dest.nlp_model.constraints
        nnz = Set()
        row = MOI.Nonlinear.ordinal_index(dest.nlp_data.evaluator, index)
        
        # get Hessian structure of this constraint as (col1, col2)
        hessian_structure_i = MOI.hessian_constraint_structure(dest.nlp_data.evaluator, row)
        
        # add each col to nnz
        for (col1, col2) in hessian_structure_i
            push!(nnz, col1)
            push!(nnz, col2)
        end
        
        # add all the nonzeroes in the form (row, col) to the vector of nonlinear jacobian entries
        for col in nnz
            push!(dest.jacobian_nonlinear_structure, (row, col))
        end
    end
    
    # get sparsity structure of the Hessian of the Lagrangian as a vector of tuples (row, column)
    dest.hessian_structure = MOI.hessian_lagrangian_structure(dest.nlp_data.evaluator)
    
    # get objective sense
    dest.sense = MOI.get(src, MOI.ObjectiveSense())
end

# TODO any special handling for the other message types beyond smsg?
function setup_message(model::Optimizer)
    # define the message callback
    function Message(smsg, dmsg, nmsg, msgv, usrmem)::Cint
        msg = unsafe_wrap(Vector{Cstring}, msgv, smsg; own = false)
        for i = 1:smsg
            println("message: ", unsafe_string(pointer(msg[i])))
        end
        return 0
    end

    # pass the callback to CONOPT
    Message_c = @cfunction($Message, Cint, (Cint, Cint, Cint, Ptr{Cstring}, Ptr{Cvoid}))
    LibConopt.COIDEF_Message(model.cntvect[], Message_c)
end

function setup_errmsg(model::Optimizer)
    # define the error message callback
    function ErrMsg(rowno, colno, posno, msg, usrmem)::Cint
        if !model.silent
            if rowno == -1 && colno == -1
                println("CONOPT error/warning about Jacobian element ", posno)
            elseif rowno == -1
                println("CONOPT error/warning about variable ", colno)
            elseif colno == -1
                println("CONOPT error/warning about constraint ", rowno)
            else
                println("CONOPT error/warning about variable ", colno, " appearing in constraint ", rowno)
            end
            print(": ", unsafe_string(pointer(msg)))
        end
        return 0
    end

    # pass the callback to CONOPT
    ErrMsg_c = @cfunction($ErrMsg, Cint, (Cint, Cint, Cint, Ptr{Cstring}, Ptr{Cvoid}))
    LibConopt.COIDEF_ErrMsg(model.cntvect[], ErrMsg_c)
end

# TODO this is just a filler now, need to make this actually work
function setup_status(model::Optimizer)
    # define the status callback
    function Status(modsta, solsta, iter, objval, usrmem)::Cint
        model.rawstatus = "CONOPT stopped"
        model.solvetime = 10
        return 0
    end

    # pass the callback to CONOPT
    Status_c = @cfunction($Status, Cint, (Cint, Cint, Cint, Cdouble, Ptr{Cvoid}))
    LibConopt.COIDEF_Status(model.cntvect[], Status_c)
end

function setup_solution(model::Optimizer)
    # define the solution callback
    function Solution(xval, xmar, xbas, xsta, yval, ymar, ybas, ysta, numvar, numcon, usrmem)::Cint
        # TODO save solution on the julia side
        return 0
    end

    # pass the callback to CONOPT
    Solution_c = @cfunction($Solution, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                              Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                              Cint, Cint, Ptr{Cvoid}))
    LibConopt.COIDEF_Solution(model.cntvect[], Solution_c)
end

function setup_readmatrix(model::Optimizer)
    # define the solution callback
    function ReadMatrix(lower, curr, upper, vsta, constrtype, rhs, esta, colsta, rowno, value, nlflag,
                        numvar, numcon, numnz, usrmem)::Cint
        @assert numvar == length(model.variable_indices)
        @assert numvar == length(model.nlp_data.constraint_bounds)
        
        return 0

        # TODO make sure to properly keep track of variable indices
        # fill in variable data
        i = 0
        for bound in model.nlp_data.constraint_bounds # TODO this is wrong! get variable bound by another way
            if bound.lower != -Inf || bound.lower > -model.lim_variable
                unsafe_store!(lower, bound.lower, i)
            end
            if bound.upper != Inf || bound.upper < model.lim_variable
                unsafe_store!(upper, bound.upper, i)
            end
            i = i+1
        end

        # set starting values, if any are available, otherwise pick a number between the bounds
        for i in 1:length(model.variable_primal_start)
            inner.x[i] = something(
                model.variable_primal_start[i],
                clamp(0.0, model.nlp_data.constraint_bounds.lower[i], model.nlp_data.constraint_bounds.upper[i]),
            )
            # TODO what about unbounded variables?
        end
        
        # fill in constraint data
        i = 0
        for cons_bound in model.nlp_data.constraint_bounds
            show(cons_bound)
            println("")
            println("")
            i = i+1
        end

        return 0
    end

    # pass the callback to CONOPT
    ReadMatrix_c = @cfunction($ReadMatrix, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint},
                                                  Ptr{Cint}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                                  Ptr{Cint}, Ptr{Cdouble}, Ptr{Cint}, Cint,
                                                  Cint, Cint, Ptr{Cvoid}))
    LibConopt.COIDEF_ReadMatrix(model.cntvect[], ReadMatrix_c)
end

function setup_fdeval(model::Optimizer)
    # define the solution callback
    function FDEval(x, g, jac, rowno, jacnum, mode, ignerr, errcnt, numvar, numjac, thread, usrmem)::Cint
        # TODO implement this
        return 0
    end

    # pass the callback to CONOPT
    FDEval_c = @cfunction($FDEval, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Cint,
                                          Ptr{Cint}, Cint, Cint, Ptr{Cint},
                                          Cint, Cint, Cint, Ptr{Cvoid}))
    LibConopt.COIDEF_FDEval(model.cntvect[], FDEval_c)
end

function setup_inner(model::Optimizer)
    # TODO check if we need to recreate everything

    result = 0

    # set problem sizes
    result += LibConopt.COIDEF_NumVar(model.cntvect[], length(model.variable_indices))
    result += LibConopt.COIDEF_NumCon(model.cntvect[], length(model.nlp_model.constraints)) # objective already included here

    # number of Jacobian nonzeroes: each slack var created for a ranged row adds a Jacobian nnz;
    # objective also counts as constraint and is already included in jacobian_structure
    result += LibConopt.COIDEF_NumNz(model.cntvect[], length(model.jacobian_structure) + model.num_ranged)

    # number of nonlinear Jacobian nonzeroes: both of constraints and objective (nlp_model already accounts for it)
    result += LibConopt.COIDEF_NumNlNz(model.cntvect[], length(model.jacobian_nonlinear_structure))

    # number of entries in the Hessian of the Lagrangian
    result += LibConopt.COIDEF_NumHess(model.cntvect[], length(model.hessian_structure))
    
    # objective information
    result += LibConopt.COIDEF_OptDir(model.cntvect[], model.sense == MOI.MAX_SENSE ? 1 : -1)
    # in model.nlp_model, we store objective as the last constraint, hence use ObjCon (not ObjVar) here
    result += LibConopt.COIDEF_ObjCon(model.cntvect[], length(model.nlp_model.constraints)-1)
    
    # tell CONOPT that our function evaluations include the linear terms
    result += LibConopt.COIDEF_FVincLin(model.cntvect[], 1)
    
    # define callbacks and pass them to CONOPT
    setup_message(model)
    setup_errmsg(model)
    setup_status(model)
    setup_solution(model)
    setup_readmatrix(model)
    setup_fdeval(model)

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
    
    result = LibConopt.COI_Solve(dest.cntvect[])
    
    error("stopping for now, result = ", result)
    
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
