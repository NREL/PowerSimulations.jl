"""
Abstract type for Device Formulations (a.k.a Models)

# Example
```julia
import PowerSimulations
const PSI = PowerSimulations
struct MyCustomFormulation <: PSI.AbstractDeviceFormulation
```
"""
abstract type AbstractDeviceFormulation end

"""Formulation that fixes the injection values of devices"""
struct FixedOutput <: AbstractDeviceFormulation end

function _check_device_formulation(
    ::Type{D},
) where {D <: Union{AbstractDeviceFormulation, PSY.Device}}
    if !isconcretetype(D)
        throw(
            ArgumentError(
                "The device model must contain only concrete types, $(D) is an Abstract Type",
            ),
        )
    end
end

"""
Establishes the model for a particular device specified by type. Uses the keyword argument
feedforward to enable passing values between operation model at simulation time

# Arguments
-`::Type{D}`: Power System Device Type
-`::Type{B}`: Abstract Device Formulation

# Accepted Key Words
- `feedforward::Array{<:AbstractAffectFeedForward}` : use to pass parameters between models

# Example
```julia
thermal_gens = DeviceModel(ThermalStandard, ThermalBasicUnitCommitment),
```
"""
mutable struct DeviceModel{D <: PSY.Device, B <: AbstractDeviceFormulation}
    component_type::Type{D}
    formulation::Type{B}
    feedforward::Union{Nothing, Array{<:AbstractAffectFeedForward}}
    services::Vector{ServiceModel}

    function DeviceModel(
        ::Type{D},
        ::Type{B},
        feedforward = nothing,
    ) where {D <: PSY.Device, B <: AbstractDeviceFormulation}
        _check_device_formulation(D)
        _check_device_formulation(B)
        new{D, B}(D, B, feedforward, Vector{ServiceModel}())
    end
end

get_component_type(m::DeviceModel) = m.component_type
get_formulation(m::DeviceModel) = m.formulation
get_feedforward(m::DeviceModel) = m.feedforward
get_services(m::DeviceModel) = m.services
get_services(m::Nothing) = nothing

function _set_model!(dict::Dict, label::String, model::DeviceModel)
    if haskey(dict, label)
        @info("Overwriting $(label) existing model")
    end
    dict[label] = model
    device_models = [m for m in values(dict) if m.component_type == model.component_type]
    if length(device_models) > 1
        throw(
            IS.ConflictingInputsError(
                "A model for devices of type $(model.component_type) is already specified",
            ),
        )
    end
end
