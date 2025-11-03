mutable struct Optimizer <: MOI.AbstractOptimizer
    cntvect::Ptr{Cvoid}     # pointer to the CONOPT control vector
    silent::Bool            # whether CONOPT output should be suppressed: affects the output callbacks of CONOPT
    timelimit::Real         # time limit in seconds
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

# solver name
function MOI.get(::Optimizer, ::MOI.SolverName)::String
    return "CONOPT"
end

# TODO get raw solver

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
    # removing the tie limit -> set the time limit to CONOPT's default
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
