using PowerSystems
using JuMP

include(string(homedir(),"/.julia/v0.6/PowerSystems/data/data_5bus.jl"))
sys5 = PowerSystem(nodes5, generators5, loads5_DA, branches5, nothing, 230.0, 1000.0)

m = Model()

DevicesNetInjection =  Array{JuMP.GenericAffExpr{Float64,JuMP.Variable},2}(length(sys5.buses), sys5.time_periods)

test_cl = [d for d in sys5.loads if !isa(d, PowerSystems.StaticLoad)] # Filter StaticLoads Out

pcl, IArray = PowerSimulations.loadvariables(m, DevicesNetInjection, sys5.loads, sys5.time_periods);

true