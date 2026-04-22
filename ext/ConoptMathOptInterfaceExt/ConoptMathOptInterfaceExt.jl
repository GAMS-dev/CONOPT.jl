# Copyright (c) 2013: Iain Dunning, Miles Lubin, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module ConoptMathOptInterfaceExt

import Conopt
import MathOptInterface as MOI
#import PrecompileTools

function __init__()
    setglobal!(Conopt, :Optimizer, Optimizer)
    #setglobal!(Conopt, :CallbackFunction, CallbackFunction)
    #setglobal!(Conopt, :_VectorNonlinearOracle, MOI.VectorNonlinearOracle)
    return nothing
end

include("MOI_wrapper.jl")

end  # module ConoptMathOptInterfaceExt
