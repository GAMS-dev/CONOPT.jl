
#!format:off
@enum ObjectiveSense begin
    ObjSense_Minimize       = -1
    ObjSense_Feasibility    = 0
    ObjSense_Maximize       = 1
end

@enum VerbosityLevel begin
    VerbLevel_None                        = 1
    VerbLevel_Normal                      = 2
    VerbLevel_Error                       = 3
    VerbLevel_Debug                       = 4
end

@enum ModelStatus begin
    ModelStatus_Optimal                     = 1
    ModelStatus_Locally_Optimal             = 2
    ModelStatus_Unbounded                   = 3
    ModelStatus_Infeasible                  = 4
    ModelStatus_Locally_Infeasible          = 5
    ModelStatus_Intermediate_Infeasible     = 6
    ModelStatus_Intermediate_Nonoptimal     = 7
    ModelStatus_Error_Unknown               = 12
    ModelStatus_Error_NoSolution            = 13
    ModelStatus_Solved_Unique               = 15
    ModelStatus_Solved                      = 16
    ModelStatus_Solved_Singular             = 17
    ModelStatus_Unknown                     = 18
end

@enum SolveStatus begin
    SolveStatus_Normal_Completion           = 1
    SolveStatus_Iteration_Interrupt         = 2
    SolveStatus_Timelimit                   = 3
    SolveStatus_Terminated_Solver           = 4
    SolveStatus_Evaluation_Error_Limit      = 5
    SolveStatus_User_Interrupt              = 8
    SolveStatus_Error_Setup                 = 9
    SolveStatus_Solver_Error_NoPoint        = 10
    SolveStatus_Solver_Error_Point          = 11
    SolveStatus_General_System_Error        = 13
    SolveStatus_Terminated_Quick_Mode       = 15
    SolveStatus_Unknown                     = 18
end
#!format:on

mutable struct ModelData
    num_variables::Int          # the number of variables in the problem
    num_constraints::Int        # number of constraints

    variable_lower::Vector{Float64}             # variable lower bounds
    variable_upper::Vector{Float64}             # variable upper bounds
    variable_primal_start::Vector{Float64}      # starting values of primal variables

    constraint_rhs::Vector{Float64}     # the rhs for the constraints
    constraint_type::Vector{Cint}       # the constraint type 0: equality, 1: geq, 2: leq, 3, free

    objective_row_index::Int    # the index for the objective row. TODO: handle the case when the objective is a variable.
    sense::ObjectiveSense       # the objective sense, 1 is minimize and -

    keep::Bool                  # should the data be kept after being read by Conopt

    function ModelData()
        return new(
            0,                          # number of variables
            0,                          # number of constraints
            Float64[],                  # variable lower bounds
            Float64[],                  # variable upper bounds
            Float64[],                  # primal starting values
            Float64[],                  # constraint rhs
            Cint[],
            -1,                         # the objective row index
            ObjSense_Feasibility,       # the objective sense
            false
            )
    end
end

mutable struct JacobianStructure
    start::Vector{Cint}     # the column starts of the Jacobian matrix
    index::Vector{Cint}     # the row indices for the Jacobian matrix
    values::Vector{Float64} # the values for the Jacobian matrix
    nlflag::Vector{Cint}    # the nonlinear flags for the Jacobian matrix

    keep::Bool              # should the data be kept after being read by Conopt

    function JacobianStructure()
        return new(
            Cint[],
            Cint[],
            Float64[],
            Cint[],
            false
            )
    end
end

mutable struct HessianStructure
    cols::Vector{Cint}  # the column indices for the Hessian
    rows::Vector{Cint}  # the row indices for the Hessian

    keep::Bool          # should the data be kept after being read by Conopt

    function HessianStructure()
        return new(
            Cint[],
            Cint[],
            false
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

mutable struct SolutionStatus
    x_value::Vector{Float64}        # the final solution value for the variables
    x_marginal::Vector{Float64}     # the marginal or reduced costs for the variables
    x_basis::Vector{Int}            # the basis indicators for the variables
    x_status::Vector{Int}           # the status of the variables

    y_value::Vector{Float64}        # the final value of the left hand side of all constraints,
                                    # including linear and nonlinear terms
    y_marginal::Vector{Float64}     # the marginal or reduced costs for the constraints
    y_basis::Vector{Int}            # the basis indicators for the constraints
    y_status::Vector{Int}           # the status of the constraints

    raw_status::String               # string explaining why the solver stopped
    model_status::ModelStatus       # the model status reported by Conopt
    solve_status::SolveStatus       # the solution status reported by Conopt
    iterations::Int                 # the number of iterations performed
    objective::Float64              # the final objective value

    solution_stored::Bool           # set to True is the solution data has been stored
    status_stored::Bool             # set to True is the status data has been stored
    function SolutionStatus()
        return new(
            Float64[],
            Float64[],
            Int[],
            Int[],
            Float64[],
            Float64[],
            Int[],
            Int[],
            "unknown",
            ModelStatus_Unknown,
            SolveStatus_Unknown,
            0,
            NaN,
            false,
            false
            )
    end
end

mutable struct ConoptCallbacks
    # mandatory callbacks
    eval_f::Function
    eval_jac::Function

    # optional callbacks
    eval_hess::Union{Function,Nothing}
    eval_f_ini::Union{Function,Nothing}
    eval_f_end::Union{Function,Nothing}
    message::Union{Function,Nothing}
    errmsg::Union{Function,Nothing}
    solution::Union{Function,Nothing}
    status::Union{Function,Nothing}

    function ConoptCallbacks()
        return new(
            # mandatory callbacks
            (args...) -> error("a function evaluation method is required."),
            (args...) -> error("a jacobian evaluation method is required."),

            # optional callbacks
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
            nothing,
        )
    end
end

mutable struct ConoptModel
    cntvect::Ref{Ptr{Cvoid}}    # pointer to the CONOPT control vector
    silent::Bool                # whether CONOPT output should be suppressed: affects the output callbacks of CONOPT
    log_level::Int               # the log level for the Conopt output. This matches the C++ verbosity levels

    # problem Structures
    model_data::ModelData       # a cache of the model data
    jac_structure::JacobianStructure    # a cache of the jacobian structure
    hess_structure::HessianStructure    # a cache of the hessian structure

    # evaluation cache
    eval_cache::EvaluationCache # a structure to store a cache of the function, derivative and second derivative evaluation.

    callbacks::ConoptCallbacks  # the callback functions

    solution_status::SolutionStatus     # the structure to store the final solution and status

    function ConoptModel()
        cntvect = Ref{Ptr{Cvoid}}()
        coierror = LibConopt.COI_Create(cntvect)
        if coierror != 0
            error("could not create a Conopt contol vector.")
        end

        model = new(
            cntvect,
            false,
            2,
            ModelData(),
            JacobianStructure(),
            HessianStructure(),
            EvaluationCache(),
            ConoptCallbacks(),
            SolutionStatus()
        )

        finalizer(_free_control_vector!, model)

        return model
    end
end

function _free_control_vector!(model::ConoptModel)
    if model.cntvect[] != C_NULL
        LibConopt.COI_Free(model.cntvect)
        model.cntvect = C_NULL
    end
end

function is_empty(model::ConoptModel)
    return model.model_data.num_variables == 0 &&
        model.model_data.num_constraints == 0
end

function initialize!(model::ConoptModel)
    if model.cntvect[] == C_NULL
        error("the Conopt control vector has not bee initialized")
    end

    ptr = model.cntvect[]

    coierror = 0

    # set problem sizes
    coierror += LibConopt.COIDEF_NumVar(ptr, model.model_data.num_variables)
    coierror += LibConopt.COIDEF_NumCon(ptr, model.model_data.num_constraints) # objective already included here

    # objective also counts as constraint and is already included in jacobian_structure
    coierror += LibConopt.COIDEF_NumNz(ptr, length(model.jac_structure.index))

    # number of nonlinear Jacobian nonzeroes: both of constraints and objective (nlp_model already accounts for it)
    coierror += LibConopt.COIDEF_NumNlNz(ptr, sum(model.jac_structure.nlflag))

    # number of entries in the Hessian of the Lagrangian
    coierror += LibConopt.COIDEF_NumHess(ptr, length(model.hess_structure.cols))

    # objective information
    if model.model_data.sense == ObjSense_Maximize || model.model_data.sense == ObjSense_Minimize
        coierror += LibConopt.COIDEF_OptDir(ptr, Int(model.model_data.sense))

        # in model.nlp_model, we store objective as the last constraint, hence use ObjCon (not ObjVar) here
        coierror += LibConopt.COIDEF_ObjCon(ptr, model.model_data.objective_row_index - 1)
    end

    # tell CONOPT that our function evaluations include the linear terms
    coierror += LibConopt.COIDEF_FVincLin(ptr, 1)

    coierror += register_callbacks(model)

    coierror += LibConopt.COIDEF_UsrMem(ptr, pointer_from_objref(model))

    if coierror != 0
        error("error when initialising CONOPT")
    end
end


function solve!(model::ConoptModel)
    return LibConopt.COI_Solve(model.cntvect[])
end

"""
    function _Message_cb(smsg, dmsg, nmsg, msgv, usrmem)

    the callback function for message handling. The buffer could contain error and debug messages.
    The main message stream is given by the first smsg messages. [smsg, dmsg] messages are the error
    messages. Then [dmsg, nmsg] messages are the debug messages.
"""
function _Message_cb(smsg, dmsg, nmsg, msgv, usrmem)::Cint
    model = unsafe_pointer_to_objref(usrmem)::ConoptModel
    if !model.silent && model.log_level > 1
        # normal log level outputs smsg
        message_length = smsg

        # error or higher log level outputs dmsg
        if model.log_level >= 3
            message_length = max(message_length, dmsg)
        end

        # the debug or higher log level outputs nmsg
        if model.log_level >= 4
            message_length = max(message_length, nmsg)
        end

        msg = unsafe_wrap(Vector{Cstring}, msgv, message_length; own = false)
        for i = 1:message_length
            println(unsafe_string(pointer(msg[i])))
        end
    end

    return Cint(0)
end


"""
    function _ErrMsg_cb(rowno, colno, posno, msgptr, usrmem)

    callback for handling the error messages from Conopt. These messages report the row, column and
    position numbers for the error along with a message.
"""
function _ErrMsg_cb(rowno, colno, posno, msgptr, usrmem)::Cint
    model = unsafe_pointer_to_objref(usrmem)::ConoptModel
    if !model.silent
        error_message = "CONOPT Error: "
        if rowno == -1 && colno == -1
            error_message *= "Jacobian element " * string(posno)
        elseif rowno == -1
            error_message *= "Variable " * string(colno)
        elseif colno == -1
            error_message *= "Constraint " * string(rowno)
        else
            error_message *= "Variable " * string(colno) * " appearing in Constraint " * string(rowno)
        end
        if msgptr != C_NULL
            actual_message = unsafe_string(msgptr)
            error_message *= " -- " * actual_message
        end

        @error error_message
    end

    return Cint(0)
end

# define the status callback
function _Status_cb(modsta, solsta, iter, objval, usrmem)::Cint
   model = unsafe_pointer_to_objref(usrmem)::ConoptModel

   model.solution_status.model_status = ModelStatus(modsta)
   model.solution_status.solve_status = SolveStatus(solsta)

   model.solution_status.iterations = iter
   model.solution_status.objective = objval

   model.solution_status.raw_status = "CONOPT stopped"

   model.solution_status.status_stored = true;

   return Cint(0)
end

# define the solution callback
function _Solution_cb(xval, xmar, xbas, xsta, yval, ymar, ybas, ysta, numvar, numcon, usrmem)::Cint
   model = unsafe_pointer_to_objref(usrmem)::ConoptModel
   solution = model.solution_status

   # copying the data across to the solution structure
   xval_view = unsafe_wrap(Array, xval, numvar; own=false)
   solution.x_value = copy(xval_view)

   xmar_view = unsafe_wrap(Array, xmar, numvar; own=false)
   solution.x_marginal = copy(xmar_view)

   xbas_view = unsafe_wrap(Array, xbas, numvar; own=false)
   solution.x_basis = copy(xbas_view)

   xsta_view = unsafe_wrap(Array, xsta, numvar; own=false)
   solution.x_status = copy(xsta_view)

   yval_view = unsafe_wrap(Array, yval, numcon; own=false)
   solution.y_value = copy(yval_view)

   ymar_view = unsafe_wrap(Array, ymar, numcon; own=false)
   solution.y_marginal = copy(ymar_view)

   ybas_view = unsafe_wrap(Array, ybas, numcon; own=false)
   solution.y_basis = copy(ybas_view)

   ysta_view = unsafe_wrap(Array, ysta, numcon; own=false)
   solution.y_status = copy(ysta_view)

   model.solution_status.solution_stored = true

   return Cint(0)
end


# define the read matrix callback
function _ReadMatrix_cb(lower, curr, upper, vsta, constrtype, rhs, esta, colsta, rowno, value, nlflag,
        numvar, numcon, numnz, usrmem)::Cint
    model = unsafe_pointer_to_objref(usrmem)::ConoptModel

    @assert numvar == model.model_data.num_variables
    norigvars = model.model_data.num_variables

    # fill in variable data
    unsafe_copyto!(lower, pointer(model.model_data.variable_lower), numvar)
    unsafe_copyto!(upper, pointer(model.model_data.variable_upper), numvar)
    unsafe_copyto!(curr, pointer(model.model_data.variable_primal_start), numvar)

    # fill in constraint data. NOTE: this includes the objective constraint
    @assert length(model.model_data.constraint_rhs) == numcon
    @assert length(model.model_data.constraint_type) == numcon
    unsafe_copyto!(constrtype, pointer(model.model_data.constraint_type), numcon)
    unsafe_copyto!(rhs, pointer(model.model_data.constraint_rhs), numcon)

    # filling the jacobian data
    @assert length(model.jac_structure.start) == numvar + 1
    @assert length(model.jac_structure.index) == numnz
    @assert length(model.jac_structure.values) == numnz
    @assert length(model.jac_structure.nlflag) == numnz
    unsafe_copyto!(colsta, pointer(model.jac_structure.start), numvar + 1)
    unsafe_copyto!(rowno, pointer(model.jac_structure.index), numnz)
    unsafe_copyto!(value, pointer(model.jac_structure.values), numnz)
    unsafe_copyto!(nlflag, pointer(model.jac_structure.nlflag), numnz)

    # emptying the matrix data stored by Julia that is no longer needed
    if !model.jac_structure.keep
        empty!(model.jac_structure.start)
        empty!(model.jac_structure.index)
        empty!(model.jac_structure.values)
        empty!(model.jac_structure.nlflag)
    end

    # We also no longer need the bounds and rhs arrays
    if !model.model_data.keep
        empty!(model.model_data.variable_lower)
        empty!(model.model_data.variable_upper)
        empty!(model.model_data.variable_primal_start)
        empty!(model.model_data.constraint_rhs)
        empty!(model.model_data.constraint_type)
    end

    return Cint(0)
end

# define the function and derivative evaluation callback
function _FDEval_cb(x, g, jac, rowno, jacnum, mode, ignerr, errcnt, numvar, numjac, thread, usrmem)::Cint
    #model = unsafe_pointer_to_objref(usrmem)::ConoptModel

    #x_values = unsafe_wrap(Array{Float64}, x, numvar)
    ## evaluating the non-linear functions
    #if mode == 1 || model == 3
        #success = model.callbacks.eval_f(x_values, rowno)
        #unsafe_store!(g, value)
    #end

    #if mode == 2 || model == 3
        #jac_res = unsafe_wrap(Array{Float64}, jac, numjac)
        #jac_ind = unsafe_wrap(Array{Cint}, jacnum, numjac)
        #model.callbacks.eval_jac(x_values, rowno, jac_ind, jac_res)
    #end

    return 0
end

function register_callbacks(model::ConoptModel)
    coierror = 0

    ptr = model.cntvect[]

    # pass the callback to CONOPT
    FDEval_c = @cfunction(_FDEval_cb, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Cint,
                                          Ptr{Cint}, Cint, Cint, Ptr{Cint},
                                          Cint, Cint, Cint, Ptr{Cvoid}))
    coierror += LibConopt.COIDEF_FDEval(ptr, FDEval_c)

    ReadMatrix_c = @cfunction(_ReadMatrix_cb, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint},
                                                  Ptr{Cint}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                                  Ptr{Cint}, Ptr{Cdouble}, Ptr{Cint}, Cint,
                                                  Cint, Cint, Ptr{Cvoid}))
    coierror += LibConopt.COIDEF_ReadMatrix(ptr, ReadMatrix_c)

    Message_c = @cfunction(_Message_cb, Cint, (Cint, Cint, Cint, Ptr{Cstring}, Ptr{Cvoid}))
    coierror += LibConopt.COIDEF_Message(ptr, Message_c)

    ErrMsg_c = @cfunction(_ErrMsg_cb, Cint, (Cint, Cint, Cint, Ptr{Cchar}, Ptr{Cvoid}))
    coierror += LibConopt.COIDEF_ErrMsg(ptr, ErrMsg_c)

    Status_c = @cfunction(_Status_cb, Cint, (Cint, Cint, Cint, Cdouble, Ptr{Cvoid}))
    coierror += LibConopt.COIDEF_Status(ptr, Status_c)

    Solution_c = @cfunction(_Solution_cb, Cint, (Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                              Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cint}, Ptr{Cint},
                                              Cint, Cint, Ptr{Cvoid}))
    coierror += LibConopt.COIDEF_Solution(ptr, Solution_c)

    return coierror
end
