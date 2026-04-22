using JuMP
import Conopt
import MathOptInterface as MOI

# This example solves a simple nonlinear problem
# to test the evaluation callbacks.
#
# min (x - 1)^2 + (y - 2)^2
# s.t. x * y >= 4
#      x >= 0
#      y >= 0

model = Model(Conopt.Optimizer)

@variable(model, x >= 0)
@variable(model, y >= 0)

@objective(model, Min, (x - 1)^2 + (y - 2)^2)

@constraint(model, x * y >= 4)

println("Model setup:")
print(model)

println("
Solving...")
optimize!(model)

println("
Results:")
println("Termination status: ", termination_status(model))
println("Primal status: ", primal_status(model))

if termination_status(model) == MOI.OPTIMAL ||
    termination_status(model) == MOI.LOCALLY_SOLVED
    println("
Optimal solution found")
    println("x = ", value(x))
    println("y = ", value(y))
    println("Objective value: ", objective_value(model))
else
    println("
No optimal solution found.")
end
