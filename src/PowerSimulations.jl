module PowerSimulations

using JuMP
using TimeSeries
using PowerSystems
using Compat

#include("core/parameters.jl")
#include("core/models.jl")
#include("core/simulations.jl")

const PowerVariable = JuMP.JuMPArray{JuMP.Variable,2,Tuple{Array{String,1},UnitRange{Int64}}}

#Device Modeling components
include("device_models/renewable_generation.jl")
include("device_models/thermal_generation.jl")
include("device_models/storage.jl")
include("device_models/hydro_generation.jl")
include("device_models/electric_loads.jl")
include("device_models/branches.jl")

#Network related components
include("network_models/node_balance.jl")

#Cost Components
include("cost_functions/thermalgenvariable_cost.jl")
include("cost_functions/thermalgencommitment_cost.jl")
include("cost_functions/renewablegencurtailment_cost.jl")
include("cost_functions/controlableload_cost.jl")
#include("power_models/economic_dispatch.jl")

end # module
