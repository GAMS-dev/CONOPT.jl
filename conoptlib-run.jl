include("./LibConopt.jl")
using .LibConopt

tpl = ntuple(i->0, 175)
vect = LibConopt.coiRec(tpl)        # coiRec object
vectptr = pointer_from_objref(vect) # pointer to coiRec (= coiHandle_t)
refcntvect = Ref{LibConopt.coiHandle_t}(vectptr)           # pointer to coiHandle_t

create_return = LibConopt.COI_Create(refcntvect)
println("Create returned ", create_return)

major = Ref{Cint}(0)
minor = Ref{Cint}(7)
patch = Ref{Cint}(0)
conoptversion = LibConopt.COIGET_Version(major, minor, patch)
println("version is ", major[], ".", minor[], ".", patch[])

# define a message callback
function Message(smsg, dmsg, nmsg, msgv, usrmem)::Cint
    msg = unsafe_wrap(Vector{Cstring}, msgv, smsg; own = false)
    for i = 1:smsg
         println("message: ", unsafe_string(pointer(msg[i])))
    end
    return 0
end;

function ErrMsg(rowno, colno, posno, msg, usrmem)::Cint
    println("Error message")
    return 0
end;

Message_c = @cfunction(Message, Cint, (Cint, Cint, Cint, Ptr{Cstring}, Ptr{Cvoid}));
ErrMsg_c = @cfunction(ErrMsg, Cint, (Cint, Cint, Cint, Ptr{Cstring}, Ptr{Cvoid}));

LibConopt.COIDEF_Message(refcntvect[], Message_c)
#LibConopt.COIDEF_ErrMsg(vectptr, ErrMsg_c)
println("Registered message")

result = LibConopt.COI_Solve(refcntvect[])
println("Result is ", result)

LibConopt.COI_Free(refcntvect)
