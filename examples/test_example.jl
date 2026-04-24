using JuMP
using Conopt

model = Model(Conopt.Optimizer)

@variable(model, v1 >= 0)
@variable(model, v2 >= 0)
#@variable(model, v3 >= 0)
#@constraint(model, v1^2 == 4) #= why is it commented out? =#
@constraint(model, v1 + v2 == 1)
@objective(model, Min, 1 + v1 + v2 + 2*v1^2 + v2^2 + v1*v2)

MOI.set(model, MOI.RawOptimizerAttribute("Lim_Time"), 10)

optimize!(model)

if has_values(model)
    # Objective Value (Uses your MOI.ObjectiveValue getter)
    println("\nObjective Value: ", objective_value(model))

    # Primal Solutions (Uses your MOI.VariablePrimal getters)
    println("\n--- PRIMAL SOLUTIONS (Variables) ---")
    println("v1 = ", value(v1))
    println("v2 = ", value(v2))
    #println("v3 = ", value(v3))
else
    println("\nNo primal solutions available (Solve failed).")
end
