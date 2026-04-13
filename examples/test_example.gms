$title Simple QCQP for Evaluation Testing

Variables
    v1      "Variable 1"
    v2      "Variable 2"
    v3      "Variable 3 (Objective)"
    z       "Objective value"
;

* VariableIndex-in-GreaterThan{Float64}: v[3] >= 0.0
Positive Variables v3;

Equations
    obj_eq      "Objective definition"
    affine_con  "Linear constraint: v1 + v2 >= 1"
    quad_con    "Quadratic constraint: v1^2 + v2^2 - v3^2 <= 0"
;

* Objective: 0.0 + 1.0 v[3]
obj_eq..
    z =e= v3;

* ScalarAffineFunction: 0.0 + 1.0 v[1] + 1.0 v[2] >= 1.0
affine_con..
    v1 + v2 =g= 1.0;

* ScalarQuadraticFunction: 0.0 + 1.0 v[1]^2 + 1.0 v[2]^2 - 1.0 v[3]^2 <= 0.0
quad_con..
    sqr(v1) + sqr(v2) - sqr(v3) =l= 0.0;

Model simple_qcqp /all/;

* Use CONOPT to match your Julia setup
Option NLP = conopt;

Solve simple_qcqp using nlp minimizing z;

Display v1.l, v2.l, v3.l, z.l;
