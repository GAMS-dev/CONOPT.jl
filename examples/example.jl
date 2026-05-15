using JuMP
using CONOPT

model = Model(CONOPT.Optimizer)

@variable(model, x >= 1)
@variable(model, y >= 1)
@constraint(model, x + y >= 5)
@objective(model, Min, x + 2*y + 2)

optimize!(model)
