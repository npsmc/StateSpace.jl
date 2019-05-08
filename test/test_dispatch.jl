@testset "Testing method dispatch..." begin

# LinearGaussianSSM
#	- LinearKalmanFilter
@test method_exists(predict, (LinearGaussianSSM, AbstractMvNormal))
@test method_exists(update, (LinearGaussianSSM, AbstractMvNormal, Vector))
@test method_exists(update, 
	(LinearGaussianSSM, AbstractMvNormal, Vector, Int))
@test method_exists(update, 
	(LinearGaussianSSM, AbstractMvNormal, Vector, KalmanFilter, Int))

# NonlinearGaussianSSM
#	- NonlinearKalmanFilter
@test method_exists(update,
	(NonlinearGaussianSSM, AbstractMvNormal, Vector))

for T in [NonlinearKalmanFilter, ExtendedKalmanFilter, UnscentedKalmanFilter]
    println(T)
    @test method_exists(update, 
	(NonlinearGaussianSSM, AbstractMvNormal, Vector, T))
    @test method_exists(update, 
		(NonlinearGaussianSSM, AbstractMvNormal, Vector, T, Int))
end

# Special predict methods that don't return just a Distribution
@test method_exists(predict, (NonlinearGaussianSSM, AbstractMvNormal, UKF))
@test method_exists(predict, (NonlinearGaussianSSM, Matrix, EnKF))

@test method_exists(update, 
	(NonlinearGaussianSSM, Matrix, Vector, EnKF))

# NonlinearSSM 			NonlinearFilter


end
