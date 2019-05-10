using ForwardDiff

import Distributions: AbstractMvNormal

abstract type AbstractStateSpaceModel end
const AbstractSSM = AbstractStateSpaceModel
abstract type AbstractGaussianSSM <: AbstractStateSpaceModel end

# LinearGaussianSSM     LinearKalmanFilter
#                       NonlinearKalmanFilter
#                       NonlinearFilter
#
# NonlinearGaussianSSM  NonlinearKalmanFilter
#                       NonlinearFilter
#
# NonlinearSSM          NonlinearFilter


###########################################################################
# Linear Gaussian 
###########################################################################

struct LinearGaussianSSM <: AbstractGaussianSSM
    # Process transition matrix, control matrix, and noise covariance
    F :: Function
    B :: Function
    V :: Function

    # Observation matrix and noise covariance
    G :: Function
    W :: Function

    # Model dimensions
    nx :: Int
    ny :: Int
    nu :: Int

    function LinearGaussianSSM( F :: Function, 
                                B :: Function, 
                                V :: Function,
                                G :: Function, 
                                W :: Function ) 

        @assert ispossemidef(V(1))
        @assert ispossemidef(W(1))

        nx, ny, nu = confirm_matrix_sizes(F(1), B(1), V(1), G(1), W(1))
        new(F, B, V, G, W, nx, ny, nu)

    end

    ## Time-dependent constructor
    function LinearGaussianSSM( F :: Function, 
                                V :: Function, 
                                G :: Function, 
                                W :: Function ) 
    
        B = _ -> begin zeros(T, (size(V(1), 1), 1)) end where T

        LinearGaussianSSM(F, B, V, G, W)
    
    end
    
    # Time-independent constructor
    function LinearGaussianSSM( F :: Matrix{T}, 
                                V :: Matrix{T}, 
                                G :: Matrix{T}, 
                                W :: Matrix{T}) where T

        B = zeros(T, size(F, 1), 1)
    
        LinearGaussianSSM(_->F, _->B, _->V, _->G, _->W)
    
    end

    function LinearGaussianSSM( F :: Matrix{T}, 
                                V :: Matrix{T}, 
                                G :: Matrix{T}, 
                                W :: Matrix{T},
                                B :: Matrix{T}) where T

        LinearGaussianSSM(_->F, _->B, _->V, _->G, _->W)
    
    end

end

import Base.show

function show(io::IO, mod::LinearGaussianSSM)

    dx, dy = mod.nx, mod.ny 
    println("LinearGaussianSSM, $dx-D process x $dy-D observations")
    println("Process evolution matrix F:")
    show(mod.F(1))
    println("\n\nGontrol input matrix B:")
    show(mod.B(1))
    println("\n\nProcess error covariance V:")
    show(mod.V(1))
    println("\n\nObservation matrix G:")
    show(mod.G(1))
    println("\n\nObseration error covariance W:")
    show(mod.W(1))

end

## Core methods
process_matrix(m::LinearGaussianSSM, state::Vector, t::Real=0.0) = m.F(t)
process_matrix(m::LinearGaussianSSM, state::AbstractMvNormal, t::Real=0.0) = m.F(t)

observation_matrix(m::LinearGaussianSSM, state::Vector, t::Real=0.0) = m.G(t)
observation_matrix(m::LinearGaussianSSM, state::AbstractMvNormal, t::Real=0.0) = m.G(t)

control_input(m::LinearGaussianSSM, u, t::Real=0.0) = m.B(t) * u

###########################################################################
# Nonlinear Gaussian 
###########################################################################

struct NonlinearGaussianSSM <: AbstractGaussianSSM
    # Process transition function, jacobian, and noise covariance matrix
    f :: Function
    V :: Function

    # Control input function
    b :: Function

    # Observation function, 
    g :: Function # actual observation function
    W :: Function

    nx :: Int
    ny :: Int
    nu :: Int

    function NonlinearGaussianSSM( f  :: Function, 
                                   V  :: Function,
                                   b  :: Function, 
                                   g  :: Function, 
                                   W  :: Function, 
                                   nx :: Int, 
                                   ny :: Int, 
                                   nu :: Int) 

        @assert ispossemidef(V(1))
        @assert ispossemidef(W(1))
        @assert (nx, nx) == size(V(1))
        @assert (ny, ny) == size(W(1))

        new(f, V, b, g, W, nx, ny, nu)

    end


    function NonlinearGaussianSSM( f  :: Function, 
                                   V  :: Matrix{T}, 
                                   g  :: Function,
                                   W  :: Matrix{T}; 
                                   nu :: Int=0) where T

        b  = _ -> 0
        nx = size(V, 1)
        ny = size(W, 1)
    
        new(f, _-> V, b, g, _-> W, nx, ny, nu)
    
    end

end


## Core methods
function process_matrix( m :: NonlinearGaussianSSM, 
                         x :: Vector, 
                         t :: Real=0.0) 

    ForwardDiff.jacobian(m.f, x)

end

function process_matrix( m :: NonlinearGaussianSSM, 
                         x :: AbstractMvNormal, 
                         t :: Real=0.0)

    process_matrix(m, mean(x), t)

end

function observation_matrix( m :: NonlinearGaussianSSM, 
                             x :: Vector, 
                             t :: Real=0.0) 

    ForwardDiff.jacobian(m.g, x)

end

function observation_matrix( m :: NonlinearGaussianSSM, 
                             x :: AbstractMvNormal, 
                             t :: Real=0.0) 

    process_matrix(m, mean(x), t)

end

function control_input( m :: NonlinearGaussianSSM, 
                        u, 
                        t :: Real=0.0 ) 
    m.b(u)

end


