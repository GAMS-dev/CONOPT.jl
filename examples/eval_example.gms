$title Simple Nonlinear Problem Evaluation Example

* min (x - 1)^2 + (y - 2)^2
* s.t. x * y >= 4
* x >= 0
* y >= 0

Variables
    x    "x variable"
    y    "y variable"
    z    "objective value variable"
;

* This handles the x >= 0 and y >= 0 bounds natively
Positive Variables x, y;

Equations
    obj_eq    "objective function equation"
    con_eq    "nonlinear constraint equation"
;

* GAMS uses sqr() or power() for exponents
obj_eq..
    z =e= sqr(x - 1) + sqr(y - 2);

con_eq..
    x * y =g= 4;

Model eval_example /all/;

* Explicitly tell GAMS to use CONOPT (just like Model(Conopt.Optimizer) in JuMP)
Option NLP = conopt;

Solve eval_example using nlp minimizing z;

* Print the final primal values to the .lst file
Display "--- Optimal Solution Found ---", x.l, y.l, z.l;
