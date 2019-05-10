@testset "Testing Kalman Filter..." begin

using LinearAlgebra, Statistics, Plots

Random.seed!(0)

F = Matrix(I,4,4) * 0.9
V = random_cov(4)
G = [1.0 0.0 0.5 0.1;
	 0.0 0.5 1.0 1.0]
W = random_cov(2)

m = LinearGaussianSSM(F, V, G, W)
x0 = MvNormal(randn(4), Matrix(I,4,4) .* 100.0)

x1 = predict(m, x0)
println(mean(x1))

y1 = m.G(1) * mean(x1) + randn(2) / 10
u1 = update(m, x1, y1)
println(mean(u1))

xx, yy = simulate(m, 100, x0)
yy[1, 50] = NaN  # throw in a missing value

plot(xx')
savefig("xx.png")
plot(yy')
savefig("yy.png")

fs = filter(m, yy, x0)
 print(fs)

# plot(xx', "k")
# plot(mean(fs)', "r")

y_new = fs.observations[:, end] + randn(2) / 10
update!(m, fs, y_new)

ss = smooth(m, fs)


@test loglikelihood(fs) < loglikelihood(ss)


end
