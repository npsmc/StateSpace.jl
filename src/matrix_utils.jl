# Methods for checking matrix sizes etc.
import LinearAlgebra: issymmetric, eigmin

issquare(x::Matrix) = size(x, 1) == size(x, 2)
ispossemidef(x::Matrix) = issymmetric(x) && (eigmin(x) >= 0)

function confirm_matrix_sizes(F, B, V, G, W)

    nx = size(F, 1)
    nu = size(B, 2)
    ny = size(G, 1)

    @assert size(F) == (nx, nx)
    @assert size(B) == (nx, nu)
    @assert size(V) == (nx, nx)

    @assert size(G) == (ny, nx)
    @assert size(W) == (ny, ny)

    return nx, ny, nu

end 
