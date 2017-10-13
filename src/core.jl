# TODO: contribute to DifferentialEquations.
function PeriodicCallback(f, Δt::Number; kwargs...)
    next_time = Ref(typemin(Δt))
    condition = (t, u, integrator) -> t == next_time[]
    affect! = function (integrator)
        f(integrator)
        new_time = next_time[] + Δt
        if any(t -> t > new_time, integrator.opts.tstops.valtree) # TODO: accessing internal data...
            next_time[] = new_time
            add_tstop!(integrator, new_time)
        end
    end
    initialize = function (c, t, u, integrator)
        next_time[] = t
        affect!(integrator) # first call should be *before* any time steps have been taken
    end
    DiscreteCallback(condition, affect!; initialize = initialize, kwargs...)
end

function zero_control!(τ::AbstractVector, t, state::MechanismState)
    τ[:] = 0
end

function DiffEqBase.ODEProblem(state::MechanismState{X, M, C}, tspan, control! = zero_control!) where {X, M, C}
    # TODO: running controller at a reduced rate
    # TODO: ability to affect external wrenches

    result = DynamicsResult{C}(state.mechanism)
    τ = similar(velocity(state))
    closed_loop_dynamics! = let state = state, result = result, τ = τ # https://github.com/JuliaLang/julia/issues/15276
        function (t, x, ẋ)
            # TODO: unpack function in RigidBodyDynamics:
            nq = num_positions(state)
            nv = num_velocities(state)
            ns = num_additional_states(state)

            q̇ = view(ẋ, 1 : nq)
            v̇ = view(ẋ, nq + 1 : nq + nv)
            ṡ = view(ẋ, nq + nv + 1 : nq + nv + ns)

            set!(state, x)
            configuration_derivative!(q̇, state)
            control!(τ, t, state)
            dynamics!(result, state, τ)
            v̇[:] = result.v̇
            ṡ[:] = result.ṡ

            ẋ
        end
    end
    x = state_vector(state) # TODO: Vector constructor
    ODEProblem(closed_loop_dynamics!, x, tspan)
end

function configuration_renormalizer(state::MechanismState, condition = (t, u, integrator) -> true)
    renormalize = let state = state # https://github.com/JuliaLang/julia/issues/15276
        function (integrator)
            q = view(integrator.u, 1 : num_positions(state))
            set_configuration!(state, q)
            normalize_configuration!(state)
            q[:] = configuration(state)
            u_modified!(integrator, true)
        end
    end
    DiscreteCallback(condition, renormalize; save_positions = (false, false))
end
