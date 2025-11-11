include("src/gen/libconopt.jl")
using .LibConopt

cntvect = Ref{Ptr{Cvoid}}()

create_return = LibConopt.COI_Create(cntvect)
println("Create returned ", create_return, " cntvect is ", cntvect)

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

LibConopt.COIDEF_Message(cntvect[], Message_c)
#LibConopt.COIDEF_ErrMsg(vectptr, ErrMsg_c)
println("Registered message")

result = LibConopt.COI_Solve(cntvect[])
println("Result is ", result)

LibConopt.COI_Free(cntvect)
