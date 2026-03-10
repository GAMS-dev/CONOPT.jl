using JuMP
using Conopt

# Initialize the model
model = Model(Conopt.Optimizer)

# 1. Variables (2 original, 2 new)
@variable(model, x >= 1) #
@variable(model, y >= 1) #
@variable(model, z >= 0)
@variable(model, w >= 0)

# 2. Constraints (Named so we can extract their duals!)
@constraint(model, c1, x + y >= 5) #
@constraint(model, c2, 2*x + z >= 8)
@constraint(model, c3, y + 3*w >= 6)

# 3. Objective Function (Incorporating the new variables)
@objective(model, Min, x + 2*y + 3*z + w + 2) #

# 4. Hand off to Conopt.jl!
optimize!(model) #

# ==========================================
# EXTRACTION PHASE
# ==========================================
println("\n--- SOLVER STATUS ---")

# Termination Status (Uses your MOI.TerminationStatus getter)
status = termination_status(model)
println("Termination Status: ", status)

# Running Time (Uses your MOI.SolveTimeSec getter)
time_sec = solve_time(model)
println("Solve Time: ", time_sec, " seconds")

# We use `has_values` to check your MOI.PrimalStatus before extracting
if has_values(model)
    # Objective Value (Uses your MOI.ObjectiveValue getter)
    println("\nObjective Value: ", objective_value(model))

    # Primal Solutions (Uses your MOI.VariablePrimal getters)
    println("\n--- PRIMAL SOLUTIONS (Variables) ---")
    println("x = ", value(x))
    println("y = ", value(y))
    println("z = ", value(z))
    println("w = ", value(w))
else
    println("\nNo primal solutions available (Solve failed).")
end

# We use `has_duals` to check your MOI.DualStatus before extracting
if has_duals(model)
    # Dual Solutions (Uses your MOI.ConstraintDual getters)
    println("\n--- DUAL SOLUTIONS (Shadow Prices) ---")
    println("Dual of c1 (x + y >= 5)  : ", dual(c1))
    println("Dual of c2 (2x + z >= 8) : ", dual(c2))
    println("Dual of c3 (y + 3w >= 6) : ", dual(c3))

    println("\n--- REDUCED COSTS (Variable Bound Duals) ---")
    println("Reduced cost of x (>= 1) : ", reduced_cost(x))
    println("Reduced cost of y (>= 1) : ", reduced_cost(y))
    println("Reduced cost of z (>= 0) : ", reduced_cost(z))
    println("Reduced cost of w (>= 0) : ", reduced_cost(w))
else
    println("\nNo dual solutions available.")
end
