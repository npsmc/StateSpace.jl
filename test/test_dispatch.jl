@testset "Testing method dispatch..." begin

# LinearGaussianSSM
#    - LinearKalmanFilter
@test hasmethod(predict, (LinearGaussianSSM, AbstractMvNormal))
@test hasmethod(update, (LinearGaussianSSM, AbstractMvNormal, Vector))
@test hasmethod(update, 
    (LinearGaussianSSM, AbstractMvNormal, Vector, Int))
@test hasmethod(update, 
    (LinearGaussianSSM, AbstractMvNormal, Vector, KalmanFilter, Int))

# NonlinearGaussianSSM
#    - NonlinearKalmanFilter
@test hasmethod(update,
    (NonlinearGaussianSSM, AbstractMvNormal, Vector))

for T in [NonlinearKalmanFilter, ExtendedKalmanFilter, UnscentedKalmanFilter]
    println(T)
    @test hasmethod(update, 
    (NonlinearGaussianSSM, AbstractMvNormal, Vector, T))
    @test hasmethod(update, 
        (NonlinearGaussianSSM, AbstractMvNormal, Vector, T, Int))
end

# Special predict methods that don't return just a Distribution
@test hasmethod(predict, (NonlinearGaussianSSM, AbstractMvNormal, UKF))
@test hasmethod(predict, (NonlinearGaussianSSM, Matrix, EnKF))

@test hasmethod(update, 
    (NonlinearGaussianSSM, Matrix, Vector, EnKF))

# NonlinearSSM             NonlinearFilter


end
