mutable struct Optimizer <: MOI.AbstractOptimizer
    cntvect::Ptr{Cvoid}         # pointer to the CONOPT control vector
    silent::Bool                # whether CONOPT output should be suppressed: affects the output callbacks of CONOPT
    timelimit::Real             # time limit in seconds
    name::String                # name of the model
    params::Dict{String,String} # solver parameters
    threads::Int                # number of threads (0 is default, tells CONOPT to use the maximum number of threads)
    function Optimizer()
        cntvect = Ptr{Cvoid}()
        coierror = LibConopt.COI_Create(Ref{Ptr{Cvoid}}(cntvect))
        if coierror != 0
            error("could not create a CONOPT control vector")
        end
        model = new(cntvect, false, 1e+06)
        finalizer(LibConopt.COI_Free, Ref{Ptr{Cvoid}}(model.cntvect))
        return model
    end
end



# implementations of some basic functions

function Base.summary(io::IO, model::Optimizer)
    return print(io, "CONOPT solver with the control vector pointer $(model.cntvect)")
end

function MOI.is_empty(model::Optimizer)
    # TODO actually check if the model is empty
    return true
end

function MOI.empty!(model::Optimizer)
    # empty the model (TODO: does this also need to free the C problem?)
    return
end



# get, set and supports functions for various Optimizer attributes

# solver name
function MOI.get(::Optimizer, ::MOI.SolverName)::String
    return "CONOPT"
end

# solver version
function MOI.get(::Optimizer, ::MOI.SolverVersion)::String
    major = Ref{Cint}(0)
    minor = Ref{Cint}(0)
    patch = Ref{Cint}(0)
    coierror = LibConopt.COIGET_Version(major, minor, patch)
    if coierror != 0
        error("could not get CONOPT version")
    end
    return string(major[], ".", minor[], ".", patch[])
end

# raw solver
MOI.get(::Optimizer, ::MOI.RawSolver) = model.cntvect

# model name
MOI.get(::Optimizer, ::MOI.Name) = model.name
function MOI.set(::Optimizer, ::MOI.Name, value::String)
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

function MOI.set(::Optimizer, ::MOI.TimeLimitSec, value::Real)
    if value == model.timelimit
        return
    end
    model.timelimit = value
    coierror += LibConopt.COIDEF_ResLim(cntvect, value);
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
    coierror += LibConopt.COIDEF_ResLim(cntvect, 1e+06);
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
    coierror = LibConopt.COIDEF_ThreadS(cntvect, value);
    if coierror != 0
        error("could not set CONOPT number of threads")
    end
    threads = value
    return
end

function MOI.set(model::Optimizer, ::MOI.NumberOfThreads, ::Nothing)
    coierror = LibConopt.COIDEF_ThreadS(cntvect, 0);
    if coierror != 0
        error("could not reset CONOPT number of threads")
    end
    threads = 0
    return
end

MOI.get(model::Optimizer, ::MOI.NumberOfThreads) = model.threads

# gap tolerances not supported by CONOPT
MOI.supports(::Optimizer, ::MOI.AbsoluteGapTolerance) = false
MOI.supports(::Optimizer, ::MOI.RelativeGapTolerance) = false


###
### Optimize and post-optimize functions
###

function MOI.optimize!(model::Optimizer)
    result = LibConopt.COI_Solve(cntvect)
    #t = time()
    #model.variable_primal = nothing
    #model.constraint_primal = nothing
    #model.Cbc_solve_return_code = Cbc_solve(model)
    #model.has_solution = _result_count(model)
    #model.solve_time = time() - t
    #model.termination_status = _termination_status(model)
    return
end
