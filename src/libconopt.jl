module LibConopt

using CEnum: CEnum, @cenum

mutable struct coiRec
    CntInfo::NTuple{175, Cint}
end

import ..libconopt

const coiHandle_t = Ptr{coiRec}

# typedef int ( COI_CALLCONV * COI_READMATRIX_t ) ( double LOWER [ ] , double CURR [ ] , double UPPER [ ] , int VSTA [ ] , int TYPEX [ ] , double RHS [ ] , int ESTA [ ] , int COLSTA [ ] , int ROWNO [ ] , double VALUE [ ] , int NLFLAG [ ] , int NUMVAR , int NUMCON , int NUMNZ , void * USRMEM )
const COI_READMATRIX_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_FDEVAL_t ) ( const double X [ ] , double * G , double JAC [ ] , int ROWNO , const int JACNUM [ ] , int MODE , int IGNERR , int * ERRCNT , int NUMVAR , int NUMJAC , int THREAD , void * USRMEM )
const COI_FDEVAL_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_FDEVALINI_t ) ( const double X [ ] , const int ROWLIST [ ] , int MODE , int LISTSIZE , int NUMTHREAD , int IGNERR , int * ERRCNT , int NUMVAR , void * USRMEM )
const COI_FDEVALINI_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_FDEVALEND_t ) ( int IGNERR , int * ERRCNT , void * USRMEM )
const COI_FDEVALEND_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_STATUS_t ) ( int MODSTA , int SOLSTA , int ITER , double OBJVAL , void * USRMEM )
const COI_STATUS_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_SOLUTION_t ) ( const double XVAL [ ] , const double XMAR [ ] , const int XBAS [ ] , const int XSTA [ ] , const double YVAL [ ] , const double YMAR [ ] , const int YBAS [ ] , const int YSTA [ ] , int NUMVAR , int NUMCON , void * USRMEM )
const COI_SOLUTION_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_MESSAGE_t ) ( int SMSG , int DMSG , int NMSG , char * MSGV [ ] , void * USRMEM )
const COI_MESSAGE_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_ERRMSG_t ) ( int ROWNO , int COLNO , int POSNO , const char * MSG , void * USRMEM )
const COI_ERRMSG_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_PROGRESS_t ) ( int LEN_INT , const int INTX [ ] , int LEN_RL , const double RL [ ] , const double X [ ] , void * USRMEM )
const COI_PROGRESS_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_OPTION_t ) ( int NCALL , double * RVAL , int * IVAL , int * LVAL , char * NAME , void * USRMEM )
const COI_OPTION_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_TRIORD_t ) ( int MODE , int TYPEX , int STATUS , int ROWNO , int COLNO , int INF , double VALUE , double RESID , void * USRMEM )
const COI_TRIORD_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_FDINTERVAL_t ) ( const double XMIN [ ] , const double XMAX [ ] , double * GMIN , double * GMAX , double JMIN [ ] , double JMAX [ ] , int ROWNO , const int JACNUM [ ] , int MODE , double PINF , int NUMVAR , int NUMJAC , void * USRMEM )
const COI_FDINTERVAL_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_2DDIR_t ) ( const double X [ ] , const double DX [ ] , double D2G [ ] , int ROWNO , const int JACNUM [ ] , int * NODRV , int NUMVAR , int NUMJAC , int THREAD , void * USRMEM )
const COI_2DDIR_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_2DDIRINI_t ) ( const double X [ ] , const double DX [ ] , const int ROWLIST [ ] , int LISTSIZE , int NUMTHREAD , int NEWPT , int * NODRV , int NUMVAR , void * USRMEM )
const COI_2DDIRINI_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_2DDIREND_t ) ( int * NODRV , void * USRMEM )
const COI_2DDIREND_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_2DDIRLAGR_t ) ( const double X [ ] , const double DX [ ] , const double U [ ] , double D2G [ ] , int NEWPT , int * NODRV , int NUMVAR , int NUMCON , void * USRMEM )
const COI_2DDIRLAGR_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_2DLAGRSIZE_t ) ( int * NODRV , int NUMVAR , int NUMCON , int * NHESS , int MAXHESS , void * USRMEM )
const COI_2DLAGRSIZE_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_2DLAGRSTR_t ) ( int HSRW [ ] , int HSCL [ ] , int * NODRV , int NUMVAR , int NUMCON , int NHESS , void * USRMEM )
const COI_2DLAGRSTR_t = Ptr{Cvoid}

# typedef int ( COI_CALLCONV * COI_2DLAGRVAL_t ) ( const double X [ ] , const double U [ ] , const int HSRW [ ] , const int HSCL [ ] , double HSVL [ ] , int * NODRV , int NUMVAR , int NUMCON , int NHESS , void * USRMEM )
const COI_2DLAGRVAL_t = Ptr{Cvoid}

function COI_Solve(cntvect)
    return ccall((:COI_Solve, libconopt), Cint, (coiHandle_t,), cntvect)
end

function COIGET_Version(major, minor, patch)
    return ccall(
        (:COIGET_Version, libconopt),
        Cvoid,
        (Ptr{Cint}, Ptr{Cint}, Ptr{Cint}),
        major,
        minor,
        patch,
    )
end

function COIGET_MaxThreads(cntvect)
    return ccall((:COIGET_MaxThreads, libconopt), Cint, (coiHandle_t,), cntvect)
end

function COIGET_MaxHeapUsed(cntvect)
    return ccall((:COIGET_MaxHeapUsed, libconopt), Cdouble, (coiHandle_t,), cntvect)
end

function COIGET_RangeErrors(cntvect)
    return ccall((:COIGET_RangeErrors, libconopt), Cint, (coiHandle_t,), cntvect)
end

#function COI_Create(cntvect)
#ccall((:COI_Create, libconopt), Cint, (Ptr{coiHandle_t},), cntvect)
#end

function COI_Create(cntvect)
    return ccall((:COI_Create, libconopt), Cint, (Ptr{Ptr{Cvoid}},), cntvect)
end

#function COI_Free(cntvect)
#ccall((:COI_Free, libconopt), Cint, (Ptr{coiHandle_t},), cntvect)
#end

function COI_Free(cntvect)
    return ccall((:COI_Free, libconopt), Cint, (Ptr{Ptr{Cvoid}},), cntvect)
end

function COI_Finalize()
    return ccall((:COI_Finalize, libconopt), Cvoid, ())
end

function COIDEF_NumVar(cntvect, numvar)
    return ccall((:COIDEF_NumVar, libconopt), Cint, (coiHandle_t, Cint), cntvect, numvar)
end

function COIDEF_NumCon(cntvect, numcon)
    return ccall((:COIDEF_NumCon, libconopt), Cint, (coiHandle_t, Cint), cntvect, numcon)
end

function COIDEF_NumNz(cntvect, numnz)
    return ccall((:COIDEF_NumNz, libconopt), Cint, (coiHandle_t, Cint), cntvect, numnz)
end

function COIDEF_NumNlNz(cntvect, numnlnz)
    return ccall((:COIDEF_NumNlNz, libconopt), Cint, (coiHandle_t, Cint), cntvect, numnlnz)
end

function COIDEF_NumHess(cntvect, numhess)
    return ccall((:COIDEF_NumHess, libconopt), Cint, (coiHandle_t, Cint), cntvect, numhess)
end

function COIDEF_OptDir(cntvect, optdir)
    return ccall((:COIDEF_OptDir, libconopt), Cint, (coiHandle_t, Cint), cntvect, optdir)
end

function COIDEF_ObjVar(cntvect, objvar)
    return ccall((:COIDEF_ObjVar, libconopt), Cint, (coiHandle_t, Cint), cntvect, objvar)
end

function COIDEF_ObjCon(cntvect, objcon)
    return ccall((:COIDEF_ObjCon, libconopt), Cint, (coiHandle_t, Cint), cntvect, objcon)
end

function COIDEF_License(cntvect, licint1, licint2, licint3, licstring)
    return ccall(
        (:COIDEF_License, libconopt),
        Cint,
        (coiHandle_t, Cint, Cint, Cint, Ptr{Cchar}),
        cntvect,
        licint1,
        licint2,
        licint3,
        licstring,
    )
end

function COIDEF_ItLim(cntvect, itlim)
    return ccall((:COIDEF_ItLim, libconopt), Cint, (coiHandle_t, Cint), cntvect, itlim)
end

function COIDEF_ErrLim(cntvect, errlim)
    return ccall((:COIDEF_ErrLim, libconopt), Cint, (coiHandle_t, Cint), cntvect, errlim)
end

function COIDEF_ResLim(cntvect, reslim)
    return ccall((:COIDEF_ResLim, libconopt), Cint, (coiHandle_t, Cdouble), cntvect, reslim)
end

function COIDEF_MaxHeap(cntvect, maxheap)
    return ccall(
        (:COIDEF_MaxHeap, libconopt), Cint, (coiHandle_t, Cdouble), cntvect, maxheap
    )
end

function COIDEF_IniStat(cntvect, inistat)
    return ccall((:COIDEF_IniStat, libconopt), Cint, (coiHandle_t, Cint), cntvect, inistat)
end

function COIDEF_FVincLin(cntvect, fvinclin)
    return ccall(
        (:COIDEF_FVincLin, libconopt), Cint, (coiHandle_t, Cint), cntvect, fvinclin
    )
end

function COIDEF_FVforAll(cntvect, fvforall)
    return ccall(
        (:COIDEF_FVforAll, libconopt), Cint, (coiHandle_t, Cint), cntvect, fvforall
    )
end

function COIDEF_MaxSup(cntvect, maxsup)
    return ccall((:COIDEF_MaxSup, libconopt), Cint, (coiHandle_t, Cint), cntvect, maxsup)
end

function COIDEF_Square(cntvect, square)
    return ccall((:COIDEF_Square, libconopt), Cint, (coiHandle_t, Cint), cntvect, square)
end

function COIDEF_EmptyRow(cntvect, emptyrow)
    return ccall(
        (:COIDEF_EmptyRow, libconopt), Cint, (coiHandle_t, Cint), cntvect, emptyrow
    )
end

function COIDEF_EmptyCol(cntvect, emptycol)
    return ccall(
        (:COIDEF_EmptyCol, libconopt), Cint, (coiHandle_t, Cint), cntvect, emptycol
    )
end

function COIDEF_DisCont(cntvect, discont)
    return ccall((:COIDEF_DisCont, libconopt), Cint, (coiHandle_t, Cint), cntvect, discont)
end

function COIDEF_HessFac(cntvect, hessfac)
    return ccall(
        (:COIDEF_HessFac, libconopt), Cint, (coiHandle_t, Cdouble), cntvect, hessfac
    )
end

function COIDEF_DebugFV(cntvect, debugfv)
    return ccall((:COIDEF_DebugFV, libconopt), Cint, (coiHandle_t, Cint), cntvect, debugfv)
end

function COIDEF_Debug2D(cntvect, debug2d)
    return ccall((:COIDEF_Debug2D, libconopt), Cint, (coiHandle_t, Cint), cntvect, debug2d)
end

function COIDEF_ClearM(cntvect, clearm)
    return ccall((:COIDEF_ClearM, libconopt), Cint, (coiHandle_t, Cint), cntvect, clearm)
end

function COIDEF_ThreadS(cntvect, threads)
    return ccall((:COIDEF_ThreadS, libconopt), Cint, (coiHandle_t, Cint), cntvect, threads)
end

function COIDEF_ThreadF(cntvect, threadf)
    return ccall((:COIDEF_ThreadF, libconopt), Cint, (coiHandle_t, Cint), cntvect, threadf)
end

function COIDEF_Thread2D(cntvect, thread2d)
    return ccall(
        (:COIDEF_Thread2D, libconopt), Cint, (coiHandle_t, Cint), cntvect, thread2d
    )
end

function COIDEF_ThreadC(cntvect, threadc)
    return ccall((:COIDEF_ThreadC, libconopt), Cint, (coiHandle_t, Cint), cntvect, threadc)
end

function COIDEF_StdOut(cntvect, tostdout)
    return ccall((:COIDEF_StdOut, libconopt), Cint, (coiHandle_t, Cint), cntvect, tostdout)
end

function COIDEF_Optfile(cntvect, optfile)
    return ccall(
        (:COIDEF_Optfile, libconopt), Cint, (coiHandle_t, Ptr{Cchar}), cntvect, optfile
    )
end

function COIDEF_ReadMatrix(cntvect, coi_readmatrix)
    return ccall(
        (:COIDEF_ReadMatrix, libconopt),
        Cint,
        (coiHandle_t, COI_READMATRIX_t),
        cntvect,
        coi_readmatrix,
    )
end

function COIDEF_FDEval(cntvect, coi_fdeval)
    return ccall(
        (:COIDEF_FDEval, libconopt), Cint, (coiHandle_t, COI_FDEVAL_t), cntvect, coi_fdeval
    )
end

function COIDEF_FDEvalIni(cntvect, coi_fdevalini)
    return ccall(
        (:COIDEF_FDEvalIni, libconopt),
        Cint,
        (coiHandle_t, COI_FDEVALINI_t),
        cntvect,
        coi_fdevalini,
    )
end

function COIDEF_FDEvalEnd(cntvect, coi_fdevalend)
    return ccall(
        (:COIDEF_FDEvalEnd, libconopt),
        Cint,
        (coiHandle_t, COI_FDEVALEND_t),
        cntvect,
        coi_fdevalend,
    )
end

function COIDEF_Status(cntvect, coi_status)
    return ccall(
        (:COIDEF_Status, libconopt), Cint, (coiHandle_t, COI_STATUS_t), cntvect, coi_status
    )
end

function COIDEF_Solution(cntvect, coi_solution)
    return ccall(
        (:COIDEF_Solution, libconopt),
        Cint,
        (coiHandle_t, COI_SOLUTION_t),
        cntvect,
        coi_solution,
    )
end

function COIDEF_Message(cntvect, coi_message)
    return ccall(
        (:COIDEF_Message, libconopt),
        Cint,
        (Ptr{Cvoid}, COI_MESSAGE_t),
        cntvect,
        coi_message,
    )
end

function COIDEF_ErrMsg(cntvect, coi_errmsg)
    return ccall(
        (:COIDEF_ErrMsg, libconopt), Cint, (Ptr{Cvoid}, COI_ERRMSG_t), cntvect, coi_errmsg
    )
end

function COIDEF_Progress(cntvect, coi_progress)
    return ccall(
        (:COIDEF_Progress, libconopt),
        Cint,
        (coiHandle_t, COI_PROGRESS_t),
        cntvect,
        coi_progress,
    )
end

function COIDEF_Option(cntvect, coi_option)
    return ccall(
        (:COIDEF_Option, libconopt), Cint, (coiHandle_t, COI_OPTION_t), cntvect, coi_option
    )
end

function COIDEF_TriOrd(cntvect, coi_triord)
    return ccall(
        (:COIDEF_TriOrd, libconopt), Cint, (coiHandle_t, COI_TRIORD_t), cntvect, coi_triord
    )
end

function COIDEF_FDInterval(cntvect, coi_fdinterval)
    return ccall(
        (:COIDEF_FDInterval, libconopt),
        Cint,
        (coiHandle_t, COI_FDINTERVAL_t),
        cntvect,
        coi_fdinterval,
    )
end

function COIDEF_2DDir(cntvect, coi_2ddir)
    return ccall(
        (:COIDEF_2DDir, libconopt), Cint, (coiHandle_t, COI_2DDIR_t), cntvect, coi_2ddir
    )
end

function COIDEF_2DDirIni(cntvect, coi_2ddirini)
    return ccall(
        (:COIDEF_2DDirIni, libconopt),
        Cint,
        (coiHandle_t, COI_2DDIRINI_t),
        cntvect,
        coi_2ddirini,
    )
end

function COIDEF_2DDirEnd(cntvect, coi_2ddirend)
    return ccall(
        (:COIDEF_2DDirEnd, libconopt),
        Cint,
        (coiHandle_t, COI_2DDIREND_t),
        cntvect,
        coi_2ddirend,
    )
end

function COIDEF_2DDirLagr(cntvect, coi_2ddirlagr)
    return ccall(
        (:COIDEF_2DDirLagr, libconopt),
        Cint,
        (coiHandle_t, COI_2DDIRLAGR_t),
        cntvect,
        coi_2ddirlagr,
    )
end

function COIDEF_2DLagrSize(cntvect, coi_2dlagrsize)
    return ccall(
        (:COIDEF_2DLagrSize, libconopt),
        Cint,
        (coiHandle_t, COI_2DLAGRSIZE_t),
        cntvect,
        coi_2dlagrsize,
    )
end

function COIDEF_2DLagrStr(cntvect, coi_2dlagrstr)
    return ccall(
        (:COIDEF_2DLagrStr, libconopt),
        Cint,
        (coiHandle_t, COI_2DLAGRSTR_t),
        cntvect,
        coi_2dlagrstr,
    )
end

function COIDEF_2DLagrVal(cntvect, coi_2dlagrval)
    return ccall(
        (:COIDEF_2DLagrVal, libconopt),
        Cint,
        (coiHandle_t, COI_2DLAGRVAL_t),
        cntvect,
        coi_2dlagrval,
    )
end

function COIDEF_UsrMem(cntvect, usrmem)
    return ccall(
        (:COIDEF_UsrMem, libconopt), Cint, (coiHandle_t, Ptr{Cvoid}), cntvect, usrmem
    )
end

const CONOPT_VERSION_MAJOR = 4

const CONOPT_VERSION_MINOR = 39

const CONOPT_VERSION_PATCH = 0

# Skipping MacroDefinition: COI_API __attribute__ ( ( __visibility__ ( "default" ) ) )

end # module
