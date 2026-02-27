
# define the message callback
function _Message_cb(smsg, dmsg, nmsg, msgv, usrmem)::Cint
   msg = unsafe_wrap(Vector{Cstring}, msgv, smsg; own = false)
   for i = 1:smsg
      println("message: ", unsafe_string(pointer(msg[i])))
   end
   return 0
end

function print_raw_bytes(cstr::Cstring)
    ptr = pointer(cstr)  # Get the underlying pointer from Cstring

    if ptr == C_NULL
        println("Pointer is NULL")
        return
    end

    for i in 0:15  # Print the first 16 bytes
        byte = unsafe_load(ptr + i)
        if byte == 0
            println(" (null terminator found)")
            return
        end
        print("0x", hex(byte), " ")
    end
    println()
end


# define the error message callback
function _ErrMsg_cb(rowno, colno, posno, msgptr, usrmem)::Cint
    model = unsafe_pointer_to_objref(usrmem)::Optimizer
    if !model.silent
        if rowno == -1 && colno == -1
            print("CONOPT error/warning about Jacobian element ", posno)
        elseif rowno == -1
            print("CONOPT error/warning about variable ", colno)
        elseif colno == -1
            print("CONOPT error/warning about constraint ", rowno)
        else
            print("CONOPT error/warning about variable ", colno, " appearing in constraint ", rowno)
        end
        if msgptr != C_NULL
            actual_msg = unsafe_string(msgptr)
            print(" : ", actual_msg)
        end
    end
    println()
    return 0
end

# define the status callback
function _Status_cb(modsta, solsta, iter, objval, usrmem)::Cint
   model = unsafe_pointer_to_objref(usrmem)::Optimizer

   model.rawstatus = "CONOPT stopped"
   model.solvetime = 10
   return 0
end

# define the solution callback
function _Solution_cb(xval, xmar, xbas, xsta, yval, ymar, ybas, ysta, numvar, numcon, usrmem)::Cint
   # TODO save solution on the julia side
   return 0
end

"""
    get_conopt_jacobian_info(evaluator, n_vars)

Returns (rows, cols, constant_values, is_nonlinear_mask)
- constant_values: Vector with the value if linear, 0.0 otherwise.
- is_nonlinear_mask: BitVector where 'true' means the value changes with x.
"""
function get_jacobian_info(structure, n_vars::Int)
    nnz = length(structure)

    rows = [s[1] for s in structure]
    cols = [s[2] for s in structure]

    # 2. Evaluate Jacobian at two different random points
    # We use random points to avoid "accidental" equality at 0 or 1
    x1 = randn(n_vars)
    x2 = x1 .+ 0.5  # Perturbed point

    vals1 = zeros(nnz)
    vals2 = zeros(nnz)

    MOI.eval_constraint_jacobian(evaluator, vals1, x1)
    MOI.eval_constraint_jacobian(evaluator, vals2, x2)

    # 3. Identify nonlinear elements
    # If the value changed between x1 and x2, it is nonlinear
    is_nonlinear_mask = BitVector(undef, nnz)
    constant_values = zeros(nnz)

    for i in 1:nnz
        # Use a small tolerance for floating point comparisons
        if isapprox(vals1[i], vals2[i], atol=1e-12)
            is_nonlinear_mask[i] = false
            constant_values[i] = vals1[i]
        else
            is_nonlinear_mask[i] = true
            constant_values[i] = 0.0 # Will be filled by callback
        end
    end

    return structure, rows, cols, constant_values, is_nonlinear_mask
end

function build_nonlinear_row_to_jac_map(structure, is_nonlinear_mask, num_constraints)
    # Preallocate an empty array of integers for each row
    row_to_indices = [Int[] for _ in 1:num_constraints]

    # Loop through the full Jacobian structure
    for flat_index in 1:length(structure)
        # Check if this specific entry is nonlinear
        if is_nonlinear_mask[flat_index]
            r = structure[flat_index][1] # Extract the MOI row index

            # Store the index in the corresponding row's list
            push!(row_to_indices[r], flat_index)
        end
    end

    return row_to_indices
end

# define the read matrix callback
function _ReadMatrix_cb(lower, curr, upper, vsta, constrtype, rhs, esta, colsta, rowno, value, nlflag,
        numvar, numcon, numnz, usrmem)::Cint
    model = unsafe_pointer_to_objref(usrmem)::Optimizer

    @assert numvar == model.model_data.num_variables + model.model_data.num_ranged
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

    return 0
end

# define the function and derivative evaluation callback
function _FDEval_cb(x, g, jac, rowno, jacnum, mode, ignerr, errcnt, numvar, numjac, thread, usrmem)::Cint
    # TODO implement this
    return 0
end


mutable struct ConoptModel
    conopt_model::Ptr{Cvoid}   # pointer to internal data structures. TODO: check if this is needed
    
end
