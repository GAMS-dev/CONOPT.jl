module TestMOIWrapper

using Test

import Conopt
import MathOptInterface as MOI

function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$(name)", "test_")
            @testset "$(name)" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
    return
end

function test_SolverName()
    @test MOI.get(Conopt.Optimizer(), MOI.SolverName()) ==
          "CONOPT"
end

end

TestMOIWrapper.runtests()
