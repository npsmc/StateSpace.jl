using StateSpace
using Distributions
using Test
using Statistics
using LinearAlgebra

function random_cov(n :: Int)
    A = rand(n, n)
    A = A + A'
    A + n * eye(n)
end

include("test_dispatch.jl")
include("test_KF.jl")
include("test_EKF.jl")
include("test_UKF.jl")
include("test_EnKF.jl")
include("test_particle_filter.jl")
