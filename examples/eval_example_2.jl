using JuMP
import Conopt
import MathOptInterface as MOI

model = Model(Conopt.Optimizer)

@variable(model, x >= 0)
@variable(model, y >= 0)
@variable(model, z >= 0)

# 1. Quadratic Objective (Nonlinear)
@objective(model, Min, (x - 1)^2 + (y - 2)^2 + z^2)

# 2. Mixed Constraint: Nonlinear (x*y) + Linear (z)
@constraint(model, mixed_con, x * y + z >= 4)

# 3. Mixed Constraint: Nonlinear (exp(x)) + Linear (y, z)
@constraint(model, exp_con, exp(x) + 2y + 3z <= 20)

# 4. Purely Linear Constraint
@constraint(model, linear_con, x + y + z <= 10)

println("Solving...")
optimize!(model)

println("\nResults:")
println("Termination status: ", termination_status(model))

if termination_status(model) in [MOI.OPTIMAL, MOI.LOCALLY_SOLVED]
    println("x = ", value(x))
    println("y = ", value(y))
    println("z = ", value(z))
    println("Objective: ", objective_value(model))
end
