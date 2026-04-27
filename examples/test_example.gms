$title Simple QCQP for Evaluation Testing

Variables
    v1      "Variable 1"
    v2      "Variable 2"
    z       "Objective value"
;

Positive Variables v1, v2;

Equations
    obj_eq      "Objective definition"
    linear_con  "Linear constraint: v1 + v2 >= 1"
    quad_con    "Quadratic constraint: v1^2 + v2^2 == 4"
;

* Objective: 1.0 + 1.0 v[1] + 1.0 v[2] + 2.0 v[1]^2 + v[2] ^ 2 + v[1] * v[2]
obj_eq..
    z =e= 1 + v1 + v2 + 2*sqr(v1) + sqr(v2) + v1*v2;

* ScalarAffineFunction: 0.0 + 1.0 v[1] + 1.0 v[2] >= 1.0
linear_con..
    v1 + v2 =g= 1.0;

* ScalarQuadraticFunction: 0.0 + 1.0 v[1]^2 + 1.0 v[2]^2 == 4.0
quad_con..
    sqr(v1) + sqr(v2) =e= 4.0;

Model simple_qcqp /all/;

* Use CONOPT to match your Julia setup
Option NLP = conopt;

Solve simple_qcqp using nlp minimizing z;

Display v1.l, v2.l, z.l;
