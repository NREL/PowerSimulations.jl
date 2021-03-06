#! format: off

abstract type AbstractAGCFormulation <: AbstractServiceFormulation end
struct PIDSmoothACE <: AbstractAGCFormulation end

"""
Steady State deviation of the frequency
"""
function add_variables!(optimization_container::OptimizationContainer, ::Type{SteadyStateFrequencyDeviation})
    variable_name = make_variable_name(SteadyStateFrequencyDeviation)
    time_steps = model_time_steps(optimization_container)
    variable = add_var_container!(optimization_container, variable_name, time_steps)
    for t in time_steps
        variable[t] = JuMP.@variable(optimization_container.JuMPmodel, base_name = "ΔF_{$(t)}")
    end
end

get_variable_sign(_, ::Type{<:PSY.Area}, ::AbstractAGCFormulation) = NaN
########################## ActivePowerVariable, Area ###########################

get_variable_binary(::ActivePowerVariable, ::Type{<:PSY.Area}, ::AbstractAGCFormulation) = false

########################## SmoothACE, AggregationTopology ###########################

get_variable_binary(::SmoothACE, ::Type{<:PSY.AggregationTopology}, ::AbstractAGCFormulation) = false

########################## DeltaActivePowerUpVariable, Area ###########################

get_variable_binary(::DeltaActivePowerUpVariable, ::Type{<:PSY.Area}, ::AbstractAGCFormulation) = false
get_variable_lower_bound(::DeltaActivePowerUpVariable, ::PSY.Area, ::AbstractAGCFormulation) = 0.0

########################## DeltaActivePowerDownVariable, Area ###########################

get_variable_binary(::DeltaActivePowerDownVariable, ::Type{<:PSY.Area}, ::AbstractAGCFormulation) = false
get_variable_lower_bound(::DeltaActivePowerDownVariable, ::PSY.Area, ::AbstractAGCFormulation) = 0.0

########################## AdditionalDeltaPowerUpVariable, Area ###########################

# Commented out since not in use. These functions will substitute balancing_auxiliary_variables!
# """
# This function add the upwards scheduled regulation variables for power generation output to the model
# """
# function AddVariableSpec(
#     ::Type{AdditionalDeltaActivePowerUpVariable},
#     ::Type{U},
#     optimization_container::OptimizationContainer,
# ) where {U <: PSY.Area}
#     return AddVariableSpec(;
#         variable_name = make_variable_name(AdditionalDeltaActivePowerUpVariable, U),
#         binary = false,
#         lb_value_func = x -> 0.0,
#         expression_name = :emergency_up,
#     )
# end
#
# """
# This function add the variables for power generation output to the model
# """
# function AddVariableSpec(
#     ::Type{AdditionalDeltaActivePowerDownVariable},
#     ::Type{U},
#     optimization_container::OptimizationContainer,
# ) where {U <: PSY.Area}
#     return AddVariableSpec(;
#         variable_name = make_variable_name(AdditionalDeltaActivePowerDownVariable, U),
#         binary = false,
#         lb_value_func = x -> 0.0,
#         expression_name = :emergency_dn,
#     )
# end

########################## AreaMismatchVariable, Area ###########################

make_variable_name(::Type{AreaMismatchVariable}, _) = make_variable_name(AreaMismatchVariable)
get_variable_binary(::AreaMismatchVariable, ::Type{<:PSY.Area}, ::AbstractAGCFormulation) = false

########################## LiftVariable, Area ###########################

make_variable_name(::Type{LiftVariable}, _) = make_variable_name(LiftVariable)
get_variable_binary(::LiftVariable, ::Type{<:PSY.Area}, ::AbstractAGCFormulation) = false
get_variable_lower_bound(::LiftVariable, ::PSY.Area, ::AbstractAGCFormulation) = 0.0

#! format: off

########################## Initial Condition ###########################
function area_control_initial_condition!(
    optimization_container::OptimizationContainer,
    services::Vector{PSY.AGC},
    ::D,
) where {D <: AbstractAGCFormulation}
    key = ICKey(AreaControlError, PSY.AGC)
    _make_initial_conditions!(
        optimization_container,
        services,
        D(),
        nothing,
        key,
        _make_initial_condition_area_control,
        _get_variable_initial_value,
        # Doesn't require Cache
    )

    return
end

function _get_variable_initial_value(
    d::PSY.Component,
    key::ICKey,
    ::AbstractAGCFormulation,
    ::Nothing,
)
    return _get_ace_error(d, key)
end

########################## , ###########################


function balancing_auxiliary_variables!(optimization_container, sys)
    area_names = [PSY.get_name(a) for a in PSY.get_components(PSY.Area, sys)]
    time_steps = model_time_steps(optimization_container)
    R_up_emergency = JuMPVariableArray(undef, area_names, time_steps)
    R_dn_emergency = JuMPVariableArray(undef, area_names, time_steps)
    assign_variable!(
        optimization_container,
        make_variable_name(AdditionalDeltaActivePowerUpVariable, PSY.Area),
        R_up_emergency,
    )
    assign_variable!(
        optimization_container,
        make_variable_name(AdditionalDeltaActivePowerDownVariable, PSY.Area),
        R_dn_emergency,
    )
    emergency_up =
        add_expression_container!(optimization_container, :emergency_up, area_names, time_steps)
    emergency_dn =
        add_expression_container!(optimization_container, :emergency_dn, area_names, time_steps)
    for t in time_steps, a in area_names
        R_up_emergency[a, t] = JuMP.@variable(
            optimization_container.JuMPmodel,
            base_name = "Re_up_{$(a),$(t)}",
            lower_bound = 0.0
        )
        emergency_up[a, t] = R_up_emergency[a, t] + 0.0
        R_dn_emergency[a, t] = JuMP.@variable(
            optimization_container.JuMPmodel,
            base_name = "Re_dn_{$(a),$(t)}",
            lower_bound = 0.0
        )
        emergency_dn[a, t] = R_dn_emergency[a, t] + 0.0
    end

    return
end

function absolute_value_lift(optimization_container::OptimizationContainer, areas)
    time_steps = model_time_steps(optimization_container)
    area_names = [PSY.get_name(a) for a in areas]
    container_lb = JuMPConstraintArray(undef, area_names, time_steps)
    assign_constraint!(optimization_container, "absolute_value_lb", container_lb)
    container_ub = JuMPConstraintArray(undef, area_names, time_steps)
    assign_constraint!(optimization_container, "absolute_value_ub", container_ub)
    mismatch = get_variable(optimization_container, :area_mismatch)
    z = get_variable(optimization_container, :lift)

    for t in time_steps, a in area_names
        container_lb[a, t] =
            JuMP.@constraint(optimization_container.JuMPmodel, mismatch[a, t] <= z[a, t])
        container_ub[a, t] =
            JuMP.@constraint(optimization_container.JuMPmodel, -1 * mismatch[a, t] <= z[a, t])
    end

    JuMP.add_to_expression!(
        optimization_container.cost_function,
        sum(z[a, t] for t in time_steps, a in area_names) * SERVICES_SLACK_COST,
    )
    return
end

"""
Expression for the power deviation given deviation in the frequency. This expression allows updating the response of the frequency depending on commitment decisions
"""
function frequency_response_constraint!(optimization_container::OptimizationContainer, sys::PSY.System)
    time_steps = model_time_steps(optimization_container)
    services = PSY.get_components(PSY.AGC, sys)
    area_names = [PSY.get_name(PSY.get_area(s)) for s in services]
    frequency_response = 0.0
    for area in PSY.get_components(PSY.Area, sys)
        frequency_response += PSY.get_load_response(area)
    end
    for g in PSY.get_components(PSY.RegulationDevice, sys, x -> PSY.get_available(x))
        d = PSY.get_droop(g)
        response = 1 / d
        frequency_response += response
    end

    @assert frequency_response >= 0.0
    # This value is the one updated later in simulation based on the UC result
    inv_frequency_reponse = 1 / frequency_response
    area_balance = get_variable(optimization_container, ActivePowerVariable, PSY.Area)
    frequency = get_variable(optimization_container, "Δf")
    R_up = get_variable(optimization_container, DeltaActivePowerUpVariable, PSY.Area)
    R_dn = get_variable(optimization_container, DeltaActivePowerDownVariable, PSY.Area)
    R_up_emergency =
        get_variable(optimization_container, AdditionalDeltaActivePowerUpVariable, PSY.Area)
    R_dn_emergency =
        get_variable(optimization_container, AdditionalDeltaActivePowerUpVariable, PSY.Area)

    container = JuMPConstraintArray(undef, time_steps)
    assign_constraint!(optimization_container, "frequency_response", container)

    for s in services, t in time_steps
        system_balance = sum(area_balance.data[:, t])
        total_reg = JuMP.AffExpr(0.0)
        for a in area_names
            JuMP.add_to_expression!(total_reg, R_up[a, t])
            JuMP.add_to_expression!(total_reg, -1 * R_dn[a, t])
            JuMP.add_to_expression!(total_reg, R_up_emergency[a, t])
            JuMP.add_to_expression!(total_reg, -1 * R_dn_emergency[a, t])
        end
        container[t] = JuMP.@constraint(
            optimization_container.JuMPmodel,
            frequency[t] == -inv_frequency_reponse * (system_balance + total_reg)
        )
    end
    return
end

function smooth_ace_pid!(optimization_container::OptimizationContainer, services::Vector{PSY.AGC})
    time_steps = model_time_steps(optimization_container)
    area_names = [PSY.get_name(PSY.get_area(s)) for s in services]
    RAW_ACE = add_expression_container!(optimization_container, :RAW_ACE, area_names, time_steps)
    SACE = get_variable(optimization_container, SmoothACE, PSY.Area)
    SACE_pid = JuMPConstraintArray(undef, area_names, time_steps)
    assign_constraint!(optimization_container, "SACE_pid", SACE_pid)

    Δf = get_variable(optimization_container, make_variable_name("Δf"))

    for (ix, service) in enumerate(services)
        kp = PSY.get_K_p(service)
        ki = PSY.get_K_i(service)
        kd = PSY.get_K_d(service)
        B = PSY.get_bias(service)
        Δt = convert(Dates.Second, optimization_container.resolution).value
        a = PSY.get_name(PSY.get_area(service))
        for t in time_steps
            # Todo: Add initial Frequency Deviation
            RAW_ACE[a, t] = -10 * B * Δf[t] + 0.0
            SACE[a, t] =
                JuMP.@variable(optimization_container.JuMPmodel, base_name = "SACE_{$(a),$(t)}")
            if t == 1
                SACE_ini =
                    get_initial_conditions(optimization_container, ICKey(AreaControlError, PSY.AGC))[ix]
                sace_exp = SACE_ini.value + kp * ((1 + Δt / (kp / ki)) * (RAW_ACE[a, t]))
                SACE_pid[a, t] =
                    JuMP.@constraint(optimization_container.JuMPmodel, SACE[a, t] == sace_exp)
                continue
            end
            SACE_pid[a, t] = JuMP.@constraint(
                optimization_container.JuMPmodel,
                SACE[a, t] ==
                SACE[a, t - 1] +
                kp * (
                    (1 + Δt / (kp / ki) + (kd / kp) / Δt) * (RAW_ACE[a, t]) +
                    (-1 - 2 * (kd / kp) / Δt) * (RAW_ACE[a, t - 1])
                )
            )
        end
    end
    return
end

function aux_constraints!(optimization_container::OptimizationContainer, sys::PSY.System)
    time_steps = model_time_steps(optimization_container)
    area_names = [PSY.get_name(a) for a in PSY.get_components(PSY.Area, sys)]
    aux_equation = JuMPConstraintArray(undef, area_names, time_steps)
    assign_constraint!(optimization_container, "balance_aux", aux_equation)
    area_mismatch = get_variable(optimization_container, :area_mismatch)
    SACE = get_variable(optimization_container, SmoothACE, PSY.Area)
    R_up = get_variable(optimization_container, DeltaActivePowerUpVariable, PSY.Area)
    R_dn = get_variable(optimization_container, DeltaActivePowerDownVariable, PSY.Area)
    R_up_emergency =
        get_variable(optimization_container, AdditionalDeltaActivePowerUpVariable, PSY.Area)
    R_dn_emergency =
        get_variable(optimization_container, AdditionalDeltaActivePowerUpVariable, PSY.Area)

    for t in time_steps, a in area_names
        aux_equation[a, t] = JuMP.@constraint(
            optimization_container.JuMPmodel,
            -1 * SACE[a, t] ==
            (R_up[a, t] - R_dn[a, t]) +
            (R_up_emergency[a, t] - R_dn_emergency[a, t]) +
            area_mismatch[a, t]
        )
    end
    return
end
