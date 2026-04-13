$Title Simple NLP Model for CONOPT

* 1. Variables
Positive Variables 
    x
    y
    z
    w;

* The objective must be a free variable in GAMS
Variable 
    obj;

* Set the non-zero lower bounds (Positive Variables default to 0)
x.lo = 1;
y.lo = 1;

* 2. Equation Declarations (Constraints)
Equations 
    obj_eq   "Objective function equation"
    c1       "First constraint"
    c2       "Second constraint"
    c3       "Third constraint";

* 3. Equation Definitions (The Math)
obj_eq.. obj =e= x + 2*y + 3*z + w + 2;

c1..     x + y =g= 5;
c2..     2*x + z =g= 8;
c3..     y + 3*w =g= 6;

* 4. Model Definition
Model simple_lp /all/;
Option nlp = Conopt;

* 5. Hand off to the Solver!
Solve simple_lp using nlp minimizing obj;

* ==========================================
* EXTRACTION PHASE (Displaying results in the .lst file)
* ==========================================

* Primal Solutions (.l stands for level value)
Display "--- PRIMAL SOLUTIONS ---";
Display x.l, y.l, z.l, w.l;
Display obj.l;

* Dual Solutions / Shadow Prices (.m stands for marginal value)
Display "--- DUAL SOLUTIONS (Shadow Prices) ---";
Display c1.m, c2.m, c3.m;

* Reduced Costs (Variable Bound Duals)
Display "--- REDUCED COSTS ---";
Display x.m, y.m, z.m, w.m;
