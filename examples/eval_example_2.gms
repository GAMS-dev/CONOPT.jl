$title Mixed Linear and Nonlinear Problem

Variables
    x       "Nonlinear variable in objective and constraints"
    y       "Nonlinear variable in objective and constraints"
    z       "Linear variable in constraints, nonlinear in objective"
    objval  "Variable to hold objective value"
;

* Setting bounds equivalent to @variable(model, x >= 0)
Positive Variables x, y, z;

Equations
    objective_eq    "Quadratic objective"
    mixed_con       "Nonlinear (x*y) + Linear (z)"
    exp_con         "Nonlinear (exp) + Linear (y, z)"
    linear_con      "Purely linear constraint"
;

* objective: (x - 1)^2 + (y - 2)^2 + z^2
objective_eq.. 
    objval =e= sqr(x - 1) + sqr(y - 2) + sqr(z);

* x * y + z >= 4 (Mixed)
mixed_con.. 
    x * y + z =g= 4;

* exp(x) + 2y + 3z <= 20 (Mixed)
exp_con.. 
    exp(x) + 2*y + 3*z =l= 20;

* x + y + z = 10 (Purely Linear)
linear_con.. 
    x + y + z =l= 10;

Model mixed_example /all/;

* Specify CONOPT as the NLP solver
Option NLP = conopt;

Solve mixed_example using nlp minimizing objval;

Display x.l, y.l, z.l, objval.l;
