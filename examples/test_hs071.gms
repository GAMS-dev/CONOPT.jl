Variables
    w, x, y, z, t, obj;

* Set the bounds for w, x, y, z
w.lo = 1.0; w.up = 5.0;
x.lo = 1.0; x.up = 5.0;
y.lo = 1.0; y.up = 5.0;
z.lo = 1.0; z.up = 5.0;

* Initial starting points (highly recommended for NLP solvers like CONOPT)
w.l = 1; x.l = 5; y.l = 5; z.l = 1;

Equations
    defobj    'Objective function'
    c1        'First nonlinear constraint'
    c2        'Second nonlinear constraint'
    c3        'Equality constraint';

* Objective: minimize t
defobj.. obj =e= t;

* t - (w*z*(w+x+y) + y) >= 0
c1..     t - (w * z * (w + x + y) + y) =g= 0.0;

* w*x*y*z >= 25
c2..     w * x * y * z =g= 25.0;

* w^2 + x^2 + y^2 + z^2 == 40
c3..     sqr(w) + sqr(x) + sqr(y) + sqr(z) =e= 40.0;

Model hs71 /all/;

* Solve using CONOPT or any other NLP solver
solve hs71 minimizing obj using nlp;
