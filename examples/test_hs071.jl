using JuMP
using Conopt

model = Model(Conopt.Optimizer)

@variable(model, 1 <= w <= 5)
@variable(model, 1 <= x <= 5)
@variable(model, 1 <= y <= 5)
@variable(model, 1 <= z <= 5)
@variable(model, t >= 0)
@constraint(model, t - (w*z*(w + x + y) + y) >= 0)
@constraint(model, w*x*y*z >= 25)
@constraint(model, w^2 + x^2 + y^2 + z^2 == 40)
@objective(model, Min, t)

optimize!(model)

if has_values(model)
    # Objective Value (Uses your MOI.ObjectiveValue getter)
    println("\nObjective Value: ", objective_value(model))

    # Primal Solutions (Uses your MOI.VariablePrimal getters)
    println("\n--- PRIMAL SOLUTIONS (Variables) ---")
    println("w = ", value(w))
    println("x = ", value(x))
    println("y = ", value(y))
    println("z = ", value(z))
else
    println("\nNo primal solutions available (Solve failed).")
end
