module StateSpace

    using Distributions, ForwardDiff
    using Statistics, LinearAlgebra, Random

    # model types
    export AbstractStateSpaceModel
    export AbstractSSM
    export AbstractGaussianSSM
    export LinearGaussianSSM
    export NonlinearGaussianSSM
    export NonlinearSSM
    
    # filter types
    export AbstractStateSpaceFilter
    export AbstractKalmanFilter
    export LinearKalmanFilter
    export NonlinearKalmanFilter
    export NonlinearFilter
    export KalmanFilter
    export KF
    export ExtendedKalmanFilter
    export EKF
    export UnscentedKalmanFilter
    export UKF
    export EnsembleKalmanFilter
    export EnKF
    export ParticleFilter
    export FilteredState
    export show
    export process_matrix
    export observation_matrix
    export predict
    export observe
    export update
    export update!
    export filter
    export smooth
    export loglikelihood
    export simulate
    
    include("matrix_utils.jl")
    include("model_types.jl")
    include("filtered_states.jl")
    include("filter_types.jl")
    include("common.jl")
    include("particle_filter.jl")

end # module
