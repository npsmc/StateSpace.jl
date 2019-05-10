
#Linear Kalman Filter With Control Input Example

###Introduction

This notebook is designed to demonstrate how to use the StateSpace.jl package to execute the Kalman filter for a linear State Space model with control input. The example that has been used here closely follows the one given on "Greg Czerniak's Website". Namely the canonball example on [this page.](http://greg.czerniak.info/guides/kalman1/)   

For those of you that do not need/want the explanation of the model and the code, you can skip right to the end of this notebook where the entire section of code required to run this example is given.

###The Problem

The problem considered here is that of firing a ball from a canon at a given angle and velocity from the canon muzzle. We will assume that measurements of the ball's position are recorded with a camera at a given (constant) interval. The camera has a significant error in its measurement. We also measure the ball's velocity with relatively precise detectors inside the ball.

#####Process Model

The kinematic equations for the system are:

$$
\begin{align}
x(t)   &= x_0 + V_0^x t, \\
V^x(t) &= V_0^x, \\
y(t)   &= y_0 + V_0^y t - \frac{1}{2}gt^2, \\
V^y(t) &= V_0^y - gt,
\end{align}
$$

where $x$ is the position of the ball in the x (horizontal) direction, $y$ is the position of the ball in the y (vertical) direction, $V^x$ is the velocity of the ball in the x (horizontal) direction, $V^y$ is the velocity of the ball in the y (vertical) direction, $t$ is time, $x_0$, $y_0$, $V_0^x$ and $V_0^y$ are the initial x and y postion and velocity of the ball. $g$ is the acceleration due to gravity, 9.81 m/s.

Since the filter is discrete we need to discretize our equations so that we get the value of the current state of the ball in terms of the previous. This leads to the following equations:

$$
\begin{align}
x_n   &= x_{n-1} + V_{n-1}^x \Delta t, \\
V^x_n &= V_{n-1}^x, \\
y_n   &= y_{n-1} + V_{n-1}^y \Delta t - \frac{1}{2}g\Delta t^2, \\
V^y_n &= V_{n-1}^y - g\Delta t.
\end{align}
$$

These equations. Can be written in matrix form as:

$$
\begin{bmatrix}
       x_n   \\[0.3em]
       V^x_n \\[0.3em]
       y_n   \\[0.3em]
       V^y_n 
     \end{bmatrix}
     = 
     \begin{bmatrix}
       1 & \Delta t & 0 & 0        \\[0.3em]
       0 & 1        & 0 & 0        \\[0.3em]
       0 & 0        & 1 & \Delta t \\[0.3em]
       0 & 0        & 0 & 1
     \end{bmatrix}
     \begin{bmatrix}
       x_{n-1}   \\[0.3em]
       V^x_{n-1} \\[0.3em]
       y_{n-1}   \\[0.3em]
       V^y_{n-1} 
     \end{bmatrix}
     +
     \begin{bmatrix}
       0 & 0 & 0 & 0        \\[0.3em]
       0 & 0 & 0 & 0        \\[0.3em]
       0 & 0 & 1 & 0 \\[0.3em]
       0 & 0 & 0 & 1
     \end{bmatrix}
     \begin{bmatrix}
       0   \\[0.3em]
       0 \\[0.3em]
       -\frac{1}{2}g\Delta t^2   \\[0.3em]
       -g\Delta t 
     \end{bmatrix},
$$

Which is in the form:
$$
\mathbf{x}_n = \mathbf{A}\mathbf{x}_{n-1} + \mathbf{B}\mathbf{u}_n,
$$

where $\mathbf{x}_n$ is the state vector at the current time step, $\mathbf{A}$ is the process matrix, $\mathbf{B}$ is the control matrix and $\mathbf{u}_n$ is the control input vector.

#####Observation Model

We assume that we measure the position and velocity of the canonball directly and hence the observation (emission) matrix is the identity matrix, namely:

$$
\begin{bmatrix}
       1 & 0 & 0 & 0        \\[0.3em]
       0 & 1 & 0 & 0        \\[0.3em]
       0 & 0 & 1 & 0 \\[0.3em]
       0 & 0 & 0 & 1
\end{bmatrix}
$$

###Setting up the problem
First we'll import the required modules


```julia
using StateSpace
using Distributions
using Gadfly
using Colors
```

#####Generate noisy observations
In this section we will generate the noisy observations using the kinematic equations defined above in their continuous form.   

The first thing to do is to set the parameters of the model


```julia
elevation_angle = 45.0 #Angle above the (horizontal) ground
muzzle_speed = 100.0 #Speed at which the canonball leaves the muzzle
initial_velocity = [muzzle_speed*cos(deg2rad(elevation_angle)), muzzle_speed*sin(deg2rad(elevation_angle))] #initial x and y components of the velocity
gravAcc = 9.81 #gravitational acceleration
initial_location = [0.0, 0.0] # initial position of the canonball
Δt = 0.1 #time between each measurement
```




    0.1



Next we'll define the kinematic equations of the model as functions in Julia (we don't care about the horizontal velocity component because it's constant).


```julia
x_pos(x0::Float64, Vx::Float64, t::Float64) = x0 + Vx*t
y_pos(y0::Float64, Vy::Float64, t::Float64, g::Float64) = y0 + Vy*t - (g * t^2)/2
velocityY(Vy::Float64, t::Float64, g::Float64) = Vy - g * t
```




    velocityY (generic function with 1 method)



Let's now set the variances of the noise for the position and velocity observations. We'll make the positional noise quite big.


```julia
x_pos_var = 200.0
y_pos_var = 200.0
Vx_var = 1.0
Vy_var = 1.0
```




    1.0



Now we will preallocate the arrays to store the true values and the noisy measurements. Then we will create the measurements in a `for` loop


```julia
#Set the number of observations and preallocate vectors to store true and noisy measurement values
numObs = 145
x_pos_true = Vector{Float64}(numObs)
x_pos_obs = Vector{Float64}(numObs)
y_pos_true = Vector{Float64}(numObs)
y_pos_obs = Vector{Float64}(numObs)

Vx_true = Vector{Float64}(numObs)
Vx_obs = Vector{Float64}(numObs)
Vy_true = Vector{Float64}(numObs)
Vy_obs = Vector{Float64}(numObs)

#Generate the data (true values and noisy observations)
for i in 1:numObs
    x_pos_true[i] = x_pos(initial_location[1], initial_velocity[1], (i-1)*Δt)
    y_pos_true[i] = y_pos(initial_location[2], initial_velocity[2], (i-1)*Δt, gravAcc)
    Vx_true[i] = initial_velocity[1]
    Vy_true[i] = velocityY(initial_velocity[2], (i-1)*Δt, gravAcc)

    x_pos_obs[i] = x_pos_true[i] + randn() * sqrt(x_pos_var)
    y_pos_obs[i] = y_pos_true[i] + randn() * sqrt(y_pos_var)
    Vx_obs[i] = Vx_true[i] + randn() * sqrt(Vx_var)
    Vy_obs[i] = Vy_true[i] + randn() * sqrt(Vy_var)
end
#Create the observations vector for the Kalman filter
observations = [x_pos_obs Vx_obs y_pos_obs Vy_obs]'
```




    4x145 Array{Float64,2}:
      5.26679  28.426     26.8539  26.6246  …  1000.9     1008.6      1024.48   
     70.0963   69.7485    70.6661  71.6596       69.3015    71.0265     72.1319 
     18.6518    7.20288  -10.3564  28.2894       19.9131     1.48237    -9.53701
     71.1312   70.1222    69.3649  67.0026      -68.644    -68.4365    -70.083  



The final step in the code block above just puts all of the observations in a single array. Notice that we transpose the array to make sure that the dimensions are consistent with the StateSpace.jl convention. (Each observation is represented by a single column).

#####Define Kalman Filter Parameters

Now we can set the parameters for the process and observation model as defined above. We also set values for the corresponding covariance matrices. Because we're very sure about the process model, we set the process covariance to be very small. The observations can be set to have a higher variance but you can play about with these parameters.   
NOTE: Be carefull about setting the diagonal values to zero, these can result in calculation errors downstream in the matrix calculations - rather the values can be set to be very small.


```julia
process_matrix = [[1.0, Δt, 0.0, 0.0] [0.0, 1.0, 0.0, 0.0] [0.0, 0.0, 1.0, Δt] [0.0, 0.0, 0.0, 1.0]]'
process_covariance = 0.01*eye(4)
observation_matrix = eye(4)
observation_covariance = 0.2*eye(4)
control_matrix = [[0.0, 0.0, 0.0, 0.0] [0.0, 0.0, 0.0, 0.0] [0.0, 0.0, 1.0, 0.0] [0.0, 0.0, 0.0, 1.0]]
control_input = [0.0, 0.0, -(gravAcc * Δt^2)/2, -(gravAcc * Δt)]

#Create an instance of the LKF with the control inputs
linCISMM = LinearGaussianCISSM(process_matrix, process_covariance, observation_matrix, observation_covariance, control_matrix, control_input)
```




    StateSpace.LinearGaussianCISSM{Float64}(4x4 Array{Float64,2}:
     1.0  0.1  0.0  0.0
     0.0  1.0  0.0  0.0
     0.0  0.0  1.0  0.1
     0.0  0.0  0.0  1.0,4x4 Array{Float64,2}:
     0.01  0.0   0.0   0.0 
     0.0   0.01  0.0   0.0 
     0.0   0.0   0.01  0.0 
     0.0   0.0   0.0   0.01,4x4 Array{Float64,2}:
     1.0  0.0  0.0  0.0
     0.0  1.0  0.0  0.0
     0.0  0.0  1.0  0.0
     0.0  0.0  0.0  1.0,4x4 Array{Float64,2}:
     0.2  0.0  0.0  0.0
     0.0  0.2  0.0  0.0
     0.0  0.0  0.2  0.0
     0.0  0.0  0.0  0.2,4x4 Array{Float64,2}:
     0.0  0.0  0.0  0.0
     0.0  0.0  0.0  0.0
     0.0  0.0  1.0  0.0
     0.0  0.0  0.0  1.0,[0.0,0.0,-0.04905000000000001,-0.9810000000000001])



#####Initial Guess 
Now we can make an initial guess for the state of the system (position and velocity). We've purposely set the y coordinate of the initial value way off. This is to show how quickly the Kalman filter can converge to the correct solution. This isn't generally the case. It really depends on how good you model is and also the covariance matrix that you assign to the process/observation models. In this case, if you increase the observation variance (i.e. `observation_covariance = 10*eye(4)` say) then you'll see that it takes the Kalman filter longer to converge to the correct value. 


```julia
initial_guess_state = [0.0, initial_velocity[1], 500.0, initial_velocity[2]]
initial_guess_covariance = eye(4)
initial_guess = MvNormal(initial_guess_state, initial_guess_covariance)
```




    FullNormal(
    dim: 4
    μ: [0.0,70.71067811865476,500.0,70.71067811865474]
    Σ: 4x4 Array{Float64,2}:
     1.0  0.0  0.0  0.0
     0.0  1.0  0.0  0.0
     0.0  0.0  1.0  0.0
     0.0  0.0  0.0  1.0
    )




#####Perform Linear Kalman Filter Algorithm
Now we have all of the parameters:
1. noisy observations
2. process (transition) and observation (emission) model paramaters
3. initial guess of state   

We can use the Kalman Filter to predict the true underlying state (The position - and velocity - of the canonball).


```julia
filtered_state = filter(linCISMM, observations, initial_guess)
```

    SmoothedState{Float64}




    



    
    145 estimates of 4-D process from 4-D observations
    Log-likelihood: -619371.3025340745


###Plot Results
Now we can plot the results to see how well the Kalman Filter predicts the true position of the ball.


```julia
x_filt = Vector{Float64}(numObs)
y_filt = Vector{Float64}(numObs)
for i in 1:numObs
    current_state = filtered_state.state[i]
    x_filt[i] = current_state.μ[1]
    y_filt[i] = current_state.μ[3]
end

n = 3
getColors = distinguishable_colors(n, Color[LCHab(70, 60, 240)],
                                   transform=c -> deuteranopic(c, 0.5),
                                   lchoices=Float64[65, 70, 75, 80],
                                   cchoices=Float64[0, 50, 60, 70],
                                   hchoices=linspace(0, 330, 24))

cannonball_plot = plot(
    layer(x=x_pos_true, y=y_pos_true, Geom.line, Theme(default_color=getColors[3])),
    layer(x=[initial_guess_state[1]; x_filt], y=[initial_guess_state[3]; y_filt], Geom.line, Theme(default_color=getColors[1])),
    layer(x=x_pos_obs, y=y_pos_obs, Geom.point, Theme(default_color=getColors[2])),
    Guide.xlabel("X position"), Guide.ylabel("Y position"),
    Guide.manual_color_key("Colour Key",["Filtered Estimate", "Measurements","True Value "],[getColors[1],getColors[2],getColors[3]]),
    Guide.title("Measurement of a Canonball in Flight")
    )
```




<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:gadfly="http://www.gadflyjl.org/ns"
     version="1.2"
     width="141.42mm" height="100mm" viewBox="0 0 141.42 100"
     stroke="none"
     fill="#000000"
     stroke-width="0.3"
     font-size="3.88"

     id="fig-8cf350439686410badaaa561ba84a807">
<g class="plotroot xscalable yscalable" id="fig-8cf350439686410badaaa561ba84a807-element-1">
  <g font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" fill="#564A55" stroke="#000000" stroke-opacity="0.000" id="fig-8cf350439686410badaaa561ba84a807-element-2">
    <text x="66.38" y="88.39" text-anchor="middle" dy="0.6em">X position</text>
  </g>
  <g class="guide xlabels" font-size="2.82" font-family="'PT Sans Caption','Helvetica Neue','Helvetica',sans-serif" fill="#6C606B" id="fig-8cf350439686410badaaa561ba84a807-element-3">
    <text x="-93.61" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-2000</text>
    <text x="-64.52" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-1500</text>
    <text x="-35.43" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-1000</text>
    <text x="-6.34" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-500</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">0</text>
    <text x="51.83" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">500</text>
    <text x="80.92" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">1000</text>
    <text x="110.01" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">1500</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">2000</text>
    <text x="168.18" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">2500</text>
    <text x="197.27" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">3000</text>
    <text x="226.36" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">3500</text>
    <text x="-64.52" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1500</text>
    <text x="-61.61" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1450</text>
    <text x="-58.7" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1400</text>
    <text x="-55.79" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1350</text>
    <text x="-52.88" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1300</text>
    <text x="-49.97" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1250</text>
    <text x="-47.07" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1200</text>
    <text x="-44.16" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1150</text>
    <text x="-41.25" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1100</text>
    <text x="-38.34" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1050</text>
    <text x="-35.43" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1000</text>
    <text x="-32.52" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-950</text>
    <text x="-29.61" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-900</text>
    <text x="-26.7" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-850</text>
    <text x="-23.8" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-800</text>
    <text x="-20.89" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-750</text>
    <text x="-17.98" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-700</text>
    <text x="-15.07" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-650</text>
    <text x="-12.16" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-600</text>
    <text x="-9.25" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-550</text>
    <text x="-6.34" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-500</text>
    <text x="-3.43" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-450</text>
    <text x="-0.53" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-400</text>
    <text x="2.38" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-350</text>
    <text x="5.29" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-300</text>
    <text x="8.2" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-250</text>
    <text x="11.11" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-200</text>
    <text x="14.02" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-150</text>
    <text x="16.93" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-100</text>
    <text x="19.84" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-50</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">0</text>
    <text x="25.65" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">50</text>
    <text x="28.56" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">100</text>
    <text x="31.47" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">150</text>
    <text x="34.38" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">200</text>
    <text x="37.29" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">250</text>
    <text x="40.2" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">300</text>
    <text x="43.11" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">350</text>
    <text x="46.02" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">400</text>
    <text x="48.92" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">450</text>
    <text x="51.83" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">500</text>
    <text x="54.74" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">550</text>
    <text x="57.65" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">600</text>
    <text x="60.56" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">650</text>
    <text x="63.47" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">700</text>
    <text x="66.38" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">750</text>
    <text x="69.29" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">800</text>
    <text x="72.19" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">850</text>
    <text x="75.1" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">900</text>
    <text x="78.01" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">950</text>
    <text x="80.92" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1000</text>
    <text x="83.83" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1050</text>
    <text x="86.74" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1100</text>
    <text x="89.65" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1150</text>
    <text x="92.56" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1200</text>
    <text x="95.46" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1250</text>
    <text x="98.37" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1300</text>
    <text x="101.28" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1350</text>
    <text x="104.19" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1400</text>
    <text x="107.1" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1450</text>
    <text x="110.01" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1500</text>
    <text x="112.92" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1550</text>
    <text x="115.83" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1600</text>
    <text x="118.73" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1650</text>
    <text x="121.64" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1700</text>
    <text x="124.55" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1750</text>
    <text x="127.46" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1800</text>
    <text x="130.37" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1850</text>
    <text x="133.28" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1900</text>
    <text x="136.19" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1950</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2000</text>
    <text x="142" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2050</text>
    <text x="144.91" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2100</text>
    <text x="147.82" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2150</text>
    <text x="150.73" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2200</text>
    <text x="153.64" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2250</text>
    <text x="156.55" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2300</text>
    <text x="159.46" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2350</text>
    <text x="162.37" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2400</text>
    <text x="165.27" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2450</text>
    <text x="168.18" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2500</text>
    <text x="171.09" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2550</text>
    <text x="174" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2600</text>
    <text x="176.91" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2650</text>
    <text x="179.82" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2700</text>
    <text x="182.73" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2750</text>
    <text x="185.64" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2800</text>
    <text x="188.54" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2850</text>
    <text x="191.45" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2900</text>
    <text x="194.36" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2950</text>
    <text x="197.27" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">3000</text>
    <text x="-93.61" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">-2000</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">0</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">2000</text>
    <text x="255.45" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">4000</text>
    <text x="-64.52" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1500</text>
    <text x="-58.7" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1400</text>
    <text x="-52.88" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1300</text>
    <text x="-47.07" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1200</text>
    <text x="-41.25" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1100</text>
    <text x="-35.43" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1000</text>
    <text x="-29.61" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-900</text>
    <text x="-23.8" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-800</text>
    <text x="-17.98" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-700</text>
    <text x="-12.16" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-600</text>
    <text x="-6.34" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-500</text>
    <text x="-0.53" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-400</text>
    <text x="5.29" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-300</text>
    <text x="11.11" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-200</text>
    <text x="16.93" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-100</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">0</text>
    <text x="28.56" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">100</text>
    <text x="34.38" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">200</text>
    <text x="40.2" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">300</text>
    <text x="46.02" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">400</text>
    <text x="51.83" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">500</text>
    <text x="57.65" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">600</text>
    <text x="63.47" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">700</text>
    <text x="69.29" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">800</text>
    <text x="75.1" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">900</text>
    <text x="80.92" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1000</text>
    <text x="86.74" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1100</text>
    <text x="92.56" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1200</text>
    <text x="98.37" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1300</text>
    <text x="104.19" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1400</text>
    <text x="110.01" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1500</text>
    <text x="115.83" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1600</text>
    <text x="121.64" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1700</text>
    <text x="127.46" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1800</text>
    <text x="133.28" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1900</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2000</text>
    <text x="144.91" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2100</text>
    <text x="150.73" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2200</text>
    <text x="156.55" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2300</text>
    <text x="162.37" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2400</text>
    <text x="168.18" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2500</text>
    <text x="174" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2600</text>
    <text x="179.82" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2700</text>
    <text x="185.64" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2800</text>
    <text x="191.45" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2900</text>
    <text x="197.27" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">3000</text>
  </g>
  <g class="guide colorkey" id="fig-8cf350439686410badaaa561ba84a807-element-4">
    <g fill="#4C404B" font-size="2.82" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" id="fig-8cf350439686410badaaa561ba84a807-element-5">
      <text x="115.82" y="44.85" dy="0.35em">Filtered Estimate</text>
      <text x="115.82" y="48.48" dy="0.35em">Measurements</text>
      <text x="115.82" y="52.1" dy="0.35em">True Value </text>
    </g>
    <g stroke="#000000" stroke-opacity="0.000" id="fig-8cf350439686410badaaa561ba84a807-element-6">
      <rect x="113.01" y="43.94" width="1.81" height="1.81" fill="#00BFFF"/>
      <rect x="113.01" y="47.57" width="1.81" height="1.81" fill="#D4CA3A"/>
      <rect x="113.01" y="51.2" width="1.81" height="1.81" fill="#FF5EA0"/>
    </g>
    <g fill="#362A35" font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" stroke="#000000" stroke-opacity="0.000" id="fig-8cf350439686410badaaa561ba84a807-element-7">
      <text x="113.01" y="41.03">Colour Key</text>
    </g>
  </g>
  <g clip-path="url(#fig-8cf350439686410badaaa561ba84a807-element-9)" id="fig-8cf350439686410badaaa561ba84a807-element-8">
    <g pointer-events="visible" opacity="1" fill="#000000" fill-opacity="0.000" stroke="#000000" stroke-opacity="0.000" class="guide background" id="fig-8cf350439686410badaaa561ba84a807-element-10">
      <rect x="20.75" y="12.61" width="91.26" height="68.1"/>
    </g>
    <g class="guide ygridlines xfixed" stroke-dasharray="0.5,0.5" stroke-width="0.2" stroke="#D0D0E0" id="fig-8cf350439686410badaaa561ba84a807-element-11">
      <path fill="none" d="M20.75,153.5 L 112.01 153.5" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,142.82 L 112.01 142.82" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,132.13 L 112.01 132.13" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,121.45 L 112.01 121.45" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,110.77 L 112.01 110.77" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,100.08 L 112.01 100.08" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,89.4 L 112.01 89.4" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,78.71 L 112.01 78.71" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,57.35 L 112.01 57.35" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,46.66 L 112.01 46.66" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,35.98 L 112.01 35.98" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,25.3 L 112.01 25.3" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,14.61 L 112.01 14.61" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,3.93 L 112.01 3.93" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-6.76 L 112.01 -6.76" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-17.44 L 112.01 -17.44" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-28.12 L 112.01 -28.12" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-49.49 L 112.01 -49.49" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-60.18 L 112.01 -60.18" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,142.82 L 112.01 142.82" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,140.68 L 112.01 140.68" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,138.54 L 112.01 138.54" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,136.41 L 112.01 136.41" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,134.27 L 112.01 134.27" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,132.13 L 112.01 132.13" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,130 L 112.01 130" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,127.86 L 112.01 127.86" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,125.72 L 112.01 125.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,123.59 L 112.01 123.59" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,121.45 L 112.01 121.45" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,119.31 L 112.01 119.31" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,117.18 L 112.01 117.18" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,115.04 L 112.01 115.04" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,112.9 L 112.01 112.9" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,110.77 L 112.01 110.77" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,108.63 L 112.01 108.63" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,106.49 L 112.01 106.49" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,104.36 L 112.01 104.36" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,102.22 L 112.01 102.22" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,100.08 L 112.01 100.08" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,97.95 L 112.01 97.95" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,95.81 L 112.01 95.81" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,93.67 L 112.01 93.67" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,91.54 L 112.01 91.54" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,89.4 L 112.01 89.4" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,87.26 L 112.01 87.26" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,85.13 L 112.01 85.13" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,82.99 L 112.01 82.99" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,80.85 L 112.01 80.85" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,78.71 L 112.01 78.71" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,76.58 L 112.01 76.58" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,74.44 L 112.01 74.44" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,72.3 L 112.01 72.3" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,70.17 L 112.01 70.17" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,65.89 L 112.01 65.89" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,63.76 L 112.01 63.76" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,61.62 L 112.01 61.62" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,59.48 L 112.01 59.48" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,57.35 L 112.01 57.35" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,55.21 L 112.01 55.21" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,53.07 L 112.01 53.07" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,50.94 L 112.01 50.94" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,48.8 L 112.01 48.8" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,46.66 L 112.01 46.66" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,44.53 L 112.01 44.53" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,42.39 L 112.01 42.39" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,40.25 L 112.01 40.25" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,38.12 L 112.01 38.12" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,35.98 L 112.01 35.98" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,33.84 L 112.01 33.84" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,31.71 L 112.01 31.71" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,29.57 L 112.01 29.57" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,27.43 L 112.01 27.43" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,25.3 L 112.01 25.3" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,23.16 L 112.01 23.16" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,21.02 L 112.01 21.02" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,18.89 L 112.01 18.89" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,16.75 L 112.01 16.75" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,14.61 L 112.01 14.61" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,12.47 L 112.01 12.47" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,10.34 L 112.01 10.34" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,8.2 L 112.01 8.2" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,6.06 L 112.01 6.06" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,3.93 L 112.01 3.93" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,1.79 L 112.01 1.79" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-0.35 L 112.01 -0.35" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-2.48 L 112.01 -2.48" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-4.62 L 112.01 -4.62" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-6.76 L 112.01 -6.76" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-8.89 L 112.01 -8.89" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-11.03 L 112.01 -11.03" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-13.17 L 112.01 -13.17" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-15.3 L 112.01 -15.3" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-17.44 L 112.01 -17.44" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-19.58 L 112.01 -19.58" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-21.71 L 112.01 -21.71" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-23.85 L 112.01 -23.85" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-25.99 L 112.01 -25.99" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-28.12 L 112.01 -28.12" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-30.26 L 112.01 -30.26" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-32.4 L 112.01 -32.4" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-34.53 L 112.01 -34.53" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-36.67 L 112.01 -36.67" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-40.94 L 112.01 -40.94" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-43.08 L 112.01 -43.08" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-45.22 L 112.01 -45.22" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-47.35 L 112.01 -47.35" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-49.49 L 112.01 -49.49" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,174.87 L 112.01 174.87" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,-145.65 L 112.01 -145.65" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,142.82 L 112.01 142.82" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,137.48 L 112.01 137.48" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,132.13 L 112.01 132.13" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,126.79 L 112.01 126.79" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,121.45 L 112.01 121.45" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,116.11 L 112.01 116.11" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,110.77 L 112.01 110.77" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,105.42 L 112.01 105.42" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,100.08 L 112.01 100.08" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,94.74 L 112.01 94.74" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,89.4 L 112.01 89.4" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,84.06 L 112.01 84.06" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,78.71 L 112.01 78.71" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,73.37 L 112.01 73.37" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,62.69 L 112.01 62.69" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,57.35 L 112.01 57.35" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,52.01 L 112.01 52.01" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,46.66 L 112.01 46.66" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,41.32 L 112.01 41.32" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,35.98 L 112.01 35.98" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,30.64 L 112.01 30.64" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,25.3 L 112.01 25.3" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,19.95 L 112.01 19.95" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,14.61 L 112.01 14.61" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,9.27 L 112.01 9.27" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,3.93 L 112.01 3.93" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-1.41 L 112.01 -1.41" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-6.76 L 112.01 -6.76" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-12.1 L 112.01 -12.1" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-17.44 L 112.01 -17.44" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-22.78 L 112.01 -22.78" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-28.12 L 112.01 -28.12" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-33.47 L 112.01 -33.47" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-44.15 L 112.01 -44.15" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-49.49 L 112.01 -49.49" gadfly:scale="5.0" visibility="hidden"/>
    </g>
    <g class="guide xgridlines yfixed" stroke-dasharray="0.5,0.5" stroke-width="0.2" stroke="#D0D0E0" id="fig-8cf350439686410badaaa561ba84a807-element-12">
      <path fill="none" d="M-93.61,12.61 L -93.61 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-64.52,12.61 L -64.52 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-35.43,12.61 L -35.43 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-6.34,12.61 L -6.34 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M51.83,12.61 L 51.83 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M80.92,12.61 L 80.92 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M110.01,12.61 L 110.01 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M168.18,12.61 L 168.18 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M197.27,12.61 L 197.27 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M226.36,12.61 L 226.36 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-64.52,12.61 L -64.52 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-61.61,12.61 L -61.61 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-58.7,12.61 L -58.7 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-55.79,12.61 L -55.79 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-52.88,12.61 L -52.88 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-49.97,12.61 L -49.97 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-47.07,12.61 L -47.07 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-44.16,12.61 L -44.16 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-41.25,12.61 L -41.25 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-38.34,12.61 L -38.34 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-35.43,12.61 L -35.43 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-32.52,12.61 L -32.52 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-29.61,12.61 L -29.61 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-26.7,12.61 L -26.7 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-23.8,12.61 L -23.8 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-20.89,12.61 L -20.89 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-17.98,12.61 L -17.98 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-15.07,12.61 L -15.07 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-12.16,12.61 L -12.16 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-9.25,12.61 L -9.25 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-6.34,12.61 L -6.34 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-3.43,12.61 L -3.43 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-0.53,12.61 L -0.53 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M2.38,12.61 L 2.38 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M5.29,12.61 L 5.29 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M8.2,12.61 L 8.2 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M11.11,12.61 L 11.11 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M14.02,12.61 L 14.02 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M16.93,12.61 L 16.93 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M19.84,12.61 L 19.84 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M25.65,12.61 L 25.65 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M28.56,12.61 L 28.56 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M31.47,12.61 L 31.47 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M34.38,12.61 L 34.38 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M37.29,12.61 L 37.29 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M40.2,12.61 L 40.2 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M43.11,12.61 L 43.11 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M46.02,12.61 L 46.02 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M48.92,12.61 L 48.92 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M51.83,12.61 L 51.83 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M54.74,12.61 L 54.74 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M57.65,12.61 L 57.65 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M60.56,12.61 L 60.56 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M63.47,12.61 L 63.47 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M66.38,12.61 L 66.38 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M69.29,12.61 L 69.29 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M72.19,12.61 L 72.19 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M75.1,12.61 L 75.1 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M78.01,12.61 L 78.01 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M80.92,12.61 L 80.92 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M83.83,12.61 L 83.83 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M86.74,12.61 L 86.74 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M89.65,12.61 L 89.65 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M92.56,12.61 L 92.56 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M95.46,12.61 L 95.46 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M98.37,12.61 L 98.37 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M101.28,12.61 L 101.28 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M104.19,12.61 L 104.19 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M107.1,12.61 L 107.1 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M110.01,12.61 L 110.01 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M112.92,12.61 L 112.92 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M115.83,12.61 L 115.83 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M118.73,12.61 L 118.73 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M121.64,12.61 L 121.64 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M124.55,12.61 L 124.55 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M127.46,12.61 L 127.46 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M130.37,12.61 L 130.37 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M133.28,12.61 L 133.28 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M136.19,12.61 L 136.19 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M142,12.61 L 142 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M144.91,12.61 L 144.91 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M147.82,12.61 L 147.82 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M150.73,12.61 L 150.73 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M153.64,12.61 L 153.64 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M156.55,12.61 L 156.55 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M159.46,12.61 L 159.46 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M162.37,12.61 L 162.37 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M165.27,12.61 L 165.27 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M168.18,12.61 L 168.18 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M171.09,12.61 L 171.09 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M174,12.61 L 174 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M176.91,12.61 L 176.91 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M179.82,12.61 L 179.82 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M182.73,12.61 L 182.73 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M185.64,12.61 L 185.64 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M188.54,12.61 L 188.54 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M191.45,12.61 L 191.45 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M194.36,12.61 L 194.36 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M197.27,12.61 L 197.27 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-93.61,12.61 L -93.61 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M255.45,12.61 L 255.45 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M-64.52,12.61 L -64.52 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-58.7,12.61 L -58.7 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-52.88,12.61 L -52.88 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-47.07,12.61 L -47.07 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-41.25,12.61 L -41.25 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-35.43,12.61 L -35.43 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-29.61,12.61 L -29.61 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-23.8,12.61 L -23.8 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-17.98,12.61 L -17.98 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-12.16,12.61 L -12.16 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-6.34,12.61 L -6.34 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-0.53,12.61 L -0.53 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M5.29,12.61 L 5.29 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M11.11,12.61 L 11.11 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M16.93,12.61 L 16.93 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M28.56,12.61 L 28.56 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M34.38,12.61 L 34.38 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M40.2,12.61 L 40.2 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M46.02,12.61 L 46.02 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M51.83,12.61 L 51.83 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M57.65,12.61 L 57.65 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M63.47,12.61 L 63.47 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M69.29,12.61 L 69.29 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M75.1,12.61 L 75.1 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M80.92,12.61 L 80.92 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M86.74,12.61 L 86.74 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M92.56,12.61 L 92.56 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M98.37,12.61 L 98.37 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M104.19,12.61 L 104.19 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M110.01,12.61 L 110.01 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M115.83,12.61 L 115.83 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M121.64,12.61 L 121.64 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M127.46,12.61 L 127.46 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M133.28,12.61 L 133.28 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M144.91,12.61 L 144.91 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M150.73,12.61 L 150.73 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M156.55,12.61 L 156.55 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M162.37,12.61 L 162.37 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M168.18,12.61 L 168.18 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M174,12.61 L 174 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M179.82,12.61 L 179.82 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M185.64,12.61 L 185.64 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M191.45,12.61 L 191.45 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M197.27,12.61 L 197.27 80.72" gadfly:scale="5.0" visibility="hidden"/>
    </g>
    <g class="plotpanel" id="fig-8cf350439686410badaaa561ba84a807-element-13">
      <g class="geometry" id="fig-8cf350439686410badaaa561ba84a807-element-14">
        <g class="color_RGBA{Float32}(0.83092886f0,0.79346967f0,0.22566344f0,1.0f0)" stroke="#FFFFFF" stroke-width="0.3" fill="#D4CA3A" id="fig-8cf350439686410badaaa561ba84a807-element-15">
          <circle cx="23.05" cy="66.04" r="0.9"/>
          <circle cx="24.4" cy="67.26" r="0.9"/>
          <circle cx="24.31" cy="69.14" r="0.9"/>
          <circle cx="24.29" cy="65.01" r="0.9"/>
          <circle cx="24.38" cy="68.08" r="0.9"/>
          <circle cx="24.61" cy="65.06" r="0.9"/>
          <circle cx="24.93" cy="61.66" r="0.9"/>
          <circle cx="26.44" cy="62.82" r="0.9"/>
          <circle cx="26.12" cy="62.85" r="0.9"/>
          <circle cx="26.36" cy="60.86" r="0.9"/>
          <circle cx="26.05" cy="60.07" r="0.9"/>
          <circle cx="25.91" cy="60.24" r="0.9"/>
          <circle cx="27.03" cy="57.95" r="0.9"/>
          <circle cx="28.7" cy="59.86" r="0.9"/>
          <circle cx="28.68" cy="57.37" r="0.9"/>
          <circle cx="27.76" cy="57.81" r="0.9"/>
          <circle cx="29.05" cy="55.32" r="0.9"/>
          <circle cx="29.09" cy="58.23" r="0.9"/>
          <circle cx="29.32" cy="57.43" r="0.9"/>
          <circle cx="31.07" cy="55.17" r="0.9"/>
          <circle cx="31.06" cy="54.49" r="0.9"/>
          <circle cx="31.22" cy="54.98" r="0.9"/>
          <circle cx="32.64" cy="54.23" r="0.9"/>
          <circle cx="32.85" cy="52.45" r="0.9"/>
          <circle cx="30.83" cy="52.31" r="0.9"/>
          <circle cx="34.1" cy="52.21" r="0.9"/>
          <circle cx="33.76" cy="53.37" r="0.9"/>
          <circle cx="34.25" cy="50.16" r="0.9"/>
          <circle cx="33.83" cy="49.54" r="0.9"/>
          <circle cx="35.32" cy="50.14" r="0.9"/>
          <circle cx="34.86" cy="49.38" r="0.9"/>
          <circle cx="36.55" cy="50.8" r="0.9"/>
          <circle cx="35.53" cy="47.8" r="0.9"/>
          <circle cx="37.22" cy="49.65" r="0.9"/>
          <circle cx="38.05" cy="47.72" r="0.9"/>
          <circle cx="37.56" cy="49.2" r="0.9"/>
          <circle cx="38.04" cy="49.51" r="0.9"/>
          <circle cx="37.7" cy="44.7" r="0.9"/>
          <circle cx="39.85" cy="45.78" r="0.9"/>
          <circle cx="37.35" cy="46.96" r="0.9"/>
          <circle cx="37.95" cy="45.16" r="0.9"/>
          <circle cx="38.41" cy="44.33" r="0.9"/>
          <circle cx="40.73" cy="45.31" r="0.9"/>
          <circle cx="42.08" cy="44.79" r="0.9"/>
          <circle cx="41.43" cy="44.38" r="0.9"/>
          <circle cx="40.27" cy="43.71" r="0.9"/>
          <circle cx="41.03" cy="43.38" r="0.9"/>
          <circle cx="42.18" cy="43.96" r="0.9"/>
          <circle cx="43.45" cy="43.36" r="0.9"/>
          <circle cx="43.36" cy="43.33" r="0.9"/>
          <circle cx="43.2" cy="42.6" r="0.9"/>
          <circle cx="44.03" cy="41.8" r="0.9"/>
          <circle cx="43.75" cy="43.57" r="0.9"/>
          <circle cx="45.8" cy="41" r="0.9"/>
          <circle cx="45.21" cy="40.78" r="0.9"/>
          <circle cx="44.54" cy="41.88" r="0.9"/>
          <circle cx="45.95" cy="40.82" r="0.9"/>
          <circle cx="45.03" cy="43.26" r="0.9"/>
          <circle cx="48.08" cy="41.6" r="0.9"/>
          <circle cx="46.86" cy="42.05" r="0.9"/>
          <circle cx="47.53" cy="40.26" r="0.9"/>
          <circle cx="46.11" cy="41.64" r="0.9"/>
          <circle cx="48.66" cy="41.15" r="0.9"/>
          <circle cx="47.37" cy="39.78" r="0.9"/>
          <circle cx="48.61" cy="38.8" r="0.9"/>
          <circle cx="49.27" cy="42.96" r="0.9"/>
          <circle cx="48.9" cy="41.69" r="0.9"/>
          <circle cx="48.57" cy="38.66" r="0.9"/>
          <circle cx="50.96" cy="40.71" r="0.9"/>
          <circle cx="52.23" cy="39.62" r="0.9"/>
          <circle cx="50.57" cy="40.61" r="0.9"/>
          <circle cx="51.64" cy="40.77" r="0.9"/>
          <circle cx="53.61" cy="41.11" r="0.9"/>
          <circle cx="51.68" cy="39.96" r="0.9"/>
          <circle cx="51.89" cy="39.46" r="0.9"/>
          <circle cx="54.23" cy="39.78" r="0.9"/>
          <circle cx="54.02" cy="43.51" r="0.9"/>
          <circle cx="53.94" cy="40.08" r="0.9"/>
          <circle cx="54.67" cy="41.57" r="0.9"/>
          <circle cx="55.07" cy="41.89" r="0.9"/>
          <circle cx="55.51" cy="40.95" r="0.9"/>
          <circle cx="55.77" cy="41.54" r="0.9"/>
          <circle cx="56.75" cy="39.68" r="0.9"/>
          <circle cx="57.35" cy="41.7" r="0.9"/>
          <circle cx="56.23" cy="41.62" r="0.9"/>
          <circle cx="57.94" cy="40.7" r="0.9"/>
          <circle cx="57.46" cy="41.41" r="0.9"/>
          <circle cx="58.51" cy="40.61" r="0.9"/>
          <circle cx="58.4" cy="42.54" r="0.9"/>
          <circle cx="59.78" cy="41.89" r="0.9"/>
          <circle cx="60.12" cy="40.81" r="0.9"/>
          <circle cx="62.1" cy="43.83" r="0.9"/>
          <circle cx="59.38" cy="39.88" r="0.9"/>
          <circle cx="61.18" cy="42.25" r="0.9"/>
          <circle cx="61.52" cy="44.48" r="0.9"/>
          <circle cx="60.73" cy="44.49" r="0.9"/>
          <circle cx="60.92" cy="46.27" r="0.9"/>
          <circle cx="62.44" cy="44.88" r="0.9"/>
          <circle cx="63.83" cy="45.91" r="0.9"/>
          <circle cx="63.58" cy="42.51" r="0.9"/>
          <circle cx="62.49" cy="42.71" r="0.9"/>
          <circle cx="65.02" cy="46.2" r="0.9"/>
          <circle cx="63.12" cy="44.37" r="0.9"/>
          <circle cx="64.62" cy="48.5" r="0.9"/>
          <circle cx="64.69" cy="47.55" r="0.9"/>
          <circle cx="65.34" cy="48.49" r="0.9"/>
          <circle cx="66.79" cy="46.85" r="0.9"/>
          <circle cx="66.87" cy="46.84" r="0.9"/>
          <circle cx="66.31" cy="46.27" r="0.9"/>
          <circle cx="68.68" cy="48.54" r="0.9"/>
          <circle cx="66.76" cy="49.09" r="0.9"/>
          <circle cx="69.36" cy="50.14" r="0.9"/>
          <circle cx="69.54" cy="47.33" r="0.9"/>
          <circle cx="69.67" cy="50.12" r="0.9"/>
          <circle cx="72.35" cy="50.05" r="0.9"/>
          <circle cx="69.97" cy="51.29" r="0.9"/>
          <circle cx="71.06" cy="51.16" r="0.9"/>
          <circle cx="71.27" cy="49.8" r="0.9"/>
          <circle cx="71.29" cy="51.92" r="0.9"/>
          <circle cx="71.33" cy="51.98" r="0.9"/>
          <circle cx="73.05" cy="52.77" r="0.9"/>
          <circle cx="72.77" cy="54.11" r="0.9"/>
          <circle cx="71.8" cy="55.08" r="0.9"/>
          <circle cx="74.28" cy="53.73" r="0.9"/>
          <circle cx="73.4" cy="56.22" r="0.9"/>
          <circle cx="73.94" cy="57.62" r="0.9"/>
          <circle cx="73.88" cy="56.12" r="0.9"/>
          <circle cx="75.42" cy="53.93" r="0.9"/>
          <circle cx="75.19" cy="55.28" r="0.9"/>
          <circle cx="76.38" cy="56.85" r="0.9"/>
          <circle cx="75.2" cy="55.99" r="0.9"/>
          <circle cx="75.04" cy="58.83" r="0.9"/>
          <circle cx="78.01" cy="57.78" r="0.9"/>
          <circle cx="77.84" cy="58.24" r="0.9"/>
          <circle cx="77.26" cy="62.65" r="0.9"/>
          <circle cx="78.13" cy="62.26" r="0.9"/>
          <circle cx="78.31" cy="61.2" r="0.9"/>
          <circle cx="79.68" cy="62" r="0.9"/>
          <circle cx="80.37" cy="62.65" r="0.9"/>
          <circle cx="79.71" cy="64.98" r="0.9"/>
          <circle cx="80.74" cy="66.05" r="0.9"/>
          <circle cx="80.54" cy="66.27" r="0.9"/>
          <circle cx="80.97" cy="65.9" r="0.9"/>
          <circle cx="81.42" cy="67.87" r="0.9"/>
          <circle cx="82.34" cy="69.05" r="0.9"/>
        </g>
      </g>
      <g stroke-width="0.3" fill="#000000" fill-opacity="0.000" class="geometry" stroke-dasharray="none" stroke="#00BFFF" id="fig-8cf350439686410badaaa561ba84a807-element-16">
        <path fill="none" d="M22.75,14.61 L 23.07 57.42 23.91 61.68 24.32 63.79 24.6 63.65 24.85 64.26 25.11 63.94 25.39 62.9 25.93 62.36 26.3 61.94 26.63 61.19 26.83 60.44 26.96 59.9 27.29 59 27.91 58.69 28.4 57.93 28.59 57.43 29 56.52 29.35 56.43 29.66 56.19 30.28 55.54 30.77 54.89 31.19 54.49 31.83 54.02 32.37 53.28 32.37 52.68 33.06 52.18 33.54 52.04 34.02 51.27 34.31 50.54 34.85 50.08 35.17 49.57 35.79 49.48 36.06 48.78 36.63 48.64 37.26 48.13 37.65 48.04 38.06 48.06 38.3 47.06 38.94 46.3 38.95 46.49 39.06 45.79 39.24 45.22 39.88 44.99 40.66 44.7 41.14 44.4 41.28 44.02 41.55 43.67 42 43.52 42.63 43.28 43.1 43.1 43.44 42.81 43.89 42.42 44.18 42.49 44.85 42.02 45.25 41.61 45.42 41.52 45.86 41.24 46.01 41.54 46.77 41.44 47.11 41.46 47.53 41.1 47.55 41.12 48.1 41.04 48.27 40.7 48.67 40.23 49.11 40.74 49.39 40.89 49.54 40.37 50.16 40.41 50.92 40.21 51.17 40.27 51.6 40.37 52.35 40.52 52.53 40.41 52.72 40.22 53.36 40.14 53.82 40.88 54.18 40.74 54.6 40.96 55.02 41.21 55.45 41.22 55.84 41.36 56.36 41.09 56.89 41.3 57.08 41.47 57.58 41.4 57.88 41.51 58.33 41.44 58.67 41.79 59.22 41.95 59.73 41.85 60.56 42.41 60.64 42.03 61.08 42.24 61.5 42.88 61.66 43.4 61.83 44.2 62.28 44.55 62.93 45.05 63.39 44.73 63.53 44.53 64.17 45.11 64.27 45.2 64.66 46.14 64.99 46.7 65.39 47.35 66.01 47.53 66.51 47.67 66.8 47.67 67.52 48.16 67.69 48.65 68.36 49.28 68.94 49.2 69.42 49.73 70.37 50.14 70.61 50.74 71.03 51.18 71.41 51.26 71.71 51.77 71.96 52.2 72.51 52.71 72.89 53.4 72.99 54.16 73.59 54.49 73.87 55.28 74.21 56.2 74.46 56.62 74.99 56.51 75.35 56.7 75.89 57.19 76.07 57.4 76.18 58.18 76.89 58.59 77.41 59.01 77.7 60.28 78.12 61.21 78.49 61.73 79.06 62.31 79.66 62.92 80 63.9 80.48 64.9 80.82 65.75 81.18 66.36 81.55 67.26 82.05 68.22"/>
      </g>
      <g stroke-width="0.3" fill="#000000" fill-opacity="0.000" class="geometry" stroke-dasharray="none" stroke="#FF5EA0" id="fig-8cf350439686410badaaa561ba84a807-element-17">
        <path fill="none" d="M22.75,68.03 L 23.16 67.28 23.57 66.54 23.98 65.81 24.39 65.09 24.8 64.38 25.21 63.69 25.62 63 26.04 62.32 26.45 61.66 26.86 61 27.27 60.36 27.68 59.72 28.09 59.1 28.5 58.48 28.92 57.88 29.33 57.29 29.74 56.7 30.15 56.13 30.56 55.57 30.97 55.02 31.38 54.48 31.79 53.95 32.21 53.43 32.62 52.92 33.03 52.42 33.44 51.93 33.85 51.45 34.26 50.99 34.67 50.53 35.09 50.08 35.5 49.65 35.91 49.22 36.32 48.81 36.73 48.4 37.14 48.01 37.55 47.63 37.97 47.25 38.38 46.89 38.79 46.54 39.2 46.2 39.61 45.87 40.02 45.55 40.43 45.24 40.84 44.94 41.26 44.65 41.67 44.37 42.08 44.1 42.49 43.84 42.9 43.6 43.31 43.36 43.72 43.13 44.14 42.92 44.55 42.71 44.96 42.52 45.37 42.33 45.78 42.16 46.19 42 46.6 41.84 47.02 41.7 47.43 41.57 47.84 41.45 48.25 41.34 48.66 41.24 49.07 41.15 49.48 41.07 49.89 41 50.31 40.94 50.72 40.89 51.13 40.85 51.54 40.83 51.95 40.81 52.36 40.8 52.77 40.81 53.19 40.82 53.6 40.85 54.01 40.88 54.42 40.93 54.83 40.99 55.24 41.06 55.65 41.13 56.07 41.22 56.48 41.32 56.89 41.43 57.3 41.55 57.71 41.68 58.12 41.82 58.53 41.97 58.94 42.13 59.36 42.3 59.77 42.49 60.18 42.68 60.59 42.88 61 43.1 61.41 43.32 61.82 43.56 62.24 43.8 62.65 44.06 63.06 44.32 63.47 44.6 63.88 44.89 64.29 45.19 64.7 45.5 65.12 45.81 65.53 46.14 65.94 46.48 66.35 46.83 66.76 47.19 67.17 47.57 67.58 47.95 67.99 48.34 68.41 48.74 68.82 49.16 69.23 49.58 69.64 50.01 70.05 50.46 70.46 50.91 70.87 51.38 71.29 51.85 71.7 52.34 72.11 52.84 72.52 53.35 72.93 53.86 73.34 54.39 73.75 54.93 74.17 55.48 74.58 56.04 74.99 56.61 75.4 57.19 75.81 57.78 76.22 58.38 76.63 59 77.04 59.62 77.46 60.25 77.87 60.9 78.28 61.55 78.69 62.22 79.1 62.89 79.51 63.58 79.92 64.27 80.34 64.98 80.75 65.7 81.16 66.42 81.57 67.16 81.98 67.91"/>
      </g>
    </g>
    <g opacity="0" class="guide zoomslider" stroke="#000000" stroke-opacity="0.000" id="fig-8cf350439686410badaaa561ba84a807-element-18">
      <g fill="#EAEAEA" stroke-width="0.3" stroke-opacity="0" stroke="#6A6A6A" id="fig-8cf350439686410badaaa561ba84a807-element-19">
        <rect x="105.01" y="15.61" width="4" height="4"/>
        <g class="button_logo" fill="#6A6A6A" id="fig-8cf350439686410badaaa561ba84a807-element-20">
          <path d="M105.81,17.21 L 106.61 17.21 106.61 16.41 107.41 16.41 107.41 17.21 108.21 17.21 108.21 18.01 107.41 18.01 107.41 18.81 106.61 18.81 106.61 18.01 105.81 18.01 z"/>
        </g>
      </g>
      <g fill="#EAEAEA" id="fig-8cf350439686410badaaa561ba84a807-element-21">
        <rect x="85.51" y="15.61" width="19" height="4"/>
      </g>
      <g class="zoomslider_thumb" fill="#6A6A6A" id="fig-8cf350439686410badaaa561ba84a807-element-22">
        <rect x="94.01" y="15.61" width="2" height="4"/>
      </g>
      <g fill="#EAEAEA" stroke-width="0.3" stroke-opacity="0" stroke="#6A6A6A" id="fig-8cf350439686410badaaa561ba84a807-element-23">
        <rect x="81.01" y="15.61" width="4" height="4"/>
        <g class="button_logo" fill="#6A6A6A" id="fig-8cf350439686410badaaa561ba84a807-element-24">
          <path d="M81.81,17.21 L 84.21 17.21 84.21 18.01 81.81 18.01 z"/>
        </g>
      </g>
    </g>
  </g>
  <g class="guide ylabels" font-size="2.82" font-family="'PT Sans Caption','Helvetica Neue','Helvetica',sans-serif" fill="#6C606B" id="fig-8cf350439686410badaaa561ba84a807-element-25">
    <text x="19.74" y="153.5" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-800</text>
    <text x="19.74" y="142.82" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-700</text>
    <text x="19.74" y="132.13" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-600</text>
    <text x="19.74" y="121.45" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-500</text>
    <text x="19.74" y="110.77" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-400</text>
    <text x="19.74" y="100.08" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-300</text>
    <text x="19.74" y="89.4" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-200</text>
    <text x="19.74" y="78.71" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">-100</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">0</text>
    <text x="19.74" y="57.35" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">100</text>
    <text x="19.74" y="46.66" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">200</text>
    <text x="19.74" y="35.98" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">300</text>
    <text x="19.74" y="25.3" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">400</text>
    <text x="19.74" y="14.61" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">500</text>
    <text x="19.74" y="3.93" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">600</text>
    <text x="19.74" y="-6.76" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">700</text>
    <text x="19.74" y="-17.44" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">800</text>
    <text x="19.74" y="-28.12" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">900</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">1000</text>
    <text x="19.74" y="-49.49" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">1100</text>
    <text x="19.74" y="-60.18" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">1200</text>
    <text x="19.74" y="142.82" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-700</text>
    <text x="19.74" y="140.68" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-680</text>
    <text x="19.74" y="138.54" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-660</text>
    <text x="19.74" y="136.41" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-640</text>
    <text x="19.74" y="134.27" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-620</text>
    <text x="19.74" y="132.13" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-600</text>
    <text x="19.74" y="130" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-580</text>
    <text x="19.74" y="127.86" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-560</text>
    <text x="19.74" y="125.72" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-540</text>
    <text x="19.74" y="123.59" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-520</text>
    <text x="19.74" y="121.45" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-500</text>
    <text x="19.74" y="119.31" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-480</text>
    <text x="19.74" y="117.18" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-460</text>
    <text x="19.74" y="115.04" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-440</text>
    <text x="19.74" y="112.9" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-420</text>
    <text x="19.74" y="110.77" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-400</text>
    <text x="19.74" y="108.63" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-380</text>
    <text x="19.74" y="106.49" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-360</text>
    <text x="19.74" y="104.36" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-340</text>
    <text x="19.74" y="102.22" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-320</text>
    <text x="19.74" y="100.08" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-300</text>
    <text x="19.74" y="97.95" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-280</text>
    <text x="19.74" y="95.81" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-260</text>
    <text x="19.74" y="93.67" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-240</text>
    <text x="19.74" y="91.54" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-220</text>
    <text x="19.74" y="89.4" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-200</text>
    <text x="19.74" y="87.26" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-180</text>
    <text x="19.74" y="85.13" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-160</text>
    <text x="19.74" y="82.99" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-140</text>
    <text x="19.74" y="80.85" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-120</text>
    <text x="19.74" y="78.71" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-100</text>
    <text x="19.74" y="76.58" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-80</text>
    <text x="19.74" y="74.44" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-60</text>
    <text x="19.74" y="72.3" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-40</text>
    <text x="19.74" y="70.17" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-20</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">0</text>
    <text x="19.74" y="65.89" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">20</text>
    <text x="19.74" y="63.76" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">40</text>
    <text x="19.74" y="61.62" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">60</text>
    <text x="19.74" y="59.48" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">80</text>
    <text x="19.74" y="57.35" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">100</text>
    <text x="19.74" y="55.21" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">120</text>
    <text x="19.74" y="53.07" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">140</text>
    <text x="19.74" y="50.94" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">160</text>
    <text x="19.74" y="48.8" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">180</text>
    <text x="19.74" y="46.66" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">200</text>
    <text x="19.74" y="44.53" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">220</text>
    <text x="19.74" y="42.39" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">240</text>
    <text x="19.74" y="40.25" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">260</text>
    <text x="19.74" y="38.12" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">280</text>
    <text x="19.74" y="35.98" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">300</text>
    <text x="19.74" y="33.84" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">320</text>
    <text x="19.74" y="31.71" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">340</text>
    <text x="19.74" y="29.57" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">360</text>
    <text x="19.74" y="27.43" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">380</text>
    <text x="19.74" y="25.3" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">400</text>
    <text x="19.74" y="23.16" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">420</text>
    <text x="19.74" y="21.02" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">440</text>
    <text x="19.74" y="18.89" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">460</text>
    <text x="19.74" y="16.75" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">480</text>
    <text x="19.74" y="14.61" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">500</text>
    <text x="19.74" y="12.47" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">520</text>
    <text x="19.74" y="10.34" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">540</text>
    <text x="19.74" y="8.2" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">560</text>
    <text x="19.74" y="6.06" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">580</text>
    <text x="19.74" y="3.93" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">600</text>
    <text x="19.74" y="1.79" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">620</text>
    <text x="19.74" y="-0.35" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">640</text>
    <text x="19.74" y="-2.48" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">660</text>
    <text x="19.74" y="-4.62" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">680</text>
    <text x="19.74" y="-6.76" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">700</text>
    <text x="19.74" y="-8.89" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">720</text>
    <text x="19.74" y="-11.03" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">740</text>
    <text x="19.74" y="-13.17" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">760</text>
    <text x="19.74" y="-15.3" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">780</text>
    <text x="19.74" y="-17.44" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">800</text>
    <text x="19.74" y="-19.58" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">820</text>
    <text x="19.74" y="-21.71" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">840</text>
    <text x="19.74" y="-23.85" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">860</text>
    <text x="19.74" y="-25.99" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">880</text>
    <text x="19.74" y="-28.12" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">900</text>
    <text x="19.74" y="-30.26" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">920</text>
    <text x="19.74" y="-32.4" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">940</text>
    <text x="19.74" y="-34.53" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">960</text>
    <text x="19.74" y="-36.67" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">980</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1000</text>
    <text x="19.74" y="-40.94" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1020</text>
    <text x="19.74" y="-43.08" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1040</text>
    <text x="19.74" y="-45.22" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1060</text>
    <text x="19.74" y="-47.35" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1080</text>
    <text x="19.74" y="-49.49" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1100</text>
    <text x="19.74" y="174.87" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">-1000</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">0</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">1000</text>
    <text x="19.74" y="-145.65" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">2000</text>
    <text x="19.74" y="142.82" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-700</text>
    <text x="19.74" y="137.48" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-650</text>
    <text x="19.74" y="132.13" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-600</text>
    <text x="19.74" y="126.79" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-550</text>
    <text x="19.74" y="121.45" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-500</text>
    <text x="19.74" y="116.11" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-450</text>
    <text x="19.74" y="110.77" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-400</text>
    <text x="19.74" y="105.42" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-350</text>
    <text x="19.74" y="100.08" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-300</text>
    <text x="19.74" y="94.74" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-250</text>
    <text x="19.74" y="89.4" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-200</text>
    <text x="19.74" y="84.06" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-150</text>
    <text x="19.74" y="78.71" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-100</text>
    <text x="19.74" y="73.37" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-50</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">0</text>
    <text x="19.74" y="62.69" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">50</text>
    <text x="19.74" y="57.35" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">100</text>
    <text x="19.74" y="52.01" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">150</text>
    <text x="19.74" y="46.66" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">200</text>
    <text x="19.74" y="41.32" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">250</text>
    <text x="19.74" y="35.98" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">300</text>
    <text x="19.74" y="30.64" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">350</text>
    <text x="19.74" y="25.3" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">400</text>
    <text x="19.74" y="19.95" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">450</text>
    <text x="19.74" y="14.61" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">500</text>
    <text x="19.74" y="9.27" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">550</text>
    <text x="19.74" y="3.93" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">600</text>
    <text x="19.74" y="-1.41" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">650</text>
    <text x="19.74" y="-6.76" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">700</text>
    <text x="19.74" y="-12.1" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">750</text>
    <text x="19.74" y="-17.44" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">800</text>
    <text x="19.74" y="-22.78" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">850</text>
    <text x="19.74" y="-28.12" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">900</text>
    <text x="19.74" y="-33.47" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">950</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">1000</text>
    <text x="19.74" y="-44.15" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">1050</text>
    <text x="19.74" y="-49.49" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">1100</text>
  </g>
  <g font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" fill="#564A55" stroke="#000000" stroke-opacity="0.000" id="fig-8cf350439686410badaaa561ba84a807-element-26">
    <text x="8.81" y="44.66" text-anchor="middle" dy="0.35em" transform="rotate(-90, 8.81, 46.66)">Y position</text>
  </g>
  <g font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" fill="#564A55" stroke="#000000" stroke-opacity="0.000" id="fig-8cf350439686410badaaa561ba84a807-element-27">
    <text x="66.38" y="10.61" text-anchor="middle">Measurement of a Canonball in Flight</text>
  </g>
</g>
<defs>
<clipPath id="fig-8cf350439686410badaaa561ba84a807-element-9">
  <path d="M20.75,12.61 L 112.01 12.61 112.01 80.72 20.75 80.72" />
</clipPath
></defs>
<script> <![CDATA[
(function(N){var k=/[\.\/]/,L=/\s*,\s*/,C=function(a,d){return a-d},a,v,y={n:{}},M=function(){for(var a=0,d=this.length;a<d;a++)if("undefined"!=typeof this[a])return this[a]},A=function(){for(var a=this.length;--a;)if("undefined"!=typeof this[a])return this[a]},w=function(k,d){k=String(k);var f=v,n=Array.prototype.slice.call(arguments,2),u=w.listeners(k),p=0,b,q=[],e={},l=[],r=a;l.firstDefined=M;l.lastDefined=A;a=k;for(var s=v=0,x=u.length;s<x;s++)"zIndex"in u[s]&&(q.push(u[s].zIndex),0>u[s].zIndex&&
(e[u[s].zIndex]=u[s]));for(q.sort(C);0>q[p];)if(b=e[q[p++] ],l.push(b.apply(d,n)),v)return v=f,l;for(s=0;s<x;s++)if(b=u[s],"zIndex"in b)if(b.zIndex==q[p]){l.push(b.apply(d,n));if(v)break;do if(p++,(b=e[q[p] ])&&l.push(b.apply(d,n)),v)break;while(b)}else e[b.zIndex]=b;else if(l.push(b.apply(d,n)),v)break;v=f;a=r;return l};w._events=y;w.listeners=function(a){a=a.split(k);var d=y,f,n,u,p,b,q,e,l=[d],r=[];u=0;for(p=a.length;u<p;u++){e=[];b=0;for(q=l.length;b<q;b++)for(d=l[b].n,f=[d[a[u] ],d["*"] ],n=2;n--;)if(d=
f[n])e.push(d),r=r.concat(d.f||[]);l=e}return r};w.on=function(a,d){a=String(a);if("function"!=typeof d)return function(){};for(var f=a.split(L),n=0,u=f.length;n<u;n++)(function(a){a=a.split(k);for(var b=y,f,e=0,l=a.length;e<l;e++)b=b.n,b=b.hasOwnProperty(a[e])&&b[a[e] ]||(b[a[e] ]={n:{}});b.f=b.f||[];e=0;for(l=b.f.length;e<l;e++)if(b.f[e]==d){f=!0;break}!f&&b.f.push(d)})(f[n]);return function(a){+a==+a&&(d.zIndex=+a)}};w.f=function(a){var d=[].slice.call(arguments,1);return function(){w.apply(null,
[a,null].concat(d).concat([].slice.call(arguments,0)))}};w.stop=function(){v=1};w.nt=function(k){return k?(new RegExp("(?:\\.|\\/|^)"+k+"(?:\\.|\\/|$)")).test(a):a};w.nts=function(){return a.split(k)};w.off=w.unbind=function(a,d){if(a){var f=a.split(L);if(1<f.length)for(var n=0,u=f.length;n<u;n++)w.off(f[n],d);else{for(var f=a.split(k),p,b,q,e,l=[y],n=0,u=f.length;n<u;n++)for(e=0;e<l.length;e+=q.length-2){q=[e,1];p=l[e].n;if("*"!=f[n])p[f[n] ]&&q.push(p[f[n] ]);else for(b in p)p.hasOwnProperty(b)&&
q.push(p[b]);l.splice.apply(l,q)}n=0;for(u=l.length;n<u;n++)for(p=l[n];p.n;){if(d){if(p.f){e=0;for(f=p.f.length;e<f;e++)if(p.f[e]==d){p.f.splice(e,1);break}!p.f.length&&delete p.f}for(b in p.n)if(p.n.hasOwnProperty(b)&&p.n[b].f){q=p.n[b].f;e=0;for(f=q.length;e<f;e++)if(q[e]==d){q.splice(e,1);break}!q.length&&delete p.n[b].f}}else for(b in delete p.f,p.n)p.n.hasOwnProperty(b)&&p.n[b].f&&delete p.n[b].f;p=p.n}}}else w._events=y={n:{}}};w.once=function(a,d){var f=function(){w.unbind(a,f);return d.apply(this,
arguments)};return w.on(a,f)};w.version="0.4.2";w.toString=function(){return"You are running Eve 0.4.2"};"undefined"!=typeof module&&module.exports?module.exports=w:"function"===typeof define&&define.amd?define("eve",[],function(){return w}):N.eve=w})(this);
(function(N,k){"function"===typeof define&&define.amd?define("Snap.svg",["eve"],function(L){return k(N,L)}):k(N,N.eve)})(this,function(N,k){var L=function(a){var k={},y=N.requestAnimationFrame||N.webkitRequestAnimationFrame||N.mozRequestAnimationFrame||N.oRequestAnimationFrame||N.msRequestAnimationFrame||function(a){setTimeout(a,16)},M=Array.isArray||function(a){return a instanceof Array||"[object Array]"==Object.prototype.toString.call(a)},A=0,w="M"+(+new Date).toString(36),z=function(a){if(null==
a)return this.s;var b=this.s-a;this.b+=this.dur*b;this.B+=this.dur*b;this.s=a},d=function(a){if(null==a)return this.spd;this.spd=a},f=function(a){if(null==a)return this.dur;this.s=this.s*a/this.dur;this.dur=a},n=function(){delete k[this.id];this.update();a("mina.stop."+this.id,this)},u=function(){this.pdif||(delete k[this.id],this.update(),this.pdif=this.get()-this.b)},p=function(){this.pdif&&(this.b=this.get()-this.pdif,delete this.pdif,k[this.id]=this)},b=function(){var a;if(M(this.start)){a=[];
for(var b=0,e=this.start.length;b<e;b++)a[b]=+this.start[b]+(this.end[b]-this.start[b])*this.easing(this.s)}else a=+this.start+(this.end-this.start)*this.easing(this.s);this.set(a)},q=function(){var l=0,b;for(b in k)if(k.hasOwnProperty(b)){var e=k[b],f=e.get();l++;e.s=(f-e.b)/(e.dur/e.spd);1<=e.s&&(delete k[b],e.s=1,l--,function(b){setTimeout(function(){a("mina.finish."+b.id,b)})}(e));e.update()}l&&y(q)},e=function(a,r,s,x,G,h,J){a={id:w+(A++).toString(36),start:a,end:r,b:s,s:0,dur:x-s,spd:1,get:G,
set:h,easing:J||e.linear,status:z,speed:d,duration:f,stop:n,pause:u,resume:p,update:b};k[a.id]=a;r=0;for(var K in k)if(k.hasOwnProperty(K)&&(r++,2==r))break;1==r&&y(q);return a};e.time=Date.now||function(){return+new Date};e.getById=function(a){return k[a]||null};e.linear=function(a){return a};e.easeout=function(a){return Math.pow(a,1.7)};e.easein=function(a){return Math.pow(a,0.48)};e.easeinout=function(a){if(1==a)return 1;if(0==a)return 0;var b=0.48-a/1.04,e=Math.sqrt(0.1734+b*b);a=e-b;a=Math.pow(Math.abs(a),
1/3)*(0>a?-1:1);b=-e-b;b=Math.pow(Math.abs(b),1/3)*(0>b?-1:1);a=a+b+0.5;return 3*(1-a)*a*a+a*a*a};e.backin=function(a){return 1==a?1:a*a*(2.70158*a-1.70158)};e.backout=function(a){if(0==a)return 0;a-=1;return a*a*(2.70158*a+1.70158)+1};e.elastic=function(a){return a==!!a?a:Math.pow(2,-10*a)*Math.sin(2*(a-0.075)*Math.PI/0.3)+1};e.bounce=function(a){a<1/2.75?a*=7.5625*a:a<2/2.75?(a-=1.5/2.75,a=7.5625*a*a+0.75):a<2.5/2.75?(a-=2.25/2.75,a=7.5625*a*a+0.9375):(a-=2.625/2.75,a=7.5625*a*a+0.984375);return a};
return N.mina=e}("undefined"==typeof k?function(){}:k),C=function(){function a(c,t){if(c){if(c.tagName)return x(c);if(y(c,"array")&&a.set)return a.set.apply(a,c);if(c instanceof e)return c;if(null==t)return c=G.doc.querySelector(c),x(c)}return new s(null==c?"100%":c,null==t?"100%":t)}function v(c,a){if(a){"#text"==c&&(c=G.doc.createTextNode(a.text||""));"string"==typeof c&&(c=v(c));if("string"==typeof a)return"xlink:"==a.substring(0,6)?c.getAttributeNS(m,a.substring(6)):"xml:"==a.substring(0,4)?c.getAttributeNS(la,
a.substring(4)):c.getAttribute(a);for(var da in a)if(a[h](da)){var b=J(a[da]);b?"xlink:"==da.substring(0,6)?c.setAttributeNS(m,da.substring(6),b):"xml:"==da.substring(0,4)?c.setAttributeNS(la,da.substring(4),b):c.setAttribute(da,b):c.removeAttribute(da)}}else c=G.doc.createElementNS(la,c);return c}function y(c,a){a=J.prototype.toLowerCase.call(a);return"finite"==a?isFinite(c):"array"==a&&(c instanceof Array||Array.isArray&&Array.isArray(c))?!0:"null"==a&&null===c||a==typeof c&&null!==c||"object"==
a&&c===Object(c)||$.call(c).slice(8,-1).toLowerCase()==a}function M(c){if("function"==typeof c||Object(c)!==c)return c;var a=new c.constructor,b;for(b in c)c[h](b)&&(a[b]=M(c[b]));return a}function A(c,a,b){function m(){var e=Array.prototype.slice.call(arguments,0),f=e.join("\u2400"),d=m.cache=m.cache||{},l=m.count=m.count||[];if(d[h](f)){a:for(var e=l,l=f,B=0,H=e.length;B<H;B++)if(e[B]===l){e.push(e.splice(B,1)[0]);break a}return b?b(d[f]):d[f]}1E3<=l.length&&delete d[l.shift()];l.push(f);d[f]=c.apply(a,
e);return b?b(d[f]):d[f]}return m}function w(c,a,b,m,e,f){return null==e?(c-=b,a-=m,c||a?(180*I.atan2(-a,-c)/C+540)%360:0):w(c,a,e,f)-w(b,m,e,f)}function z(c){return c%360*C/180}function d(c){var a=[];c=c.replace(/(?:^|\s)(\w+)\(([^)]+)\)/g,function(c,b,m){m=m.split(/\s*,\s*|\s+/);"rotate"==b&&1==m.length&&m.push(0,0);"scale"==b&&(2<m.length?m=m.slice(0,2):2==m.length&&m.push(0,0),1==m.length&&m.push(m[0],0,0));"skewX"==b?a.push(["m",1,0,I.tan(z(m[0])),1,0,0]):"skewY"==b?a.push(["m",1,I.tan(z(m[0])),
0,1,0,0]):a.push([b.charAt(0)].concat(m));return c});return a}function f(c,t){var b=O(c),m=new a.Matrix;if(b)for(var e=0,f=b.length;e<f;e++){var h=b[e],d=h.length,B=J(h[0]).toLowerCase(),H=h[0]!=B,l=H?m.invert():0,E;"t"==B&&2==d?m.translate(h[1],0):"t"==B&&3==d?H?(d=l.x(0,0),B=l.y(0,0),H=l.x(h[1],h[2]),l=l.y(h[1],h[2]),m.translate(H-d,l-B)):m.translate(h[1],h[2]):"r"==B?2==d?(E=E||t,m.rotate(h[1],E.x+E.width/2,E.y+E.height/2)):4==d&&(H?(H=l.x(h[2],h[3]),l=l.y(h[2],h[3]),m.rotate(h[1],H,l)):m.rotate(h[1],
h[2],h[3])):"s"==B?2==d||3==d?(E=E||t,m.scale(h[1],h[d-1],E.x+E.width/2,E.y+E.height/2)):4==d?H?(H=l.x(h[2],h[3]),l=l.y(h[2],h[3]),m.scale(h[1],h[1],H,l)):m.scale(h[1],h[1],h[2],h[3]):5==d&&(H?(H=l.x(h[3],h[4]),l=l.y(h[3],h[4]),m.scale(h[1],h[2],H,l)):m.scale(h[1],h[2],h[3],h[4])):"m"==B&&7==d&&m.add(h[1],h[2],h[3],h[4],h[5],h[6])}return m}function n(c,t){if(null==t){var m=!0;t="linearGradient"==c.type||"radialGradient"==c.type?c.node.getAttribute("gradientTransform"):"pattern"==c.type?c.node.getAttribute("patternTransform"):
c.node.getAttribute("transform");if(!t)return new a.Matrix;t=d(t)}else t=a._.rgTransform.test(t)?J(t).replace(/\.{3}|\u2026/g,c._.transform||aa):d(t),y(t,"array")&&(t=a.path?a.path.toString.call(t):J(t)),c._.transform=t;var b=f(t,c.getBBox(1));if(m)return b;c.matrix=b}function u(c){c=c.node.ownerSVGElement&&x(c.node.ownerSVGElement)||c.node.parentNode&&x(c.node.parentNode)||a.select("svg")||a(0,0);var t=c.select("defs"),t=null==t?!1:t.node;t||(t=r("defs",c.node).node);return t}function p(c){return c.node.ownerSVGElement&&
x(c.node.ownerSVGElement)||a.select("svg")}function b(c,a,m){function b(c){if(null==c)return aa;if(c==+c)return c;v(B,{width:c});try{return B.getBBox().width}catch(a){return 0}}function h(c){if(null==c)return aa;if(c==+c)return c;v(B,{height:c});try{return B.getBBox().height}catch(a){return 0}}function e(b,B){null==a?d[b]=B(c.attr(b)||0):b==a&&(d=B(null==m?c.attr(b)||0:m))}var f=p(c).node,d={},B=f.querySelector(".svg---mgr");B||(B=v("rect"),v(B,{x:-9E9,y:-9E9,width:10,height:10,"class":"svg---mgr",
fill:"none"}),f.appendChild(B));switch(c.type){case "rect":e("rx",b),e("ry",h);case "image":e("width",b),e("height",h);case "text":e("x",b);e("y",h);break;case "circle":e("cx",b);e("cy",h);e("r",b);break;case "ellipse":e("cx",b);e("cy",h);e("rx",b);e("ry",h);break;case "line":e("x1",b);e("x2",b);e("y1",h);e("y2",h);break;case "marker":e("refX",b);e("markerWidth",b);e("refY",h);e("markerHeight",h);break;case "radialGradient":e("fx",b);e("fy",h);break;case "tspan":e("dx",b);e("dy",h);break;default:e(a,
b)}f.removeChild(B);return d}function q(c){y(c,"array")||(c=Array.prototype.slice.call(arguments,0));for(var a=0,b=0,m=this.node;this[a];)delete this[a++];for(a=0;a<c.length;a++)"set"==c[a].type?c[a].forEach(function(c){m.appendChild(c.node)}):m.appendChild(c[a].node);for(var h=m.childNodes,a=0;a<h.length;a++)this[b++]=x(h[a]);return this}function e(c){if(c.snap in E)return E[c.snap];var a=this.id=V(),b;try{b=c.ownerSVGElement}catch(m){}this.node=c;b&&(this.paper=new s(b));this.type=c.tagName;this.anims=
{};this._={transform:[]};c.snap=a;E[a]=this;"g"==this.type&&(this.add=q);if(this.type in{g:1,mask:1,pattern:1})for(var e in s.prototype)s.prototype[h](e)&&(this[e]=s.prototype[e])}function l(c){this.node=c}function r(c,a){var b=v(c);a.appendChild(b);return x(b)}function s(c,a){var b,m,f,d=s.prototype;if(c&&"svg"==c.tagName){if(c.snap in E)return E[c.snap];var l=c.ownerDocument;b=new e(c);m=c.getElementsByTagName("desc")[0];f=c.getElementsByTagName("defs")[0];m||(m=v("desc"),m.appendChild(l.createTextNode("Created with Snap")),
b.node.appendChild(m));f||(f=v("defs"),b.node.appendChild(f));b.defs=f;for(var ca in d)d[h](ca)&&(b[ca]=d[ca]);b.paper=b.root=b}else b=r("svg",G.doc.body),v(b.node,{height:a,version:1.1,width:c,xmlns:la});return b}function x(c){return!c||c instanceof e||c instanceof l?c:c.tagName&&"svg"==c.tagName.toLowerCase()?new s(c):c.tagName&&"object"==c.tagName.toLowerCase()&&"image/svg+xml"==c.type?new s(c.contentDocument.getElementsByTagName("svg")[0]):new e(c)}a.version="0.3.0";a.toString=function(){return"Snap v"+
this.version};a._={};var G={win:N,doc:N.document};a._.glob=G;var h="hasOwnProperty",J=String,K=parseFloat,U=parseInt,I=Math,P=I.max,Q=I.min,Y=I.abs,C=I.PI,aa="",$=Object.prototype.toString,F=/^\s*((#[a-f\d]{6})|(#[a-f\d]{3})|rgba?\(\s*([\d\.]+%?\s*,\s*[\d\.]+%?\s*,\s*[\d\.]+%?(?:\s*,\s*[\d\.]+%?)?)\s*\)|hsba?\(\s*([\d\.]+(?:deg|\xb0|%)?\s*,\s*[\d\.]+%?\s*,\s*[\d\.]+(?:%?\s*,\s*[\d\.]+)?%?)\s*\)|hsla?\(\s*([\d\.]+(?:deg|\xb0|%)?\s*,\s*[\d\.]+%?\s*,\s*[\d\.]+(?:%?\s*,\s*[\d\.]+)?%?)\s*\))\s*$/i;a._.separator=
RegExp("[,\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]+");var S=RegExp("[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*"),X={hs:1,rg:1},W=RegExp("([a-z])[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029,]*((-?\\d*\\.?\\d*(?:e[\\-+]?\\d+)?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*)+)",
"ig"),ma=RegExp("([rstm])[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029,]*((-?\\d*\\.?\\d*(?:e[\\-+]?\\d+)?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*)+)","ig"),Z=RegExp("(-?\\d*\\.?\\d*(?:e[\\-+]?\\d+)?)[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*",
"ig"),na=0,ba="S"+(+new Date).toString(36),V=function(){return ba+(na++).toString(36)},m="http://www.w3.org/1999/xlink",la="http://www.w3.org/2000/svg",E={},ca=a.url=function(c){return"url('#"+c+"')"};a._.$=v;a._.id=V;a.format=function(){var c=/\{([^\}]+)\}/g,a=/(?:(?:^|\.)(.+?)(?=\[|\.|$|\()|\[('|")(.+?)\2\])(\(\))?/g,b=function(c,b,m){var h=m;b.replace(a,function(c,a,b,m,t){a=a||m;h&&(a in h&&(h=h[a]),"function"==typeof h&&t&&(h=h()))});return h=(null==h||h==m?c:h)+""};return function(a,m){return J(a).replace(c,
function(c,a){return b(c,a,m)})}}();a._.clone=M;a._.cacher=A;a.rad=z;a.deg=function(c){return 180*c/C%360};a.angle=w;a.is=y;a.snapTo=function(c,a,b){b=y(b,"finite")?b:10;if(y(c,"array"))for(var m=c.length;m--;){if(Y(c[m]-a)<=b)return c[m]}else{c=+c;m=a%c;if(m<b)return a-m;if(m>c-b)return a-m+c}return a};a.getRGB=A(function(c){if(!c||(c=J(c)).indexOf("-")+1)return{r:-1,g:-1,b:-1,hex:"none",error:1,toString:ka};if("none"==c)return{r:-1,g:-1,b:-1,hex:"none",toString:ka};!X[h](c.toLowerCase().substring(0,
2))&&"#"!=c.charAt()&&(c=T(c));if(!c)return{r:-1,g:-1,b:-1,hex:"none",error:1,toString:ka};var b,m,e,f,d;if(c=c.match(F)){c[2]&&(e=U(c[2].substring(5),16),m=U(c[2].substring(3,5),16),b=U(c[2].substring(1,3),16));c[3]&&(e=U((d=c[3].charAt(3))+d,16),m=U((d=c[3].charAt(2))+d,16),b=U((d=c[3].charAt(1))+d,16));c[4]&&(d=c[4].split(S),b=K(d[0]),"%"==d[0].slice(-1)&&(b*=2.55),m=K(d[1]),"%"==d[1].slice(-1)&&(m*=2.55),e=K(d[2]),"%"==d[2].slice(-1)&&(e*=2.55),"rgba"==c[1].toLowerCase().slice(0,4)&&(f=K(d[3])),
d[3]&&"%"==d[3].slice(-1)&&(f/=100));if(c[5])return d=c[5].split(S),b=K(d[0]),"%"==d[0].slice(-1)&&(b/=100),m=K(d[1]),"%"==d[1].slice(-1)&&(m/=100),e=K(d[2]),"%"==d[2].slice(-1)&&(e/=100),"deg"!=d[0].slice(-3)&&"\u00b0"!=d[0].slice(-1)||(b/=360),"hsba"==c[1].toLowerCase().slice(0,4)&&(f=K(d[3])),d[3]&&"%"==d[3].slice(-1)&&(f/=100),a.hsb2rgb(b,m,e,f);if(c[6])return d=c[6].split(S),b=K(d[0]),"%"==d[0].slice(-1)&&(b/=100),m=K(d[1]),"%"==d[1].slice(-1)&&(m/=100),e=K(d[2]),"%"==d[2].slice(-1)&&(e/=100),
"deg"!=d[0].slice(-3)&&"\u00b0"!=d[0].slice(-1)||(b/=360),"hsla"==c[1].toLowerCase().slice(0,4)&&(f=K(d[3])),d[3]&&"%"==d[3].slice(-1)&&(f/=100),a.hsl2rgb(b,m,e,f);b=Q(I.round(b),255);m=Q(I.round(m),255);e=Q(I.round(e),255);f=Q(P(f,0),1);c={r:b,g:m,b:e,toString:ka};c.hex="#"+(16777216|e|m<<8|b<<16).toString(16).slice(1);c.opacity=y(f,"finite")?f:1;return c}return{r:-1,g:-1,b:-1,hex:"none",error:1,toString:ka}},a);a.hsb=A(function(c,b,m){return a.hsb2rgb(c,b,m).hex});a.hsl=A(function(c,b,m){return a.hsl2rgb(c,
b,m).hex});a.rgb=A(function(c,a,b,m){if(y(m,"finite")){var e=I.round;return"rgba("+[e(c),e(a),e(b),+m.toFixed(2)]+")"}return"#"+(16777216|b|a<<8|c<<16).toString(16).slice(1)});var T=function(c){var a=G.doc.getElementsByTagName("head")[0]||G.doc.getElementsByTagName("svg")[0];T=A(function(c){if("red"==c.toLowerCase())return"rgb(255, 0, 0)";a.style.color="rgb(255, 0, 0)";a.style.color=c;c=G.doc.defaultView.getComputedStyle(a,aa).getPropertyValue("color");return"rgb(255, 0, 0)"==c?null:c});return T(c)},
qa=function(){return"hsb("+[this.h,this.s,this.b]+")"},ra=function(){return"hsl("+[this.h,this.s,this.l]+")"},ka=function(){return 1==this.opacity||null==this.opacity?this.hex:"rgba("+[this.r,this.g,this.b,this.opacity]+")"},D=function(c,b,m){null==b&&y(c,"object")&&"r"in c&&"g"in c&&"b"in c&&(m=c.b,b=c.g,c=c.r);null==b&&y(c,string)&&(m=a.getRGB(c),c=m.r,b=m.g,m=m.b);if(1<c||1<b||1<m)c/=255,b/=255,m/=255;return[c,b,m]},oa=function(c,b,m,e){c=I.round(255*c);b=I.round(255*b);m=I.round(255*m);c={r:c,
g:b,b:m,opacity:y(e,"finite")?e:1,hex:a.rgb(c,b,m),toString:ka};y(e,"finite")&&(c.opacity=e);return c};a.color=function(c){var b;y(c,"object")&&"h"in c&&"s"in c&&"b"in c?(b=a.hsb2rgb(c),c.r=b.r,c.g=b.g,c.b=b.b,c.opacity=1,c.hex=b.hex):y(c,"object")&&"h"in c&&"s"in c&&"l"in c?(b=a.hsl2rgb(c),c.r=b.r,c.g=b.g,c.b=b.b,c.opacity=1,c.hex=b.hex):(y(c,"string")&&(c=a.getRGB(c)),y(c,"object")&&"r"in c&&"g"in c&&"b"in c&&!("error"in c)?(b=a.rgb2hsl(c),c.h=b.h,c.s=b.s,c.l=b.l,b=a.rgb2hsb(c),c.v=b.b):(c={hex:"none"},
c.r=c.g=c.b=c.h=c.s=c.v=c.l=-1,c.error=1));c.toString=ka;return c};a.hsb2rgb=function(c,a,b,m){y(c,"object")&&"h"in c&&"s"in c&&"b"in c&&(b=c.b,a=c.s,c=c.h,m=c.o);var e,h,d;c=360*c%360/60;d=b*a;a=d*(1-Y(c%2-1));b=e=h=b-d;c=~~c;b+=[d,a,0,0,a,d][c];e+=[a,d,d,a,0,0][c];h+=[0,0,a,d,d,a][c];return oa(b,e,h,m)};a.hsl2rgb=function(c,a,b,m){y(c,"object")&&"h"in c&&"s"in c&&"l"in c&&(b=c.l,a=c.s,c=c.h);if(1<c||1<a||1<b)c/=360,a/=100,b/=100;var e,h,d;c=360*c%360/60;d=2*a*(0.5>b?b:1-b);a=d*(1-Y(c%2-1));b=e=
h=b-d/2;c=~~c;b+=[d,a,0,0,a,d][c];e+=[a,d,d,a,0,0][c];h+=[0,0,a,d,d,a][c];return oa(b,e,h,m)};a.rgb2hsb=function(c,a,b){b=D(c,a,b);c=b[0];a=b[1];b=b[2];var m,e;m=P(c,a,b);e=m-Q(c,a,b);c=((0==e?0:m==c?(a-b)/e:m==a?(b-c)/e+2:(c-a)/e+4)+360)%6*60/360;return{h:c,s:0==e?0:e/m,b:m,toString:qa}};a.rgb2hsl=function(c,a,b){b=D(c,a,b);c=b[0];a=b[1];b=b[2];var m,e,h;m=P(c,a,b);e=Q(c,a,b);h=m-e;c=((0==h?0:m==c?(a-b)/h:m==a?(b-c)/h+2:(c-a)/h+4)+360)%6*60/360;m=(m+e)/2;return{h:c,s:0==h?0:0.5>m?h/(2*m):h/(2-2*
m),l:m,toString:ra}};a.parsePathString=function(c){if(!c)return null;var b=a.path(c);if(b.arr)return a.path.clone(b.arr);var m={a:7,c:6,o:2,h:1,l:2,m:2,r:4,q:4,s:4,t:2,v:1,u:3,z:0},e=[];y(c,"array")&&y(c[0],"array")&&(e=a.path.clone(c));e.length||J(c).replace(W,function(c,a,b){var h=[];c=a.toLowerCase();b.replace(Z,function(c,a){a&&h.push(+a)});"m"==c&&2<h.length&&(e.push([a].concat(h.splice(0,2))),c="l",a="m"==a?"l":"L");"o"==c&&1==h.length&&e.push([a,h[0] ]);if("r"==c)e.push([a].concat(h));else for(;h.length>=
m[c]&&(e.push([a].concat(h.splice(0,m[c]))),m[c]););});e.toString=a.path.toString;b.arr=a.path.clone(e);return e};var O=a.parseTransformString=function(c){if(!c)return null;var b=[];y(c,"array")&&y(c[0],"array")&&(b=a.path.clone(c));b.length||J(c).replace(ma,function(c,a,m){var e=[];a.toLowerCase();m.replace(Z,function(c,a){a&&e.push(+a)});b.push([a].concat(e))});b.toString=a.path.toString;return b};a._.svgTransform2string=d;a._.rgTransform=RegExp("^[a-z][\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*-?\\.?\\d",
"i");a._.transform2matrix=f;a._unit2px=b;a._.getSomeDefs=u;a._.getSomeSVG=p;a.select=function(c){return x(G.doc.querySelector(c))};a.selectAll=function(c){c=G.doc.querySelectorAll(c);for(var b=(a.set||Array)(),m=0;m<c.length;m++)b.push(x(c[m]));return b};setInterval(function(){for(var c in E)if(E[h](c)){var a=E[c],b=a.node;("svg"!=a.type&&!b.ownerSVGElement||"svg"==a.type&&(!b.parentNode||"ownerSVGElement"in b.parentNode&&!b.ownerSVGElement))&&delete E[c]}},1E4);(function(c){function m(c){function a(c,
b){var m=v(c.node,b);(m=(m=m&&m.match(d))&&m[2])&&"#"==m.charAt()&&(m=m.substring(1))&&(f[m]=(f[m]||[]).concat(function(a){var m={};m[b]=ca(a);v(c.node,m)}))}function b(c){var a=v(c.node,"xlink:href");a&&"#"==a.charAt()&&(a=a.substring(1))&&(f[a]=(f[a]||[]).concat(function(a){c.attr("xlink:href","#"+a)}))}var e=c.selectAll("*"),h,d=/^\s*url\(("|'|)(.*)\1\)\s*$/;c=[];for(var f={},l=0,E=e.length;l<E;l++){h=e[l];a(h,"fill");a(h,"stroke");a(h,"filter");a(h,"mask");a(h,"clip-path");b(h);var t=v(h.node,
"id");t&&(v(h.node,{id:h.id}),c.push({old:t,id:h.id}))}l=0;for(E=c.length;l<E;l++)if(e=f[c[l].old])for(h=0,t=e.length;h<t;h++)e[h](c[l].id)}function e(c,a,b){return function(m){m=m.slice(c,a);1==m.length&&(m=m[0]);return b?b(m):m}}function d(c){return function(){var a=c?"<"+this.type:"",b=this.node.attributes,m=this.node.childNodes;if(c)for(var e=0,h=b.length;e<h;e++)a+=" "+b[e].name+'="'+b[e].value.replace(/"/g,'\\"')+'"';if(m.length){c&&(a+=">");e=0;for(h=m.length;e<h;e++)3==m[e].nodeType?a+=m[e].nodeValue:
1==m[e].nodeType&&(a+=x(m[e]).toString());c&&(a+="</"+this.type+">")}else c&&(a+="/>");return a}}c.attr=function(c,a){if(!c)return this;if(y(c,"string"))if(1<arguments.length){var b={};b[c]=a;c=b}else return k("snap.util.getattr."+c,this).firstDefined();for(var m in c)c[h](m)&&k("snap.util.attr."+m,this,c[m]);return this};c.getBBox=function(c){if(!a.Matrix||!a.path)return this.node.getBBox();var b=this,m=new a.Matrix;if(b.removed)return a._.box();for(;"use"==b.type;)if(c||(m=m.add(b.transform().localMatrix.translate(b.attr("x")||
0,b.attr("y")||0))),b.original)b=b.original;else var e=b.attr("xlink:href"),b=b.original=b.node.ownerDocument.getElementById(e.substring(e.indexOf("#")+1));var e=b._,h=a.path.get[b.type]||a.path.get.deflt;try{if(c)return e.bboxwt=h?a.path.getBBox(b.realPath=h(b)):a._.box(b.node.getBBox()),a._.box(e.bboxwt);b.realPath=h(b);b.matrix=b.transform().localMatrix;e.bbox=a.path.getBBox(a.path.map(b.realPath,m.add(b.matrix)));return a._.box(e.bbox)}catch(d){return a._.box()}};var f=function(){return this.string};
c.transform=function(c){var b=this._;if(null==c){var m=this;c=new a.Matrix(this.node.getCTM());for(var e=n(this),h=[e],d=new a.Matrix,l=e.toTransformString(),b=J(e)==J(this.matrix)?J(b.transform):l;"svg"!=m.type&&(m=m.parent());)h.push(n(m));for(m=h.length;m--;)d.add(h[m]);return{string:b,globalMatrix:c,totalMatrix:d,localMatrix:e,diffMatrix:c.clone().add(e.invert()),global:c.toTransformString(),total:d.toTransformString(),local:l,toString:f}}c instanceof a.Matrix?this.matrix=c:n(this,c);this.node&&
("linearGradient"==this.type||"radialGradient"==this.type?v(this.node,{gradientTransform:this.matrix}):"pattern"==this.type?v(this.node,{patternTransform:this.matrix}):v(this.node,{transform:this.matrix}));return this};c.parent=function(){return x(this.node.parentNode)};c.append=c.add=function(c){if(c){if("set"==c.type){var a=this;c.forEach(function(c){a.add(c)});return this}c=x(c);this.node.appendChild(c.node);c.paper=this.paper}return this};c.appendTo=function(c){c&&(c=x(c),c.append(this));return this};
c.prepend=function(c){if(c){if("set"==c.type){var a=this,b;c.forEach(function(c){b?b.after(c):a.prepend(c);b=c});return this}c=x(c);var m=c.parent();this.node.insertBefore(c.node,this.node.firstChild);this.add&&this.add();c.paper=this.paper;this.parent()&&this.parent().add();m&&m.add()}return this};c.prependTo=function(c){c=x(c);c.prepend(this);return this};c.before=function(c){if("set"==c.type){var a=this;c.forEach(function(c){var b=c.parent();a.node.parentNode.insertBefore(c.node,a.node);b&&b.add()});
this.parent().add();return this}c=x(c);var b=c.parent();this.node.parentNode.insertBefore(c.node,this.node);this.parent()&&this.parent().add();b&&b.add();c.paper=this.paper;return this};c.after=function(c){c=x(c);var a=c.parent();this.node.nextSibling?this.node.parentNode.insertBefore(c.node,this.node.nextSibling):this.node.parentNode.appendChild(c.node);this.parent()&&this.parent().add();a&&a.add();c.paper=this.paper;return this};c.insertBefore=function(c){c=x(c);var a=this.parent();c.node.parentNode.insertBefore(this.node,
c.node);this.paper=c.paper;a&&a.add();c.parent()&&c.parent().add();return this};c.insertAfter=function(c){c=x(c);var a=this.parent();c.node.parentNode.insertBefore(this.node,c.node.nextSibling);this.paper=c.paper;a&&a.add();c.parent()&&c.parent().add();return this};c.remove=function(){var c=this.parent();this.node.parentNode&&this.node.parentNode.removeChild(this.node);delete this.paper;this.removed=!0;c&&c.add();return this};c.select=function(c){return x(this.node.querySelector(c))};c.selectAll=
function(c){c=this.node.querySelectorAll(c);for(var b=(a.set||Array)(),m=0;m<c.length;m++)b.push(x(c[m]));return b};c.asPX=function(c,a){null==a&&(a=this.attr(c));return+b(this,c,a)};c.use=function(){var c,a=this.node.id;a||(a=this.id,v(this.node,{id:a}));c="linearGradient"==this.type||"radialGradient"==this.type||"pattern"==this.type?r(this.type,this.node.parentNode):r("use",this.node.parentNode);v(c.node,{"xlink:href":"#"+a});c.original=this;return c};var l=/\S+/g;c.addClass=function(c){var a=(c||
"").match(l)||[];c=this.node;var b=c.className.baseVal,m=b.match(l)||[],e,h,d;if(a.length){for(e=0;d=a[e++];)h=m.indexOf(d),~h||m.push(d);a=m.join(" ");b!=a&&(c.className.baseVal=a)}return this};c.removeClass=function(c){var a=(c||"").match(l)||[];c=this.node;var b=c.className.baseVal,m=b.match(l)||[],e,h;if(m.length){for(e=0;h=a[e++];)h=m.indexOf(h),~h&&m.splice(h,1);a=m.join(" ");b!=a&&(c.className.baseVal=a)}return this};c.hasClass=function(c){return!!~(this.node.className.baseVal.match(l)||[]).indexOf(c)};
c.toggleClass=function(c,a){if(null!=a)return a?this.addClass(c):this.removeClass(c);var b=(c||"").match(l)||[],m=this.node,e=m.className.baseVal,h=e.match(l)||[],d,f,E;for(d=0;E=b[d++];)f=h.indexOf(E),~f?h.splice(f,1):h.push(E);b=h.join(" ");e!=b&&(m.className.baseVal=b);return this};c.clone=function(){var c=x(this.node.cloneNode(!0));v(c.node,"id")&&v(c.node,{id:c.id});m(c);c.insertAfter(this);return c};c.toDefs=function(){u(this).appendChild(this.node);return this};c.pattern=c.toPattern=function(c,
a,b,m){var e=r("pattern",u(this));null==c&&(c=this.getBBox());y(c,"object")&&"x"in c&&(a=c.y,b=c.width,m=c.height,c=c.x);v(e.node,{x:c,y:a,width:b,height:m,patternUnits:"userSpaceOnUse",id:e.id,viewBox:[c,a,b,m].join(" ")});e.node.appendChild(this.node);return e};c.marker=function(c,a,b,m,e,h){var d=r("marker",u(this));null==c&&(c=this.getBBox());y(c,"object")&&"x"in c&&(a=c.y,b=c.width,m=c.height,e=c.refX||c.cx,h=c.refY||c.cy,c=c.x);v(d.node,{viewBox:[c,a,b,m].join(" "),markerWidth:b,markerHeight:m,
orient:"auto",refX:e||0,refY:h||0,id:d.id});d.node.appendChild(this.node);return d};var E=function(c,a,b,m){"function"!=typeof b||b.length||(m=b,b=L.linear);this.attr=c;this.dur=a;b&&(this.easing=b);m&&(this.callback=m)};a._.Animation=E;a.animation=function(c,a,b,m){return new E(c,a,b,m)};c.inAnim=function(){var c=[],a;for(a in this.anims)this.anims[h](a)&&function(a){c.push({anim:new E(a._attrs,a.dur,a.easing,a._callback),mina:a,curStatus:a.status(),status:function(c){return a.status(c)},stop:function(){a.stop()}})}(this.anims[a]);
return c};a.animate=function(c,a,b,m,e,h){"function"!=typeof e||e.length||(h=e,e=L.linear);var d=L.time();c=L(c,a,d,d+m,L.time,b,e);h&&k.once("mina.finish."+c.id,h);return c};c.stop=function(){for(var c=this.inAnim(),a=0,b=c.length;a<b;a++)c[a].stop();return this};c.animate=function(c,a,b,m){"function"!=typeof b||b.length||(m=b,b=L.linear);c instanceof E&&(m=c.callback,b=c.easing,a=b.dur,c=c.attr);var d=[],f=[],l={},t,ca,n,T=this,q;for(q in c)if(c[h](q)){T.equal?(n=T.equal(q,J(c[q])),t=n.from,ca=
n.to,n=n.f):(t=+T.attr(q),ca=+c[q]);var la=y(t,"array")?t.length:1;l[q]=e(d.length,d.length+la,n);d=d.concat(t);f=f.concat(ca)}t=L.time();var p=L(d,f,t,t+a,L.time,function(c){var a={},b;for(b in l)l[h](b)&&(a[b]=l[b](c));T.attr(a)},b);T.anims[p.id]=p;p._attrs=c;p._callback=m;k("snap.animcreated."+T.id,p);k.once("mina.finish."+p.id,function(){delete T.anims[p.id];m&&m.call(T)});k.once("mina.stop."+p.id,function(){delete T.anims[p.id]});return T};var T={};c.data=function(c,b){var m=T[this.id]=T[this.id]||
{};if(0==arguments.length)return k("snap.data.get."+this.id,this,m,null),m;if(1==arguments.length){if(a.is(c,"object")){for(var e in c)c[h](e)&&this.data(e,c[e]);return this}k("snap.data.get."+this.id,this,m[c],c);return m[c]}m[c]=b;k("snap.data.set."+this.id,this,b,c);return this};c.removeData=function(c){null==c?T[this.id]={}:T[this.id]&&delete T[this.id][c];return this};c.outerSVG=c.toString=d(1);c.innerSVG=d()})(e.prototype);a.parse=function(c){var a=G.doc.createDocumentFragment(),b=!0,m=G.doc.createElement("div");
c=J(c);c.match(/^\s*<\s*svg(?:\s|>)/)||(c="<svg>"+c+"</svg>",b=!1);m.innerHTML=c;if(c=m.getElementsByTagName("svg")[0])if(b)a=c;else for(;c.firstChild;)a.appendChild(c.firstChild);m.innerHTML=aa;return new l(a)};l.prototype.select=e.prototype.select;l.prototype.selectAll=e.prototype.selectAll;a.fragment=function(){for(var c=Array.prototype.slice.call(arguments,0),b=G.doc.createDocumentFragment(),m=0,e=c.length;m<e;m++){var h=c[m];h.node&&h.node.nodeType&&b.appendChild(h.node);h.nodeType&&b.appendChild(h);
"string"==typeof h&&b.appendChild(a.parse(h).node)}return new l(b)};a._.make=r;a._.wrap=x;s.prototype.el=function(c,a){var b=r(c,this.node);a&&b.attr(a);return b};k.on("snap.util.getattr",function(){var c=k.nt(),c=c.substring(c.lastIndexOf(".")+1),a=c.replace(/[A-Z]/g,function(c){return"-"+c.toLowerCase()});return pa[h](a)?this.node.ownerDocument.defaultView.getComputedStyle(this.node,null).getPropertyValue(a):v(this.node,c)});var pa={"alignment-baseline":0,"baseline-shift":0,clip:0,"clip-path":0,
"clip-rule":0,color:0,"color-interpolation":0,"color-interpolation-filters":0,"color-profile":0,"color-rendering":0,cursor:0,direction:0,display:0,"dominant-baseline":0,"enable-background":0,fill:0,"fill-opacity":0,"fill-rule":0,filter:0,"flood-color":0,"flood-opacity":0,font:0,"font-family":0,"font-size":0,"font-size-adjust":0,"font-stretch":0,"font-style":0,"font-variant":0,"font-weight":0,"glyph-orientation-horizontal":0,"glyph-orientation-vertical":0,"image-rendering":0,kerning:0,"letter-spacing":0,
"lighting-color":0,marker:0,"marker-end":0,"marker-mid":0,"marker-start":0,mask:0,opacity:0,overflow:0,"pointer-events":0,"shape-rendering":0,"stop-color":0,"stop-opacity":0,stroke:0,"stroke-dasharray":0,"stroke-dashoffset":0,"stroke-linecap":0,"stroke-linejoin":0,"stroke-miterlimit":0,"stroke-opacity":0,"stroke-width":0,"text-anchor":0,"text-decoration":0,"text-rendering":0,"unicode-bidi":0,visibility:0,"word-spacing":0,"writing-mode":0};k.on("snap.util.attr",function(c){var a=k.nt(),b={},a=a.substring(a.lastIndexOf(".")+
1);b[a]=c;var m=a.replace(/-(\w)/gi,function(c,a){return a.toUpperCase()}),a=a.replace(/[A-Z]/g,function(c){return"-"+c.toLowerCase()});pa[h](a)?this.node.style[m]=null==c?aa:c:v(this.node,b)});a.ajax=function(c,a,b,m){var e=new XMLHttpRequest,h=V();if(e){if(y(a,"function"))m=b,b=a,a=null;else if(y(a,"object")){var d=[],f;for(f in a)a.hasOwnProperty(f)&&d.push(encodeURIComponent(f)+"="+encodeURIComponent(a[f]));a=d.join("&")}e.open(a?"POST":"GET",c,!0);a&&(e.setRequestHeader("X-Requested-With","XMLHttpRequest"),
e.setRequestHeader("Content-type","application/x-www-form-urlencoded"));b&&(k.once("snap.ajax."+h+".0",b),k.once("snap.ajax."+h+".200",b),k.once("snap.ajax."+h+".304",b));e.onreadystatechange=function(){4==e.readyState&&k("snap.ajax."+h+"."+e.status,m,e)};if(4==e.readyState)return e;e.send(a);return e}};a.load=function(c,b,m){a.ajax(c,function(c){c=a.parse(c.responseText);m?b.call(m,c):b(c)})};a.getElementByPoint=function(c,a){var b,m,e=G.doc.elementFromPoint(c,a);if(G.win.opera&&"svg"==e.tagName){b=
e;m=b.getBoundingClientRect();b=b.ownerDocument;var h=b.body,d=b.documentElement;b=m.top+(g.win.pageYOffset||d.scrollTop||h.scrollTop)-(d.clientTop||h.clientTop||0);m=m.left+(g.win.pageXOffset||d.scrollLeft||h.scrollLeft)-(d.clientLeft||h.clientLeft||0);h=e.createSVGRect();h.x=c-m;h.y=a-b;h.width=h.height=1;b=e.getIntersectionList(h,null);b.length&&(e=b[b.length-1])}return e?x(e):null};a.plugin=function(c){c(a,e,s,G,l)};return G.win.Snap=a}();C.plugin(function(a,k,y,M,A){function w(a,d,f,b,q,e){null==
d&&"[object SVGMatrix]"==z.call(a)?(this.a=a.a,this.b=a.b,this.c=a.c,this.d=a.d,this.e=a.e,this.f=a.f):null!=a?(this.a=+a,this.b=+d,this.c=+f,this.d=+b,this.e=+q,this.f=+e):(this.a=1,this.c=this.b=0,this.d=1,this.f=this.e=0)}var z=Object.prototype.toString,d=String,f=Math;(function(n){function k(a){return a[0]*a[0]+a[1]*a[1]}function p(a){var d=f.sqrt(k(a));a[0]&&(a[0]/=d);a[1]&&(a[1]/=d)}n.add=function(a,d,e,f,n,p){var k=[[],[],[] ],u=[[this.a,this.c,this.e],[this.b,this.d,this.f],[0,0,1] ];d=[[a,
e,n],[d,f,p],[0,0,1] ];a&&a instanceof w&&(d=[[a.a,a.c,a.e],[a.b,a.d,a.f],[0,0,1] ]);for(a=0;3>a;a++)for(e=0;3>e;e++){for(f=n=0;3>f;f++)n+=u[a][f]*d[f][e];k[a][e]=n}this.a=k[0][0];this.b=k[1][0];this.c=k[0][1];this.d=k[1][1];this.e=k[0][2];this.f=k[1][2];return this};n.invert=function(){var a=this.a*this.d-this.b*this.c;return new w(this.d/a,-this.b/a,-this.c/a,this.a/a,(this.c*this.f-this.d*this.e)/a,(this.b*this.e-this.a*this.f)/a)};n.clone=function(){return new w(this.a,this.b,this.c,this.d,this.e,
this.f)};n.translate=function(a,d){return this.add(1,0,0,1,a,d)};n.scale=function(a,d,e,f){null==d&&(d=a);(e||f)&&this.add(1,0,0,1,e,f);this.add(a,0,0,d,0,0);(e||f)&&this.add(1,0,0,1,-e,-f);return this};n.rotate=function(b,d,e){b=a.rad(b);d=d||0;e=e||0;var l=+f.cos(b).toFixed(9);b=+f.sin(b).toFixed(9);this.add(l,b,-b,l,d,e);return this.add(1,0,0,1,-d,-e)};n.x=function(a,d){return a*this.a+d*this.c+this.e};n.y=function(a,d){return a*this.b+d*this.d+this.f};n.get=function(a){return+this[d.fromCharCode(97+
a)].toFixed(4)};n.toString=function(){return"matrix("+[this.get(0),this.get(1),this.get(2),this.get(3),this.get(4),this.get(5)].join()+")"};n.offset=function(){return[this.e.toFixed(4),this.f.toFixed(4)]};n.determinant=function(){return this.a*this.d-this.b*this.c};n.split=function(){var b={};b.dx=this.e;b.dy=this.f;var d=[[this.a,this.c],[this.b,this.d] ];b.scalex=f.sqrt(k(d[0]));p(d[0]);b.shear=d[0][0]*d[1][0]+d[0][1]*d[1][1];d[1]=[d[1][0]-d[0][0]*b.shear,d[1][1]-d[0][1]*b.shear];b.scaley=f.sqrt(k(d[1]));
p(d[1]);b.shear/=b.scaley;0>this.determinant()&&(b.scalex=-b.scalex);var e=-d[0][1],d=d[1][1];0>d?(b.rotate=a.deg(f.acos(d)),0>e&&(b.rotate=360-b.rotate)):b.rotate=a.deg(f.asin(e));b.isSimple=!+b.shear.toFixed(9)&&(b.scalex.toFixed(9)==b.scaley.toFixed(9)||!b.rotate);b.isSuperSimple=!+b.shear.toFixed(9)&&b.scalex.toFixed(9)==b.scaley.toFixed(9)&&!b.rotate;b.noRotation=!+b.shear.toFixed(9)&&!b.rotate;return b};n.toTransformString=function(a){a=a||this.split();if(+a.shear.toFixed(9))return"m"+[this.get(0),
this.get(1),this.get(2),this.get(3),this.get(4),this.get(5)];a.scalex=+a.scalex.toFixed(4);a.scaley=+a.scaley.toFixed(4);a.rotate=+a.rotate.toFixed(4);return(a.dx||a.dy?"t"+[+a.dx.toFixed(4),+a.dy.toFixed(4)]:"")+(1!=a.scalex||1!=a.scaley?"s"+[a.scalex,a.scaley,0,0]:"")+(a.rotate?"r"+[+a.rotate.toFixed(4),0,0]:"")}})(w.prototype);a.Matrix=w;a.matrix=function(a,d,f,b,k,e){return new w(a,d,f,b,k,e)}});C.plugin(function(a,v,y,M,A){function w(h){return function(d){k.stop();d instanceof A&&1==d.node.childNodes.length&&
("radialGradient"==d.node.firstChild.tagName||"linearGradient"==d.node.firstChild.tagName||"pattern"==d.node.firstChild.tagName)&&(d=d.node.firstChild,b(this).appendChild(d),d=u(d));if(d instanceof v)if("radialGradient"==d.type||"linearGradient"==d.type||"pattern"==d.type){d.node.id||e(d.node,{id:d.id});var f=l(d.node.id)}else f=d.attr(h);else f=a.color(d),f.error?(f=a(b(this).ownerSVGElement).gradient(d))?(f.node.id||e(f.node,{id:f.id}),f=l(f.node.id)):f=d:f=r(f);d={};d[h]=f;e(this.node,d);this.node.style[h]=
x}}function z(a){k.stop();a==+a&&(a+="px");this.node.style.fontSize=a}function d(a){var b=[];a=a.childNodes;for(var e=0,f=a.length;e<f;e++){var l=a[e];3==l.nodeType&&b.push(l.nodeValue);"tspan"==l.tagName&&(1==l.childNodes.length&&3==l.firstChild.nodeType?b.push(l.firstChild.nodeValue):b.push(d(l)))}return b}function f(){k.stop();return this.node.style.fontSize}var n=a._.make,u=a._.wrap,p=a.is,b=a._.getSomeDefs,q=/^url\(#?([^)]+)\)$/,e=a._.$,l=a.url,r=String,s=a._.separator,x="";k.on("snap.util.attr.mask",
function(a){if(a instanceof v||a instanceof A){k.stop();a instanceof A&&1==a.node.childNodes.length&&(a=a.node.firstChild,b(this).appendChild(a),a=u(a));if("mask"==a.type)var d=a;else d=n("mask",b(this)),d.node.appendChild(a.node);!d.node.id&&e(d.node,{id:d.id});e(this.node,{mask:l(d.id)})}});(function(a){k.on("snap.util.attr.clip",a);k.on("snap.util.attr.clip-path",a);k.on("snap.util.attr.clipPath",a)})(function(a){if(a instanceof v||a instanceof A){k.stop();if("clipPath"==a.type)var d=a;else d=
n("clipPath",b(this)),d.node.appendChild(a.node),!d.node.id&&e(d.node,{id:d.id});e(this.node,{"clip-path":l(d.id)})}});k.on("snap.util.attr.fill",w("fill"));k.on("snap.util.attr.stroke",w("stroke"));var G=/^([lr])(?:\(([^)]*)\))?(.*)$/i;k.on("snap.util.grad.parse",function(a){a=r(a);var b=a.match(G);if(!b)return null;a=b[1];var e=b[2],b=b[3],e=e.split(/\s*,\s*/).map(function(a){return+a==a?+a:a});1==e.length&&0==e[0]&&(e=[]);b=b.split("-");b=b.map(function(a){a=a.split(":");var b={color:a[0]};a[1]&&
(b.offset=parseFloat(a[1]));return b});return{type:a,params:e,stops:b}});k.on("snap.util.attr.d",function(b){k.stop();p(b,"array")&&p(b[0],"array")&&(b=a.path.toString.call(b));b=r(b);b.match(/[ruo]/i)&&(b=a.path.toAbsolute(b));e(this.node,{d:b})})(-1);k.on("snap.util.attr.#text",function(a){k.stop();a=r(a);for(a=M.doc.createTextNode(a);this.node.firstChild;)this.node.removeChild(this.node.firstChild);this.node.appendChild(a)})(-1);k.on("snap.util.attr.path",function(a){k.stop();this.attr({d:a})})(-1);
k.on("snap.util.attr.class",function(a){k.stop();this.node.className.baseVal=a})(-1);k.on("snap.util.attr.viewBox",function(a){a=p(a,"object")&&"x"in a?[a.x,a.y,a.width,a.height].join(" "):p(a,"array")?a.join(" "):a;e(this.node,{viewBox:a});k.stop()})(-1);k.on("snap.util.attr.transform",function(a){this.transform(a);k.stop()})(-1);k.on("snap.util.attr.r",function(a){"rect"==this.type&&(k.stop(),e(this.node,{rx:a,ry:a}))})(-1);k.on("snap.util.attr.textpath",function(a){k.stop();if("text"==this.type){var d,
f;if(!a&&this.textPath){for(a=this.textPath;a.node.firstChild;)this.node.appendChild(a.node.firstChild);a.remove();delete this.textPath}else if(p(a,"string")?(d=b(this),a=u(d.parentNode).path(a),d.appendChild(a.node),d=a.id,a.attr({id:d})):(a=u(a),a instanceof v&&(d=a.attr("id"),d||(d=a.id,a.attr({id:d})))),d)if(a=this.textPath,f=this.node,a)a.attr({"xlink:href":"#"+d});else{for(a=e("textPath",{"xlink:href":"#"+d});f.firstChild;)a.appendChild(f.firstChild);f.appendChild(a);this.textPath=u(a)}}})(-1);
k.on("snap.util.attr.text",function(a){if("text"==this.type){for(var b=this.node,d=function(a){var b=e("tspan");if(p(a,"array"))for(var f=0;f<a.length;f++)b.appendChild(d(a[f]));else b.appendChild(M.doc.createTextNode(a));b.normalize&&b.normalize();return b};b.firstChild;)b.removeChild(b.firstChild);for(a=d(a);a.firstChild;)b.appendChild(a.firstChild)}k.stop()})(-1);k.on("snap.util.attr.fontSize",z)(-1);k.on("snap.util.attr.font-size",z)(-1);k.on("snap.util.getattr.transform",function(){k.stop();
return this.transform()})(-1);k.on("snap.util.getattr.textpath",function(){k.stop();return this.textPath})(-1);(function(){function b(d){return function(){k.stop();var b=M.doc.defaultView.getComputedStyle(this.node,null).getPropertyValue("marker-"+d);return"none"==b?b:a(M.doc.getElementById(b.match(q)[1]))}}function d(a){return function(b){k.stop();var d="marker"+a.charAt(0).toUpperCase()+a.substring(1);if(""==b||!b)this.node.style[d]="none";else if("marker"==b.type){var f=b.node.id;f||e(b.node,{id:b.id});
this.node.style[d]=l(f)}}}k.on("snap.util.getattr.marker-end",b("end"))(-1);k.on("snap.util.getattr.markerEnd",b("end"))(-1);k.on("snap.util.getattr.marker-start",b("start"))(-1);k.on("snap.util.getattr.markerStart",b("start"))(-1);k.on("snap.util.getattr.marker-mid",b("mid"))(-1);k.on("snap.util.getattr.markerMid",b("mid"))(-1);k.on("snap.util.attr.marker-end",d("end"))(-1);k.on("snap.util.attr.markerEnd",d("end"))(-1);k.on("snap.util.attr.marker-start",d("start"))(-1);k.on("snap.util.attr.markerStart",
d("start"))(-1);k.on("snap.util.attr.marker-mid",d("mid"))(-1);k.on("snap.util.attr.markerMid",d("mid"))(-1)})();k.on("snap.util.getattr.r",function(){if("rect"==this.type&&e(this.node,"rx")==e(this.node,"ry"))return k.stop(),e(this.node,"rx")})(-1);k.on("snap.util.getattr.text",function(){if("text"==this.type||"tspan"==this.type){k.stop();var a=d(this.node);return 1==a.length?a[0]:a}})(-1);k.on("snap.util.getattr.#text",function(){return this.node.textContent})(-1);k.on("snap.util.getattr.viewBox",
function(){k.stop();var b=e(this.node,"viewBox");if(b)return b=b.split(s),a._.box(+b[0],+b[1],+b[2],+b[3])})(-1);k.on("snap.util.getattr.points",function(){var a=e(this.node,"points");k.stop();if(a)return a.split(s)})(-1);k.on("snap.util.getattr.path",function(){var a=e(this.node,"d");k.stop();return a})(-1);k.on("snap.util.getattr.class",function(){return this.node.className.baseVal})(-1);k.on("snap.util.getattr.fontSize",f)(-1);k.on("snap.util.getattr.font-size",f)(-1)});C.plugin(function(a,v,y,
M,A){function w(a){return a}function z(a){return function(b){return+b.toFixed(3)+a}}var d={"+":function(a,b){return a+b},"-":function(a,b){return a-b},"/":function(a,b){return a/b},"*":function(a,b){return a*b}},f=String,n=/[a-z]+$/i,u=/^\s*([+\-\/*])\s*=\s*([\d.eE+\-]+)\s*([^\d\s]+)?\s*$/;k.on("snap.util.attr",function(a){if(a=f(a).match(u)){var b=k.nt(),b=b.substring(b.lastIndexOf(".")+1),q=this.attr(b),e={};k.stop();var l=a[3]||"",r=q.match(n),s=d[a[1] ];r&&r==l?a=s(parseFloat(q),+a[2]):(q=this.asPX(b),
a=s(this.asPX(b),this.asPX(b,a[2]+l)));isNaN(q)||isNaN(a)||(e[b]=a,this.attr(e))}})(-10);k.on("snap.util.equal",function(a,b){var q=f(this.attr(a)||""),e=f(b).match(u);if(e){k.stop();var l=e[3]||"",r=q.match(n),s=d[e[1] ];if(r&&r==l)return{from:parseFloat(q),to:s(parseFloat(q),+e[2]),f:z(r)};q=this.asPX(a);return{from:q,to:s(q,this.asPX(a,e[2]+l)),f:w}}})(-10)});C.plugin(function(a,v,y,M,A){var w=y.prototype,z=a.is;w.rect=function(a,d,k,p,b,q){var e;null==q&&(q=b);z(a,"object")&&"[object Object]"==
a?e=a:null!=a&&(e={x:a,y:d,width:k,height:p},null!=b&&(e.rx=b,e.ry=q));return this.el("rect",e)};w.circle=function(a,d,k){var p;z(a,"object")&&"[object Object]"==a?p=a:null!=a&&(p={cx:a,cy:d,r:k});return this.el("circle",p)};var d=function(){function a(){this.parentNode.removeChild(this)}return function(d,k){var p=M.doc.createElement("img"),b=M.doc.body;p.style.cssText="position:absolute;left:-9999em;top:-9999em";p.onload=function(){k.call(p);p.onload=p.onerror=null;b.removeChild(p)};p.onerror=a;
b.appendChild(p);p.src=d}}();w.image=function(f,n,k,p,b){var q=this.el("image");if(z(f,"object")&&"src"in f)q.attr(f);else if(null!=f){var e={"xlink:href":f,preserveAspectRatio:"none"};null!=n&&null!=k&&(e.x=n,e.y=k);null!=p&&null!=b?(e.width=p,e.height=b):d(f,function(){a._.$(q.node,{width:this.offsetWidth,height:this.offsetHeight})});a._.$(q.node,e)}return q};w.ellipse=function(a,d,k,p){var b;z(a,"object")&&"[object Object]"==a?b=a:null!=a&&(b={cx:a,cy:d,rx:k,ry:p});return this.el("ellipse",b)};
w.path=function(a){var d;z(a,"object")&&!z(a,"array")?d=a:a&&(d={d:a});return this.el("path",d)};w.group=w.g=function(a){var d=this.el("g");1==arguments.length&&a&&!a.type?d.attr(a):arguments.length&&d.add(Array.prototype.slice.call(arguments,0));return d};w.svg=function(a,d,k,p,b,q,e,l){var r={};z(a,"object")&&null==d?r=a:(null!=a&&(r.x=a),null!=d&&(r.y=d),null!=k&&(r.width=k),null!=p&&(r.height=p),null!=b&&null!=q&&null!=e&&null!=l&&(r.viewBox=[b,q,e,l]));return this.el("svg",r)};w.mask=function(a){var d=
this.el("mask");1==arguments.length&&a&&!a.type?d.attr(a):arguments.length&&d.add(Array.prototype.slice.call(arguments,0));return d};w.ptrn=function(a,d,k,p,b,q,e,l){if(z(a,"object"))var r=a;else arguments.length?(r={},null!=a&&(r.x=a),null!=d&&(r.y=d),null!=k&&(r.width=k),null!=p&&(r.height=p),null!=b&&null!=q&&null!=e&&null!=l&&(r.viewBox=[b,q,e,l])):r={patternUnits:"userSpaceOnUse"};return this.el("pattern",r)};w.use=function(a){return null!=a?(make("use",this.node),a instanceof v&&(a.attr("id")||
a.attr({id:ID()}),a=a.attr("id")),this.el("use",{"xlink:href":a})):v.prototype.use.call(this)};w.text=function(a,d,k){var p={};z(a,"object")?p=a:null!=a&&(p={x:a,y:d,text:k||""});return this.el("text",p)};w.line=function(a,d,k,p){var b={};z(a,"object")?b=a:null!=a&&(b={x1:a,x2:k,y1:d,y2:p});return this.el("line",b)};w.polyline=function(a){1<arguments.length&&(a=Array.prototype.slice.call(arguments,0));var d={};z(a,"object")&&!z(a,"array")?d=a:null!=a&&(d={points:a});return this.el("polyline",d)};
w.polygon=function(a){1<arguments.length&&(a=Array.prototype.slice.call(arguments,0));var d={};z(a,"object")&&!z(a,"array")?d=a:null!=a&&(d={points:a});return this.el("polygon",d)};(function(){function d(){return this.selectAll("stop")}function n(b,d){var f=e("stop"),k={offset:+d+"%"};b=a.color(b);k["stop-color"]=b.hex;1>b.opacity&&(k["stop-opacity"]=b.opacity);e(f,k);this.node.appendChild(f);return this}function u(){if("linearGradient"==this.type){var b=e(this.node,"x1")||0,d=e(this.node,"x2")||
1,f=e(this.node,"y1")||0,k=e(this.node,"y2")||0;return a._.box(b,f,math.abs(d-b),math.abs(k-f))}b=this.node.r||0;return a._.box((this.node.cx||0.5)-b,(this.node.cy||0.5)-b,2*b,2*b)}function p(a,d){function f(a,b){for(var d=(b-u)/(a-w),e=w;e<a;e++)h[e].offset=+(+u+d*(e-w)).toFixed(2);w=a;u=b}var n=k("snap.util.grad.parse",null,d).firstDefined(),p;if(!n)return null;n.params.unshift(a);p="l"==n.type.toLowerCase()?b.apply(0,n.params):q.apply(0,n.params);n.type!=n.type.toLowerCase()&&e(p.node,{gradientUnits:"userSpaceOnUse"});
var h=n.stops,n=h.length,u=0,w=0;n--;for(var v=0;v<n;v++)"offset"in h[v]&&f(v,h[v].offset);h[n].offset=h[n].offset||100;f(n,h[n].offset);for(v=0;v<=n;v++){var y=h[v];p.addStop(y.color,y.offset)}return p}function b(b,k,p,q,w){b=a._.make("linearGradient",b);b.stops=d;b.addStop=n;b.getBBox=u;null!=k&&e(b.node,{x1:k,y1:p,x2:q,y2:w});return b}function q(b,k,p,q,w,h){b=a._.make("radialGradient",b);b.stops=d;b.addStop=n;b.getBBox=u;null!=k&&e(b.node,{cx:k,cy:p,r:q});null!=w&&null!=h&&e(b.node,{fx:w,fy:h});
return b}var e=a._.$;w.gradient=function(a){return p(this.defs,a)};w.gradientLinear=function(a,d,e,f){return b(this.defs,a,d,e,f)};w.gradientRadial=function(a,b,d,e,f){return q(this.defs,a,b,d,e,f)};w.toString=function(){var b=this.node.ownerDocument,d=b.createDocumentFragment(),b=b.createElement("div"),e=this.node.cloneNode(!0);d.appendChild(b);b.appendChild(e);a._.$(e,{xmlns:"http://www.w3.org/2000/svg"});b=b.innerHTML;d.removeChild(d.firstChild);return b};w.clear=function(){for(var a=this.node.firstChild,
b;a;)b=a.nextSibling,"defs"!=a.tagName?a.parentNode.removeChild(a):w.clear.call({node:a}),a=b}})()});C.plugin(function(a,k,y,M){function A(a){var b=A.ps=A.ps||{};b[a]?b[a].sleep=100:b[a]={sleep:100};setTimeout(function(){for(var d in b)b[L](d)&&d!=a&&(b[d].sleep--,!b[d].sleep&&delete b[d])});return b[a]}function w(a,b,d,e){null==a&&(a=b=d=e=0);null==b&&(b=a.y,d=a.width,e=a.height,a=a.x);return{x:a,y:b,width:d,w:d,height:e,h:e,x2:a+d,y2:b+e,cx:a+d/2,cy:b+e/2,r1:F.min(d,e)/2,r2:F.max(d,e)/2,r0:F.sqrt(d*
d+e*e)/2,path:s(a,b,d,e),vb:[a,b,d,e].join(" ")}}function z(){return this.join(",").replace(N,"$1")}function d(a){a=C(a);a.toString=z;return a}function f(a,b,d,h,f,k,l,n,p){if(null==p)return e(a,b,d,h,f,k,l,n);if(0>p||e(a,b,d,h,f,k,l,n)<p)p=void 0;else{var q=0.5,O=1-q,s;for(s=e(a,b,d,h,f,k,l,n,O);0.01<Z(s-p);)q/=2,O+=(s<p?1:-1)*q,s=e(a,b,d,h,f,k,l,n,O);p=O}return u(a,b,d,h,f,k,l,n,p)}function n(b,d){function e(a){return+(+a).toFixed(3)}return a._.cacher(function(a,h,l){a instanceof k&&(a=a.attr("d"));
a=I(a);for(var n,p,D,q,O="",s={},c=0,t=0,r=a.length;t<r;t++){D=a[t];if("M"==D[0])n=+D[1],p=+D[2];else{q=f(n,p,D[1],D[2],D[3],D[4],D[5],D[6]);if(c+q>h){if(d&&!s.start){n=f(n,p,D[1],D[2],D[3],D[4],D[5],D[6],h-c);O+=["C"+e(n.start.x),e(n.start.y),e(n.m.x),e(n.m.y),e(n.x),e(n.y)];if(l)return O;s.start=O;O=["M"+e(n.x),e(n.y)+"C"+e(n.n.x),e(n.n.y),e(n.end.x),e(n.end.y),e(D[5]),e(D[6])].join();c+=q;n=+D[5];p=+D[6];continue}if(!b&&!d)return n=f(n,p,D[1],D[2],D[3],D[4],D[5],D[6],h-c)}c+=q;n=+D[5];p=+D[6]}O+=
D.shift()+D}s.end=O;return n=b?c:d?s:u(n,p,D[0],D[1],D[2],D[3],D[4],D[5],1)},null,a._.clone)}function u(a,b,d,e,h,f,k,l,n){var p=1-n,q=ma(p,3),s=ma(p,2),c=n*n,t=c*n,r=q*a+3*s*n*d+3*p*n*n*h+t*k,q=q*b+3*s*n*e+3*p*n*n*f+t*l,s=a+2*n*(d-a)+c*(h-2*d+a),t=b+2*n*(e-b)+c*(f-2*e+b),x=d+2*n*(h-d)+c*(k-2*h+d),c=e+2*n*(f-e)+c*(l-2*f+e);a=p*a+n*d;b=p*b+n*e;h=p*h+n*k;f=p*f+n*l;l=90-180*F.atan2(s-x,t-c)/S;return{x:r,y:q,m:{x:s,y:t},n:{x:x,y:c},start:{x:a,y:b},end:{x:h,y:f},alpha:l}}function p(b,d,e,h,f,n,k,l){a.is(b,
"array")||(b=[b,d,e,h,f,n,k,l]);b=U.apply(null,b);return w(b.min.x,b.min.y,b.max.x-b.min.x,b.max.y-b.min.y)}function b(a,b,d){return b>=a.x&&b<=a.x+a.width&&d>=a.y&&d<=a.y+a.height}function q(a,d){a=w(a);d=w(d);return b(d,a.x,a.y)||b(d,a.x2,a.y)||b(d,a.x,a.y2)||b(d,a.x2,a.y2)||b(a,d.x,d.y)||b(a,d.x2,d.y)||b(a,d.x,d.y2)||b(a,d.x2,d.y2)||(a.x<d.x2&&a.x>d.x||d.x<a.x2&&d.x>a.x)&&(a.y<d.y2&&a.y>d.y||d.y<a.y2&&d.y>a.y)}function e(a,b,d,e,h,f,n,k,l){null==l&&(l=1);l=(1<l?1:0>l?0:l)/2;for(var p=[-0.1252,
0.1252,-0.3678,0.3678,-0.5873,0.5873,-0.7699,0.7699,-0.9041,0.9041,-0.9816,0.9816],q=[0.2491,0.2491,0.2335,0.2335,0.2032,0.2032,0.1601,0.1601,0.1069,0.1069,0.0472,0.0472],s=0,c=0;12>c;c++)var t=l*p[c]+l,r=t*(t*(-3*a+9*d-9*h+3*n)+6*a-12*d+6*h)-3*a+3*d,t=t*(t*(-3*b+9*e-9*f+3*k)+6*b-12*e+6*f)-3*b+3*e,s=s+q[c]*F.sqrt(r*r+t*t);return l*s}function l(a,b,d){a=I(a);b=I(b);for(var h,f,l,n,k,s,r,O,x,c,t=d?0:[],w=0,v=a.length;w<v;w++)if(x=a[w],"M"==x[0])h=k=x[1],f=s=x[2];else{"C"==x[0]?(x=[h,f].concat(x.slice(1)),
h=x[6],f=x[7]):(x=[h,f,h,f,k,s,k,s],h=k,f=s);for(var G=0,y=b.length;G<y;G++)if(c=b[G],"M"==c[0])l=r=c[1],n=O=c[2];else{"C"==c[0]?(c=[l,n].concat(c.slice(1)),l=c[6],n=c[7]):(c=[l,n,l,n,r,O,r,O],l=r,n=O);var z;var K=x,B=c;z=d;var H=p(K),J=p(B);if(q(H,J)){for(var H=e.apply(0,K),J=e.apply(0,B),H=~~(H/8),J=~~(J/8),U=[],A=[],F={},M=z?0:[],P=0;P<H+1;P++){var C=u.apply(0,K.concat(P/H));U.push({x:C.x,y:C.y,t:P/H})}for(P=0;P<J+1;P++)C=u.apply(0,B.concat(P/J)),A.push({x:C.x,y:C.y,t:P/J});for(P=0;P<H;P++)for(K=
0;K<J;K++){var Q=U[P],L=U[P+1],B=A[K],C=A[K+1],N=0.001>Z(L.x-Q.x)?"y":"x",S=0.001>Z(C.x-B.x)?"y":"x",R;R=Q.x;var Y=Q.y,V=L.x,ea=L.y,fa=B.x,ga=B.y,ha=C.x,ia=C.y;if(W(R,V)<X(fa,ha)||X(R,V)>W(fa,ha)||W(Y,ea)<X(ga,ia)||X(Y,ea)>W(ga,ia))R=void 0;else{var $=(R*ea-Y*V)*(fa-ha)-(R-V)*(fa*ia-ga*ha),aa=(R*ea-Y*V)*(ga-ia)-(Y-ea)*(fa*ia-ga*ha),ja=(R-V)*(ga-ia)-(Y-ea)*(fa-ha);if(ja){var $=$/ja,aa=aa/ja,ja=+$.toFixed(2),ba=+aa.toFixed(2);R=ja<+X(R,V).toFixed(2)||ja>+W(R,V).toFixed(2)||ja<+X(fa,ha).toFixed(2)||
ja>+W(fa,ha).toFixed(2)||ba<+X(Y,ea).toFixed(2)||ba>+W(Y,ea).toFixed(2)||ba<+X(ga,ia).toFixed(2)||ba>+W(ga,ia).toFixed(2)?void 0:{x:$,y:aa}}else R=void 0}R&&F[R.x.toFixed(4)]!=R.y.toFixed(4)&&(F[R.x.toFixed(4)]=R.y.toFixed(4),Q=Q.t+Z((R[N]-Q[N])/(L[N]-Q[N]))*(L.t-Q.t),B=B.t+Z((R[S]-B[S])/(C[S]-B[S]))*(C.t-B.t),0<=Q&&1>=Q&&0<=B&&1>=B&&(z?M++:M.push({x:R.x,y:R.y,t1:Q,t2:B})))}z=M}else z=z?0:[];if(d)t+=z;else{H=0;for(J=z.length;H<J;H++)z[H].segment1=w,z[H].segment2=G,z[H].bez1=x,z[H].bez2=c;t=t.concat(z)}}}return t}
function r(a){var b=A(a);if(b.bbox)return C(b.bbox);if(!a)return w();a=I(a);for(var d=0,e=0,h=[],f=[],l,n=0,k=a.length;n<k;n++)l=a[n],"M"==l[0]?(d=l[1],e=l[2],h.push(d),f.push(e)):(d=U(d,e,l[1],l[2],l[3],l[4],l[5],l[6]),h=h.concat(d.min.x,d.max.x),f=f.concat(d.min.y,d.max.y),d=l[5],e=l[6]);a=X.apply(0,h);l=X.apply(0,f);h=W.apply(0,h);f=W.apply(0,f);f=w(a,l,h-a,f-l);b.bbox=C(f);return f}function s(a,b,d,e,h){if(h)return[["M",+a+ +h,b],["l",d-2*h,0],["a",h,h,0,0,1,h,h],["l",0,e-2*h],["a",h,h,0,0,1,
-h,h],["l",2*h-d,0],["a",h,h,0,0,1,-h,-h],["l",0,2*h-e],["a",h,h,0,0,1,h,-h],["z"] ];a=[["M",a,b],["l",d,0],["l",0,e],["l",-d,0],["z"] ];a.toString=z;return a}function x(a,b,d,e,h){null==h&&null==e&&(e=d);a=+a;b=+b;d=+d;e=+e;if(null!=h){var f=Math.PI/180,l=a+d*Math.cos(-e*f);a+=d*Math.cos(-h*f);var n=b+d*Math.sin(-e*f);b+=d*Math.sin(-h*f);d=[["M",l,n],["A",d,d,0,+(180<h-e),0,a,b] ]}else d=[["M",a,b],["m",0,-e],["a",d,e,0,1,1,0,2*e],["a",d,e,0,1,1,0,-2*e],["z"] ];d.toString=z;return d}function G(b){var e=
A(b);if(e.abs)return d(e.abs);Q(b,"array")&&Q(b&&b[0],"array")||(b=a.parsePathString(b));if(!b||!b.length)return[["M",0,0] ];var h=[],f=0,l=0,n=0,k=0,p=0;"M"==b[0][0]&&(f=+b[0][1],l=+b[0][2],n=f,k=l,p++,h[0]=["M",f,l]);for(var q=3==b.length&&"M"==b[0][0]&&"R"==b[1][0].toUpperCase()&&"Z"==b[2][0].toUpperCase(),s,r,w=p,c=b.length;w<c;w++){h.push(s=[]);r=b[w];p=r[0];if(p!=p.toUpperCase())switch(s[0]=p.toUpperCase(),s[0]){case "A":s[1]=r[1];s[2]=r[2];s[3]=r[3];s[4]=r[4];s[5]=r[5];s[6]=+r[6]+f;s[7]=+r[7]+
l;break;case "V":s[1]=+r[1]+l;break;case "H":s[1]=+r[1]+f;break;case "R":for(var t=[f,l].concat(r.slice(1)),u=2,v=t.length;u<v;u++)t[u]=+t[u]+f,t[++u]=+t[u]+l;h.pop();h=h.concat(P(t,q));break;case "O":h.pop();t=x(f,l,r[1],r[2]);t.push(t[0]);h=h.concat(t);break;case "U":h.pop();h=h.concat(x(f,l,r[1],r[2],r[3]));s=["U"].concat(h[h.length-1].slice(-2));break;case "M":n=+r[1]+f,k=+r[2]+l;default:for(u=1,v=r.length;u<v;u++)s[u]=+r[u]+(u%2?f:l)}else if("R"==p)t=[f,l].concat(r.slice(1)),h.pop(),h=h.concat(P(t,
q)),s=["R"].concat(r.slice(-2));else if("O"==p)h.pop(),t=x(f,l,r[1],r[2]),t.push(t[0]),h=h.concat(t);else if("U"==p)h.pop(),h=h.concat(x(f,l,r[1],r[2],r[3])),s=["U"].concat(h[h.length-1].slice(-2));else for(t=0,u=r.length;t<u;t++)s[t]=r[t];p=p.toUpperCase();if("O"!=p)switch(s[0]){case "Z":f=+n;l=+k;break;case "H":f=s[1];break;case "V":l=s[1];break;case "M":n=s[s.length-2],k=s[s.length-1];default:f=s[s.length-2],l=s[s.length-1]}}h.toString=z;e.abs=d(h);return h}function h(a,b,d,e){return[a,b,d,e,d,
e]}function J(a,b,d,e,h,f){var l=1/3,n=2/3;return[l*a+n*d,l*b+n*e,l*h+n*d,l*f+n*e,h,f]}function K(b,d,e,h,f,l,n,k,p,s){var r=120*S/180,q=S/180*(+f||0),c=[],t,x=a._.cacher(function(a,b,c){var d=a*F.cos(c)-b*F.sin(c);a=a*F.sin(c)+b*F.cos(c);return{x:d,y:a}});if(s)v=s[0],t=s[1],l=s[2],u=s[3];else{t=x(b,d,-q);b=t.x;d=t.y;t=x(k,p,-q);k=t.x;p=t.y;F.cos(S/180*f);F.sin(S/180*f);t=(b-k)/2;v=(d-p)/2;u=t*t/(e*e)+v*v/(h*h);1<u&&(u=F.sqrt(u),e*=u,h*=u);var u=e*e,w=h*h,u=(l==n?-1:1)*F.sqrt(Z((u*w-u*v*v-w*t*t)/
(u*v*v+w*t*t)));l=u*e*v/h+(b+k)/2;var u=u*-h*t/e+(d+p)/2,v=F.asin(((d-u)/h).toFixed(9));t=F.asin(((p-u)/h).toFixed(9));v=b<l?S-v:v;t=k<l?S-t:t;0>v&&(v=2*S+v);0>t&&(t=2*S+t);n&&v>t&&(v-=2*S);!n&&t>v&&(t-=2*S)}if(Z(t-v)>r){var c=t,w=k,G=p;t=v+r*(n&&t>v?1:-1);k=l+e*F.cos(t);p=u+h*F.sin(t);c=K(k,p,e,h,f,0,n,w,G,[t,c,l,u])}l=t-v;f=F.cos(v);r=F.sin(v);n=F.cos(t);t=F.sin(t);l=F.tan(l/4);e=4/3*e*l;l*=4/3*h;h=[b,d];b=[b+e*r,d-l*f];d=[k+e*t,p-l*n];k=[k,p];b[0]=2*h[0]-b[0];b[1]=2*h[1]-b[1];if(s)return[b,d,k].concat(c);
c=[b,d,k].concat(c).join().split(",");s=[];k=0;for(p=c.length;k<p;k++)s[k]=k%2?x(c[k-1],c[k],q).y:x(c[k],c[k+1],q).x;return s}function U(a,b,d,e,h,f,l,k){for(var n=[],p=[[],[] ],s,r,c,t,q=0;2>q;++q)0==q?(r=6*a-12*d+6*h,s=-3*a+9*d-9*h+3*l,c=3*d-3*a):(r=6*b-12*e+6*f,s=-3*b+9*e-9*f+3*k,c=3*e-3*b),1E-12>Z(s)?1E-12>Z(r)||(s=-c/r,0<s&&1>s&&n.push(s)):(t=r*r-4*c*s,c=F.sqrt(t),0>t||(t=(-r+c)/(2*s),0<t&&1>t&&n.push(t),s=(-r-c)/(2*s),0<s&&1>s&&n.push(s)));for(r=q=n.length;q--;)s=n[q],c=1-s,p[0][q]=c*c*c*a+3*
c*c*s*d+3*c*s*s*h+s*s*s*l,p[1][q]=c*c*c*b+3*c*c*s*e+3*c*s*s*f+s*s*s*k;p[0][r]=a;p[1][r]=b;p[0][r+1]=l;p[1][r+1]=k;p[0].length=p[1].length=r+2;return{min:{x:X.apply(0,p[0]),y:X.apply(0,p[1])},max:{x:W.apply(0,p[0]),y:W.apply(0,p[1])}}}function I(a,b){var e=!b&&A(a);if(!b&&e.curve)return d(e.curve);var f=G(a),l=b&&G(b),n={x:0,y:0,bx:0,by:0,X:0,Y:0,qx:null,qy:null},k={x:0,y:0,bx:0,by:0,X:0,Y:0,qx:null,qy:null},p=function(a,b,c){if(!a)return["C",b.x,b.y,b.x,b.y,b.x,b.y];a[0]in{T:1,Q:1}||(b.qx=b.qy=null);
switch(a[0]){case "M":b.X=a[1];b.Y=a[2];break;case "A":a=["C"].concat(K.apply(0,[b.x,b.y].concat(a.slice(1))));break;case "S":"C"==c||"S"==c?(c=2*b.x-b.bx,b=2*b.y-b.by):(c=b.x,b=b.y);a=["C",c,b].concat(a.slice(1));break;case "T":"Q"==c||"T"==c?(b.qx=2*b.x-b.qx,b.qy=2*b.y-b.qy):(b.qx=b.x,b.qy=b.y);a=["C"].concat(J(b.x,b.y,b.qx,b.qy,a[1],a[2]));break;case "Q":b.qx=a[1];b.qy=a[2];a=["C"].concat(J(b.x,b.y,a[1],a[2],a[3],a[4]));break;case "L":a=["C"].concat(h(b.x,b.y,a[1],a[2]));break;case "H":a=["C"].concat(h(b.x,
b.y,a[1],b.y));break;case "V":a=["C"].concat(h(b.x,b.y,b.x,a[1]));break;case "Z":a=["C"].concat(h(b.x,b.y,b.X,b.Y))}return a},s=function(a,b){if(7<a[b].length){a[b].shift();for(var c=a[b];c.length;)q[b]="A",l&&(u[b]="A"),a.splice(b++,0,["C"].concat(c.splice(0,6)));a.splice(b,1);v=W(f.length,l&&l.length||0)}},r=function(a,b,c,d,e){a&&b&&"M"==a[e][0]&&"M"!=b[e][0]&&(b.splice(e,0,["M",d.x,d.y]),c.bx=0,c.by=0,c.x=a[e][1],c.y=a[e][2],v=W(f.length,l&&l.length||0))},q=[],u=[],c="",t="",x=0,v=W(f.length,
l&&l.length||0);for(;x<v;x++){f[x]&&(c=f[x][0]);"C"!=c&&(q[x]=c,x&&(t=q[x-1]));f[x]=p(f[x],n,t);"A"!=q[x]&&"C"==c&&(q[x]="C");s(f,x);l&&(l[x]&&(c=l[x][0]),"C"!=c&&(u[x]=c,x&&(t=u[x-1])),l[x]=p(l[x],k,t),"A"!=u[x]&&"C"==c&&(u[x]="C"),s(l,x));r(f,l,n,k,x);r(l,f,k,n,x);var w=f[x],z=l&&l[x],y=w.length,U=l&&z.length;n.x=w[y-2];n.y=w[y-1];n.bx=$(w[y-4])||n.x;n.by=$(w[y-3])||n.y;k.bx=l&&($(z[U-4])||k.x);k.by=l&&($(z[U-3])||k.y);k.x=l&&z[U-2];k.y=l&&z[U-1]}l||(e.curve=d(f));return l?[f,l]:f}function P(a,
b){for(var d=[],e=0,h=a.length;h-2*!b>e;e+=2){var f=[{x:+a[e-2],y:+a[e-1]},{x:+a[e],y:+a[e+1]},{x:+a[e+2],y:+a[e+3]},{x:+a[e+4],y:+a[e+5]}];b?e?h-4==e?f[3]={x:+a[0],y:+a[1]}:h-2==e&&(f[2]={x:+a[0],y:+a[1]},f[3]={x:+a[2],y:+a[3]}):f[0]={x:+a[h-2],y:+a[h-1]}:h-4==e?f[3]=f[2]:e||(f[0]={x:+a[e],y:+a[e+1]});d.push(["C",(-f[0].x+6*f[1].x+f[2].x)/6,(-f[0].y+6*f[1].y+f[2].y)/6,(f[1].x+6*f[2].x-f[3].x)/6,(f[1].y+6*f[2].y-f[3].y)/6,f[2].x,f[2].y])}return d}y=k.prototype;var Q=a.is,C=a._.clone,L="hasOwnProperty",
N=/,?([a-z]),?/gi,$=parseFloat,F=Math,S=F.PI,X=F.min,W=F.max,ma=F.pow,Z=F.abs;M=n(1);var na=n(),ba=n(0,1),V=a._unit2px;a.path=A;a.path.getTotalLength=M;a.path.getPointAtLength=na;a.path.getSubpath=function(a,b,d){if(1E-6>this.getTotalLength(a)-d)return ba(a,b).end;a=ba(a,d,1);return b?ba(a,b).end:a};y.getTotalLength=function(){if(this.node.getTotalLength)return this.node.getTotalLength()};y.getPointAtLength=function(a){return na(this.attr("d"),a)};y.getSubpath=function(b,d){return a.path.getSubpath(this.attr("d"),
b,d)};a._.box=w;a.path.findDotsAtSegment=u;a.path.bezierBBox=p;a.path.isPointInsideBBox=b;a.path.isBBoxIntersect=q;a.path.intersection=function(a,b){return l(a,b)};a.path.intersectionNumber=function(a,b){return l(a,b,1)};a.path.isPointInside=function(a,d,e){var h=r(a);return b(h,d,e)&&1==l(a,[["M",d,e],["H",h.x2+10] ],1)%2};a.path.getBBox=r;a.path.get={path:function(a){return a.attr("path")},circle:function(a){a=V(a);return x(a.cx,a.cy,a.r)},ellipse:function(a){a=V(a);return x(a.cx||0,a.cy||0,a.rx,
a.ry)},rect:function(a){a=V(a);return s(a.x||0,a.y||0,a.width,a.height,a.rx,a.ry)},image:function(a){a=V(a);return s(a.x||0,a.y||0,a.width,a.height)},line:function(a){return"M"+[a.attr("x1")||0,a.attr("y1")||0,a.attr("x2"),a.attr("y2")]},polyline:function(a){return"M"+a.attr("points")},polygon:function(a){return"M"+a.attr("points")+"z"},deflt:function(a){a=a.node.getBBox();return s(a.x,a.y,a.width,a.height)}};a.path.toRelative=function(b){var e=A(b),h=String.prototype.toLowerCase;if(e.rel)return d(e.rel);
a.is(b,"array")&&a.is(b&&b[0],"array")||(b=a.parsePathString(b));var f=[],l=0,n=0,k=0,p=0,s=0;"M"==b[0][0]&&(l=b[0][1],n=b[0][2],k=l,p=n,s++,f.push(["M",l,n]));for(var r=b.length;s<r;s++){var q=f[s]=[],x=b[s];if(x[0]!=h.call(x[0]))switch(q[0]=h.call(x[0]),q[0]){case "a":q[1]=x[1];q[2]=x[2];q[3]=x[3];q[4]=x[4];q[5]=x[5];q[6]=+(x[6]-l).toFixed(3);q[7]=+(x[7]-n).toFixed(3);break;case "v":q[1]=+(x[1]-n).toFixed(3);break;case "m":k=x[1],p=x[2];default:for(var c=1,t=x.length;c<t;c++)q[c]=+(x[c]-(c%2?l:
n)).toFixed(3)}else for(f[s]=[],"m"==x[0]&&(k=x[1]+l,p=x[2]+n),q=0,c=x.length;q<c;q++)f[s][q]=x[q];x=f[s].length;switch(f[s][0]){case "z":l=k;n=p;break;case "h":l+=+f[s][x-1];break;case "v":n+=+f[s][x-1];break;default:l+=+f[s][x-2],n+=+f[s][x-1]}}f.toString=z;e.rel=d(f);return f};a.path.toAbsolute=G;a.path.toCubic=I;a.path.map=function(a,b){if(!b)return a;var d,e,h,f,l,n,k;a=I(a);h=0;for(l=a.length;h<l;h++)for(k=a[h],f=1,n=k.length;f<n;f+=2)d=b.x(k[f],k[f+1]),e=b.y(k[f],k[f+1]),k[f]=d,k[f+1]=e;return a};
a.path.toString=z;a.path.clone=d});C.plugin(function(a,v,y,C){var A=Math.max,w=Math.min,z=function(a){this.items=[];this.bindings={};this.length=0;this.type="set";if(a)for(var f=0,n=a.length;f<n;f++)a[f]&&(this[this.items.length]=this.items[this.items.length]=a[f],this.length++)};v=z.prototype;v.push=function(){for(var a,f,n=0,k=arguments.length;n<k;n++)if(a=arguments[n])f=this.items.length,this[f]=this.items[f]=a,this.length++;return this};v.pop=function(){this.length&&delete this[this.length--];
return this.items.pop()};v.forEach=function(a,f){for(var n=0,k=this.items.length;n<k&&!1!==a.call(f,this.items[n],n);n++);return this};v.animate=function(d,f,n,u){"function"!=typeof n||n.length||(u=n,n=L.linear);d instanceof a._.Animation&&(u=d.callback,n=d.easing,f=n.dur,d=d.attr);var p=arguments;if(a.is(d,"array")&&a.is(p[p.length-1],"array"))var b=!0;var q,e=function(){q?this.b=q:q=this.b},l=0,r=u&&function(){l++==this.length&&u.call(this)};return this.forEach(function(a,l){k.once("snap.animcreated."+
a.id,e);b?p[l]&&a.animate.apply(a,p[l]):a.animate(d,f,n,r)})};v.remove=function(){for(;this.length;)this.pop().remove();return this};v.bind=function(a,f,k){var u={};if("function"==typeof f)this.bindings[a]=f;else{var p=k||a;this.bindings[a]=function(a){u[p]=a;f.attr(u)}}return this};v.attr=function(a){var f={},k;for(k in a)if(this.bindings[k])this.bindings[k](a[k]);else f[k]=a[k];a=0;for(k=this.items.length;a<k;a++)this.items[a].attr(f);return this};v.clear=function(){for(;this.length;)this.pop()};
v.splice=function(a,f,k){a=0>a?A(this.length+a,0):a;f=A(0,w(this.length-a,f));var u=[],p=[],b=[],q;for(q=2;q<arguments.length;q++)b.push(arguments[q]);for(q=0;q<f;q++)p.push(this[a+q]);for(;q<this.length-a;q++)u.push(this[a+q]);var e=b.length;for(q=0;q<e+u.length;q++)this.items[a+q]=this[a+q]=q<e?b[q]:u[q-e];for(q=this.items.length=this.length-=f-e;this[q];)delete this[q++];return new z(p)};v.exclude=function(a){for(var f=0,k=this.length;f<k;f++)if(this[f]==a)return this.splice(f,1),!0;return!1};
v.insertAfter=function(a){for(var f=this.items.length;f--;)this.items[f].insertAfter(a);return this};v.getBBox=function(){for(var a=[],f=[],k=[],u=[],p=this.items.length;p--;)if(!this.items[p].removed){var b=this.items[p].getBBox();a.push(b.x);f.push(b.y);k.push(b.x+b.width);u.push(b.y+b.height)}a=w.apply(0,a);f=w.apply(0,f);k=A.apply(0,k);u=A.apply(0,u);return{x:a,y:f,x2:k,y2:u,width:k-a,height:u-f,cx:a+(k-a)/2,cy:f+(u-f)/2}};v.clone=function(a){a=new z;for(var f=0,k=this.items.length;f<k;f++)a.push(this.items[f].clone());
return a};v.toString=function(){return"Snap\u2018s set"};v.type="set";a.set=function(){var a=new z;arguments.length&&a.push.apply(a,Array.prototype.slice.call(arguments,0));return a}});C.plugin(function(a,v,y,C){function A(a){var b=a[0];switch(b.toLowerCase()){case "t":return[b,0,0];case "m":return[b,1,0,0,1,0,0];case "r":return 4==a.length?[b,0,a[2],a[3] ]:[b,0];case "s":return 5==a.length?[b,1,1,a[3],a[4] ]:3==a.length?[b,1,1]:[b,1]}}function w(b,d,f){d=q(d).replace(/\.{3}|\u2026/g,b);b=a.parseTransformString(b)||
[];d=a.parseTransformString(d)||[];for(var k=Math.max(b.length,d.length),p=[],v=[],h=0,w,z,y,I;h<k;h++){y=b[h]||A(d[h]);I=d[h]||A(y);if(y[0]!=I[0]||"r"==y[0].toLowerCase()&&(y[2]!=I[2]||y[3]!=I[3])||"s"==y[0].toLowerCase()&&(y[3]!=I[3]||y[4]!=I[4])){b=a._.transform2matrix(b,f());d=a._.transform2matrix(d,f());p=[["m",b.a,b.b,b.c,b.d,b.e,b.f] ];v=[["m",d.a,d.b,d.c,d.d,d.e,d.f] ];break}p[h]=[];v[h]=[];w=0;for(z=Math.max(y.length,I.length);w<z;w++)w in y&&(p[h][w]=y[w]),w in I&&(v[h][w]=I[w])}return{from:u(p),
to:u(v),f:n(p)}}function z(a){return a}function d(a){return function(b){return+b.toFixed(3)+a}}function f(b){return a.rgb(b[0],b[1],b[2])}function n(a){var b=0,d,f,k,n,h,p,q=[];d=0;for(f=a.length;d<f;d++){h="[";p=['"'+a[d][0]+'"'];k=1;for(n=a[d].length;k<n;k++)p[k]="val["+b++ +"]";h+=p+"]";q[d]=h}return Function("val","return Snap.path.toString.call(["+q+"])")}function u(a){for(var b=[],d=0,f=a.length;d<f;d++)for(var k=1,n=a[d].length;k<n;k++)b.push(a[d][k]);return b}var p={},b=/[a-z]+$/i,q=String;
p.stroke=p.fill="colour";v.prototype.equal=function(a,b){return k("snap.util.equal",this,a,b).firstDefined()};k.on("snap.util.equal",function(e,k){var r,s;r=q(this.attr(e)||"");var x=this;if(r==+r&&k==+k)return{from:+r,to:+k,f:z};if("colour"==p[e])return r=a.color(r),s=a.color(k),{from:[r.r,r.g,r.b,r.opacity],to:[s.r,s.g,s.b,s.opacity],f:f};if("transform"==e||"gradientTransform"==e||"patternTransform"==e)return k instanceof a.Matrix&&(k=k.toTransformString()),a._.rgTransform.test(k)||(k=a._.svgTransform2string(k)),
w(r,k,function(){return x.getBBox(1)});if("d"==e||"path"==e)return r=a.path.toCubic(r,k),{from:u(r[0]),to:u(r[1]),f:n(r[0])};if("points"==e)return r=q(r).split(a._.separator),s=q(k).split(a._.separator),{from:r,to:s,f:function(a){return a}};aUnit=r.match(b);s=q(k).match(b);return aUnit&&aUnit==s?{from:parseFloat(r),to:parseFloat(k),f:d(aUnit)}:{from:this.asPX(e),to:this.asPX(e,k),f:z}})});C.plugin(function(a,v,y,C){var A=v.prototype,w="createTouch"in C.doc;v="click dblclick mousedown mousemove mouseout mouseover mouseup touchstart touchmove touchend touchcancel".split(" ");
var z={mousedown:"touchstart",mousemove:"touchmove",mouseup:"touchend"},d=function(a,b){var d="y"==a?"scrollTop":"scrollLeft",e=b&&b.node?b.node.ownerDocument:C.doc;return e[d in e.documentElement?"documentElement":"body"][d]},f=function(){this.returnValue=!1},n=function(){return this.originalEvent.preventDefault()},u=function(){this.cancelBubble=!0},p=function(){return this.originalEvent.stopPropagation()},b=function(){if(C.doc.addEventListener)return function(a,b,e,f){var k=w&&z[b]?z[b]:b,l=function(k){var l=
d("y",f),q=d("x",f);if(w&&z.hasOwnProperty(b))for(var r=0,u=k.targetTouches&&k.targetTouches.length;r<u;r++)if(k.targetTouches[r].target==a||a.contains(k.targetTouches[r].target)){u=k;k=k.targetTouches[r];k.originalEvent=u;k.preventDefault=n;k.stopPropagation=p;break}return e.call(f,k,k.clientX+q,k.clientY+l)};b!==k&&a.addEventListener(b,l,!1);a.addEventListener(k,l,!1);return function(){b!==k&&a.removeEventListener(b,l,!1);a.removeEventListener(k,l,!1);return!0}};if(C.doc.attachEvent)return function(a,
b,e,h){var k=function(a){a=a||h.node.ownerDocument.window.event;var b=d("y",h),k=d("x",h),k=a.clientX+k,b=a.clientY+b;a.preventDefault=a.preventDefault||f;a.stopPropagation=a.stopPropagation||u;return e.call(h,a,k,b)};a.attachEvent("on"+b,k);return function(){a.detachEvent("on"+b,k);return!0}}}(),q=[],e=function(a){for(var b=a.clientX,e=a.clientY,f=d("y"),l=d("x"),n,p=q.length;p--;){n=q[p];if(w)for(var r=a.touches&&a.touches.length,u;r--;){if(u=a.touches[r],u.identifier==n.el._drag.id||n.el.node.contains(u.target)){b=
u.clientX;e=u.clientY;(a.originalEvent?a.originalEvent:a).preventDefault();break}}else a.preventDefault();b+=l;e+=f;k("snap.drag.move."+n.el.id,n.move_scope||n.el,b-n.el._drag.x,e-n.el._drag.y,b,e,a)}},l=function(b){a.unmousemove(e).unmouseup(l);for(var d=q.length,f;d--;)f=q[d],f.el._drag={},k("snap.drag.end."+f.el.id,f.end_scope||f.start_scope||f.move_scope||f.el,b);q=[]};for(y=v.length;y--;)(function(d){a[d]=A[d]=function(e,f){a.is(e,"function")&&(this.events=this.events||[],this.events.push({name:d,
f:e,unbind:b(this.node||document,d,e,f||this)}));return this};a["un"+d]=A["un"+d]=function(a){for(var b=this.events||[],e=b.length;e--;)if(b[e].name==d&&(b[e].f==a||!a)){b[e].unbind();b.splice(e,1);!b.length&&delete this.events;break}return this}})(v[y]);A.hover=function(a,b,d,e){return this.mouseover(a,d).mouseout(b,e||d)};A.unhover=function(a,b){return this.unmouseover(a).unmouseout(b)};var r=[];A.drag=function(b,d,f,h,n,p){function u(r,v,w){(r.originalEvent||r).preventDefault();this._drag.x=v;
this._drag.y=w;this._drag.id=r.identifier;!q.length&&a.mousemove(e).mouseup(l);q.push({el:this,move_scope:h,start_scope:n,end_scope:p});d&&k.on("snap.drag.start."+this.id,d);b&&k.on("snap.drag.move."+this.id,b);f&&k.on("snap.drag.end."+this.id,f);k("snap.drag.start."+this.id,n||h||this,v,w,r)}if(!arguments.length){var v;return this.drag(function(a,b){this.attr({transform:v+(v?"T":"t")+[a,b]})},function(){v=this.transform().local})}this._drag={};r.push({el:this,start:u});this.mousedown(u);return this};
A.undrag=function(){for(var b=r.length;b--;)r[b].el==this&&(this.unmousedown(r[b].start),r.splice(b,1),k.unbind("snap.drag.*."+this.id));!r.length&&a.unmousemove(e).unmouseup(l);return this}});C.plugin(function(a,v,y,C){y=y.prototype;var A=/^\s*url\((.+)\)/,w=String,z=a._.$;a.filter={};y.filter=function(d){var f=this;"svg"!=f.type&&(f=f.paper);d=a.parse(w(d));var k=a._.id(),u=z("filter");z(u,{id:k,filterUnits:"userSpaceOnUse"});u.appendChild(d.node);f.defs.appendChild(u);return new v(u)};k.on("snap.util.getattr.filter",
function(){k.stop();var d=z(this.node,"filter");if(d)return(d=w(d).match(A))&&a.select(d[1])});k.on("snap.util.attr.filter",function(d){if(d instanceof v&&"filter"==d.type){k.stop();var f=d.node.id;f||(z(d.node,{id:d.id}),f=d.id);z(this.node,{filter:a.url(f)})}d&&"none"!=d||(k.stop(),this.node.removeAttribute("filter"))});a.filter.blur=function(d,f){null==d&&(d=2);return a.format('<feGaussianBlur stdDeviation="{def}"/>',{def:null==f?d:[d,f]})};a.filter.blur.toString=function(){return this()};a.filter.shadow=
function(d,f,k,u,p){"string"==typeof k&&(p=u=k,k=4);"string"!=typeof u&&(p=u,u="#000");null==k&&(k=4);null==p&&(p=1);null==d&&(d=0,f=2);null==f&&(f=d);u=a.color(u||"#000");return a.format('<feGaussianBlur in="SourceAlpha" stdDeviation="{blur}"/><feOffset dx="{dx}" dy="{dy}" result="offsetblur"/><feFlood flood-color="{color}"/><feComposite in2="offsetblur" operator="in"/><feComponentTransfer><feFuncA type="linear" slope="{opacity}"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>',
{color:u,dx:d,dy:f,blur:k,opacity:p})};a.filter.shadow.toString=function(){return this()};a.filter.grayscale=function(d){null==d&&(d=1);return a.format('<feColorMatrix type="matrix" values="{a} {b} {c} 0 0 {d} {e} {f} 0 0 {g} {b} {h} 0 0 0 0 0 1 0"/>',{a:0.2126+0.7874*(1-d),b:0.7152-0.7152*(1-d),c:0.0722-0.0722*(1-d),d:0.2126-0.2126*(1-d),e:0.7152+0.2848*(1-d),f:0.0722-0.0722*(1-d),g:0.2126-0.2126*(1-d),h:0.0722+0.9278*(1-d)})};a.filter.grayscale.toString=function(){return this()};a.filter.sepia=
function(d){null==d&&(d=1);return a.format('<feColorMatrix type="matrix" values="{a} {b} {c} 0 0 {d} {e} {f} 0 0 {g} {h} {i} 0 0 0 0 0 1 0"/>',{a:0.393+0.607*(1-d),b:0.769-0.769*(1-d),c:0.189-0.189*(1-d),d:0.349-0.349*(1-d),e:0.686+0.314*(1-d),f:0.168-0.168*(1-d),g:0.272-0.272*(1-d),h:0.534-0.534*(1-d),i:0.131+0.869*(1-d)})};a.filter.sepia.toString=function(){return this()};a.filter.saturate=function(d){null==d&&(d=1);return a.format('<feColorMatrix type="saturate" values="{amount}"/>',{amount:1-
d})};a.filter.saturate.toString=function(){return this()};a.filter.hueRotate=function(d){return a.format('<feColorMatrix type="hueRotate" values="{angle}"/>',{angle:d||0})};a.filter.hueRotate.toString=function(){return this()};a.filter.invert=function(d){null==d&&(d=1);return a.format('<feComponentTransfer><feFuncR type="table" tableValues="{amount} {amount2}"/><feFuncG type="table" tableValues="{amount} {amount2}"/><feFuncB type="table" tableValues="{amount} {amount2}"/></feComponentTransfer>',{amount:d,
amount2:1-d})};a.filter.invert.toString=function(){return this()};a.filter.brightness=function(d){null==d&&(d=1);return a.format('<feComponentTransfer><feFuncR type="linear" slope="{amount}"/><feFuncG type="linear" slope="{amount}"/><feFuncB type="linear" slope="{amount}"/></feComponentTransfer>',{amount:d})};a.filter.brightness.toString=function(){return this()};a.filter.contrast=function(d){null==d&&(d=1);return a.format('<feComponentTransfer><feFuncR type="linear" slope="{amount}" intercept="{amount2}"/><feFuncG type="linear" slope="{amount}" intercept="{amount2}"/><feFuncB type="linear" slope="{amount}" intercept="{amount2}"/></feComponentTransfer>',
{amount:d,amount2:0.5-d/2})};a.filter.contrast.toString=function(){return this()}});return C});

]]> </script>
<script> <![CDATA[

(function (glob, factory) {
    // AMD support
    if (typeof define === "function" && define.amd) {
        // Define as an anonymous module
        define("Gadfly", ["Snap.svg"], function (Snap) {
            return factory(Snap);
        });
    } else {
        // Browser globals (glob is window)
        // Snap adds itself to window
        glob.Gadfly = factory(glob.Snap);
    }
}(this, function (Snap) {

var Gadfly = {};

// Get an x/y coordinate value in pixels
var xPX = function(fig, x) {
    var client_box = fig.node.getBoundingClientRect();
    return x * fig.node.viewBox.baseVal.width / client_box.width;
};

var yPX = function(fig, y) {
    var client_box = fig.node.getBoundingClientRect();
    return y * fig.node.viewBox.baseVal.height / client_box.height;
};


Snap.plugin(function (Snap, Element, Paper, global) {
    // Traverse upwards from a snap element to find and return the first
    // note with the "plotroot" class.
    Element.prototype.plotroot = function () {
        var element = this;
        while (!element.hasClass("plotroot") && element.parent() != null) {
            element = element.parent();
        }
        return element;
    };

    Element.prototype.svgroot = function () {
        var element = this;
        while (element.node.nodeName != "svg" && element.parent() != null) {
            element = element.parent();
        }
        return element;
    };

    Element.prototype.plotbounds = function () {
        var root = this.plotroot()
        var bbox = root.select(".guide.background").node.getBBox();
        return {
            x0: bbox.x,
            x1: bbox.x + bbox.width,
            y0: bbox.y,
            y1: bbox.y + bbox.height
        };
    };

    Element.prototype.plotcenter = function () {
        var root = this.plotroot()
        var bbox = root.select(".guide.background").node.getBBox();
        return {
            x: bbox.x + bbox.width / 2,
            y: bbox.y + bbox.height / 2
        };
    };

    // Emulate IE style mouseenter/mouseleave events, since Microsoft always
    // does everything right.
    // See: http://www.dynamic-tools.net/toolbox/isMouseLeaveOrEnter/
    var events = ["mouseenter", "mouseleave"];

    for (i in events) {
        (function (event_name) {
            var event_name = events[i];
            Element.prototype[event_name] = function (fn, scope) {
                if (Snap.is(fn, "function")) {
                    var fn2 = function (event) {
                        if (event.type != "mouseover" && event.type != "mouseout") {
                            return;
                        }

                        var reltg = event.relatedTarget ? event.relatedTarget :
                            event.type == "mouseout" ? event.toElement : event.fromElement;
                        while (reltg && reltg != this.node) reltg = reltg.parentNode;

                        if (reltg != this.node) {
                            return fn.apply(this, event);
                        }
                    };

                    if (event_name == "mouseenter") {
                        this.mouseover(fn2, scope);
                    } else {
                        this.mouseout(fn2, scope);
                    }
                }
                return this;
            };
        })(events[i]);
    }


    Element.prototype.mousewheel = function (fn, scope) {
        if (Snap.is(fn, "function")) {
            var el = this;
            var fn2 = function (event) {
                fn.apply(el, [event]);
            };
        }

        this.node.addEventListener(
            /Firefox/i.test(navigator.userAgent) ? "DOMMouseScroll" : "mousewheel",
            fn2);

        return this;
    };


    // Snap's attr function can be too slow for things like panning/zooming.
    // This is a function to directly update element attributes without going
    // through eve.
    Element.prototype.attribute = function(key, val) {
        if (val === undefined) {
            return this.node.getAttribute(key);
        } else {
            this.node.setAttribute(key, val);
            return this;
        }
    };

    Element.prototype.init_gadfly = function() {
        this.mouseenter(Gadfly.plot_mouseover)
            .mouseleave(Gadfly.plot_mouseout)
            .dblclick(Gadfly.plot_dblclick)
            .mousewheel(Gadfly.guide_background_scroll)
            .drag(Gadfly.guide_background_drag_onmove,
                  Gadfly.guide_background_drag_onstart,
                  Gadfly.guide_background_drag_onend);
        this.mouseenter(function (event) {
            init_pan_zoom(this.plotroot());
        });
        return this;
    };
});


// When the plot is moused over, emphasize the grid lines.
Gadfly.plot_mouseover = function(event) {
    var root = this.plotroot();

    var keyboard_zoom = function(event) {
        if (event.which == 187) { // plus
            increase_zoom_by_position(root, 0.1, true);
        } else if (event.which == 189) { // minus
            increase_zoom_by_position(root, -0.1, true);
        }
    };
    root.data("keyboard_zoom", keyboard_zoom);
    window.addEventListener("keyup", keyboard_zoom);

    var xgridlines = root.select(".xgridlines"),
        ygridlines = root.select(".ygridlines");

    xgridlines.data("unfocused_strokedash",
                    xgridlines.attribute("stroke-dasharray").replace(/(\d)(,|$)/g, "$1mm$2"));
    ygridlines.data("unfocused_strokedash",
                    ygridlines.attribute("stroke-dasharray").replace(/(\d)(,|$)/g, "$1mm$2"));

    // emphasize grid lines
    var destcolor = root.data("focused_xgrid_color");
    xgridlines.attribute("stroke-dasharray", "none")
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    destcolor = root.data("focused_ygrid_color");
    ygridlines.attribute("stroke-dasharray", "none")
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    // reveal zoom slider
    root.select(".zoomslider")
        .animate({opacity: 1.0}, 250);
};

// Reset pan and zoom on double click
Gadfly.plot_dblclick = function(event) {
  set_plot_pan_zoom(this.plotroot(), 0.0, 0.0, 1.0);
};

// Unemphasize grid lines on mouse out.
Gadfly.plot_mouseout = function(event) {
    var root = this.plotroot();

    window.removeEventListener("keyup", root.data("keyboard_zoom"));
    root.data("keyboard_zoom", undefined);

    var xgridlines = root.select(".xgridlines"),
        ygridlines = root.select(".ygridlines");

    var destcolor = root.data("unfocused_xgrid_color");

    xgridlines.attribute("stroke-dasharray", xgridlines.data("unfocused_strokedash"))
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    destcolor = root.data("unfocused_ygrid_color");
    ygridlines.attribute("stroke-dasharray", ygridlines.data("unfocused_strokedash"))
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    // hide zoom slider
    root.select(".zoomslider")
        .animate({opacity: 0.0}, 250);
};


var set_geometry_transform = function(root, tx, ty, scale) {
    var xscalable = root.hasClass("xscalable"),
        yscalable = root.hasClass("yscalable");

    var old_scale = root.data("scale");

    var xscale = xscalable ? scale : 1.0,
        yscale = yscalable ? scale : 1.0;

    tx = xscalable ? tx : 0.0;
    ty = yscalable ? ty : 0.0;

    var t = new Snap.Matrix().translate(tx, ty).scale(xscale, yscale);

    root.selectAll(".geometry, image")
        .forEach(function (element, i) {
            element.transform(t);
        });

    bounds = root.plotbounds();

    if (yscalable) {
        var xfixed_t = new Snap.Matrix().translate(0, ty).scale(1.0, yscale);
        root.selectAll(".xfixed")
            .forEach(function (element, i) {
                element.transform(xfixed_t);
            });

        root.select(".ylabels")
            .transform(xfixed_t)
            .selectAll("text")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var cx = element.asPX("x"),
                        cy = element.asPX("y");
                    var st = element.data("static_transform");
                    unscale_t = new Snap.Matrix();
                    unscale_t.scale(1, 1/scale, cx, cy).add(st);
                    element.transform(unscale_t);

                    var y = cy * scale + ty;
                    element.attr("visibility",
                        bounds.y0 <= y && y <= bounds.y1 ? "visible" : "hidden");
                }
            });
    }

    if (xscalable) {
        var yfixed_t = new Snap.Matrix().translate(tx, 0).scale(xscale, 1.0);
        var xtrans = new Snap.Matrix().translate(tx, 0);
        root.selectAll(".yfixed")
            .forEach(function (element, i) {
                element.transform(yfixed_t);
            });

        root.select(".xlabels")
            .transform(yfixed_t)
            .selectAll("text")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var cx = element.asPX("x"),
                        cy = element.asPX("y");
                    var st = element.data("static_transform");
                    unscale_t = new Snap.Matrix();
                    unscale_t.scale(1/scale, 1, cx, cy).add(st);

                    element.transform(unscale_t);

                    var x = cx * scale + tx;
                    element.attr("visibility",
                        bounds.x0 <= x && x <= bounds.x1 ? "visible" : "hidden");
                    }
            });
    }

    // we must unscale anything that is scale invariance: widths, raiduses, etc.
    var size_attribs = ["font-size"];
    var unscaled_selection = ".geometry, .geometry *";
    if (xscalable) {
        size_attribs.push("rx");
        unscaled_selection += ", .xgridlines";
    }
    if (yscalable) {
        size_attribs.push("ry");
        unscaled_selection += ", .ygridlines";
    }

    root.selectAll(unscaled_selection)
        .forEach(function (element, i) {
            // circle need special help
            if (element.node.nodeName == "circle") {
                var cx = element.attribute("cx"),
                    cy = element.attribute("cy");
                unscale_t = new Snap.Matrix().scale(1/xscale, 1/yscale,
                                                        cx, cy);
                element.transform(unscale_t);
                return;
            }

            for (i in size_attribs) {
                var key = size_attribs[i];
                var val = parseFloat(element.attribute(key));
                if (val !== undefined && val != 0 && !isNaN(val)) {
                    element.attribute(key, val * old_scale / scale);
                }
            }
        });
};


// Find the most appropriate tick scale and update label visibility.
var update_tickscale = function(root, scale, axis) {
    if (!root.hasClass(axis + "scalable")) return;

    var tickscales = root.data(axis + "tickscales");
    var best_tickscale = 1.0;
    var best_tickscale_dist = Infinity;
    for (tickscale in tickscales) {
        var dist = Math.abs(Math.log(tickscale) - Math.log(scale));
        if (dist < best_tickscale_dist) {
            best_tickscale_dist = dist;
            best_tickscale = tickscale;
        }
    }

    if (best_tickscale != root.data(axis + "tickscale")) {
        root.data(axis + "tickscale", best_tickscale);
        var mark_inscale_gridlines = function (element, i) {
            var inscale = element.attr("gadfly:scale") == best_tickscale;
            element.attribute("gadfly:inscale", inscale);
            element.attr("visibility", inscale ? "visible" : "hidden");
        };

        var mark_inscale_labels = function (element, i) {
            var inscale = element.attr("gadfly:scale") == best_tickscale;
            element.attribute("gadfly:inscale", inscale);
            element.attr("visibility", inscale ? "visible" : "hidden");
        };

        root.select("." + axis + "gridlines").selectAll("path").forEach(mark_inscale_gridlines);
        root.select("." + axis + "labels").selectAll("text").forEach(mark_inscale_labels);
    }
};


var set_plot_pan_zoom = function(root, tx, ty, scale) {
    var old_scale = root.data("scale");
    var bounds = root.plotbounds();

    var width = bounds.x1 - bounds.x0,
        height = bounds.y1 - bounds.y0;

    // compute the viewport derived from tx, ty, and scale
    var x_min = -width * scale - (scale * width - width),
        x_max = width * scale,
        y_min = -height * scale - (scale * height - height),
        y_max = height * scale;

    var x0 = bounds.x0 - scale * bounds.x0,
        y0 = bounds.y0 - scale * bounds.y0;

    var tx = Math.max(Math.min(tx - x0, x_max), x_min),
        ty = Math.max(Math.min(ty - y0, y_max), y_min);

    tx += x0;
    ty += y0;

    // when the scale change, we may need to alter which set of
    // ticks is being displayed
    if (scale != old_scale) {
        update_tickscale(root, scale, "x");
        update_tickscale(root, scale, "y");
    }

    set_geometry_transform(root, tx, ty, scale);

    root.data("scale", scale);
    root.data("tx", tx);
    root.data("ty", ty);
};


var scale_centered_translation = function(root, scale) {
    var bounds = root.plotbounds();

    var width = bounds.x1 - bounds.x0,
        height = bounds.y1 - bounds.y0;

    var tx0 = root.data("tx"),
        ty0 = root.data("ty");

    var scale0 = root.data("scale");

    // how off from center the current view is
    var xoff = tx0 - (bounds.x0 * (1 - scale0) + (width * (1 - scale0)) / 2),
        yoff = ty0 - (bounds.y0 * (1 - scale0) + (height * (1 - scale0)) / 2);

    // rescale offsets
    xoff = xoff * scale / scale0;
    yoff = yoff * scale / scale0;

    // adjust for the panel position being scaled
    var x_edge_adjust = bounds.x0 * (1 - scale),
        y_edge_adjust = bounds.y0 * (1 - scale);

    return {
        x: xoff + x_edge_adjust + (width - width * scale) / 2,
        y: yoff + y_edge_adjust + (height - height * scale) / 2
    };
};


// Initialize data for panning zooming if it isn't already.
var init_pan_zoom = function(root) {
    if (root.data("zoompan-ready")) {
        return;
    }

    // The non-scaling-stroke trick. Rather than try to correct for the
    // stroke-width when zooming, we force it to a fixed value.
    var px_per_mm = root.node.getCTM().a;

    // Drag events report deltas in pixels, which we'd like to convert to
    // millimeters.
    root.data("px_per_mm", px_per_mm);

    root.selectAll("path")
        .forEach(function (element, i) {
        sw = element.asPX("stroke-width") * px_per_mm;
        if (sw > 0) {
            element.attribute("stroke-width", sw);
            element.attribute("vector-effect", "non-scaling-stroke");
        }
    });

    // Store ticks labels original tranformation
    root.selectAll(".xlabels > text, .ylabels > text")
        .forEach(function (element, i) {
            var lm = element.transform().localMatrix;
            element.data("static_transform",
                new Snap.Matrix(lm.a, lm.b, lm.c, lm.d, lm.e, lm.f));
        });

    var xgridlines = root.select(".xgridlines");
    var ygridlines = root.select(".ygridlines");
    var xlabels = root.select(".xlabels");
    var ylabels = root.select(".ylabels");

    if (root.data("tx") === undefined) root.data("tx", 0);
    if (root.data("ty") === undefined) root.data("ty", 0);
    if (root.data("scale") === undefined) root.data("scale", 1.0);
    if (root.data("xtickscales") === undefined) {

        // index all the tick scales that are listed
        var xtickscales = {};
        var ytickscales = {};
        var add_x_tick_scales = function (element, i) {
            xtickscales[element.attribute("gadfly:scale")] = true;
        };
        var add_y_tick_scales = function (element, i) {
            ytickscales[element.attribute("gadfly:scale")] = true;
        };

        if (xgridlines) xgridlines.selectAll("path").forEach(add_x_tick_scales);
        if (ygridlines) ygridlines.selectAll("path").forEach(add_y_tick_scales);
        if (xlabels) xlabels.selectAll("text").forEach(add_x_tick_scales);
        if (ylabels) ylabels.selectAll("text").forEach(add_y_tick_scales);

        root.data("xtickscales", xtickscales);
        root.data("ytickscales", ytickscales);
        root.data("xtickscale", 1.0);
    }

    var min_scale = 1.0, max_scale = 1.0;
    for (scale in xtickscales) {
        min_scale = Math.min(min_scale, scale);
        max_scale = Math.max(max_scale, scale);
    }
    for (scale in ytickscales) {
        min_scale = Math.min(min_scale, scale);
        max_scale = Math.max(max_scale, scale);
    }
    root.data("min_scale", min_scale);
    root.data("max_scale", max_scale);

    // store the original positions of labels
    if (xlabels) {
        xlabels.selectAll("text")
               .forEach(function (element, i) {
                   element.data("x", element.asPX("x"));
               });
    }

    if (ylabels) {
        ylabels.selectAll("text")
               .forEach(function (element, i) {
                   element.data("y", element.asPX("y"));
               });
    }

    // mark grid lines and ticks as in or out of scale.
    var mark_inscale = function (element, i) {
        element.attribute("gadfly:inscale", element.attribute("gadfly:scale") == 1.0);
    };

    if (xgridlines) xgridlines.selectAll("path").forEach(mark_inscale);
    if (ygridlines) ygridlines.selectAll("path").forEach(mark_inscale);
    if (xlabels) xlabels.selectAll("text").forEach(mark_inscale);
    if (ylabels) ylabels.selectAll("text").forEach(mark_inscale);

    // figure out the upper ond lower bounds on panning using the maximum
    // and minum grid lines
    var bounds = root.plotbounds();
    var pan_bounds = {
        x0: 0.0,
        y0: 0.0,
        x1: 0.0,
        y1: 0.0
    };

    if (xgridlines) {
        xgridlines
            .selectAll("path")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var bbox = element.node.getBBox();
                    if (bounds.x1 - bbox.x < pan_bounds.x0) {
                        pan_bounds.x0 = bounds.x1 - bbox.x;
                    }
                    if (bounds.x0 - bbox.x > pan_bounds.x1) {
                        pan_bounds.x1 = bounds.x0 - bbox.x;
                    }
                    element.attr("visibility", "visible");
                }
            });
    }

    if (ygridlines) {
        ygridlines
            .selectAll("path")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var bbox = element.node.getBBox();
                    if (bounds.y1 - bbox.y < pan_bounds.y0) {
                        pan_bounds.y0 = bounds.y1 - bbox.y;
                    }
                    if (bounds.y0 - bbox.y > pan_bounds.y1) {
                        pan_bounds.y1 = bounds.y0 - bbox.y;
                    }
                    element.attr("visibility", "visible");
                }
            });
    }

    // nudge these values a little
    pan_bounds.x0 -= 5;
    pan_bounds.x1 += 5;
    pan_bounds.y0 -= 5;
    pan_bounds.y1 += 5;
    root.data("pan_bounds", pan_bounds);

    root.data("zoompan-ready", true)
};


// drag actions, i.e. zooming and panning
var pan_action = {
    start: function(root, x, y, event) {
        root.data("dx", 0);
        root.data("dy", 0);
        root.data("tx0", root.data("tx"));
        root.data("ty0", root.data("ty"));
    },
    update: function(root, dx, dy, x, y, event) {
        var px_per_mm = root.data("px_per_mm");
        dx /= px_per_mm;
        dy /= px_per_mm;

        var tx0 = root.data("tx"),
            ty0 = root.data("ty");

        var dx0 = root.data("dx"),
            dy0 = root.data("dy");

        root.data("dx", dx);
        root.data("dy", dy);

        dx = dx - dx0;
        dy = dy - dy0;

        var tx = tx0 + dx,
            ty = ty0 + dy;

        set_plot_pan_zoom(root, tx, ty, root.data("scale"));
    },
    end: function(root, event) {

    },
    cancel: function(root) {
        set_plot_pan_zoom(root, root.data("tx0"), root.data("ty0"), root.data("scale"));
    }
};

var zoom_box;
var zoom_action = {
    start: function(root, x, y, event) {
        var bounds = root.plotbounds();
        var width = bounds.x1 - bounds.x0,
            height = bounds.y1 - bounds.y0;
        var ratio = width / height;
        var xscalable = root.hasClass("xscalable"),
            yscalable = root.hasClass("yscalable");
        var px_per_mm = root.data("px_per_mm");
        x = xscalable ? x / px_per_mm : bounds.x0;
        y = yscalable ? y / px_per_mm : bounds.y0;
        var w = xscalable ? 0 : width;
        var h = yscalable ? 0 : height;
        zoom_box = root.rect(x, y, w, h).attr({
            "fill": "#000",
            "opacity": 0.25
        });
        zoom_box.data("ratio", ratio);
    },
    update: function(root, dx, dy, x, y, event) {
        var xscalable = root.hasClass("xscalable"),
            yscalable = root.hasClass("yscalable");
        var px_per_mm = root.data("px_per_mm");
        var bounds = root.plotbounds();
        if (yscalable) {
            y /= px_per_mm;
            y = Math.max(bounds.y0, y);
            y = Math.min(bounds.y1, y);
        } else {
            y = bounds.y1;
        }
        if (xscalable) {
            x /= px_per_mm;
            x = Math.max(bounds.x0, x);
            x = Math.min(bounds.x1, x);
        } else {
            x = bounds.x1;
        }

        dx = x - zoom_box.attr("x");
        dy = y - zoom_box.attr("y");
        if (xscalable && yscalable) {
            var ratio = zoom_box.data("ratio");
            var width = Math.min(Math.abs(dx), ratio * Math.abs(dy));
            var height = Math.min(Math.abs(dy), Math.abs(dx) / ratio);
            dx = width * dx / Math.abs(dx);
            dy = height * dy / Math.abs(dy);
        }
        var xoffset = 0,
            yoffset = 0;
        if (dx < 0) {
            xoffset = dx;
            dx = -1 * dx;
        }
        if (dy < 0) {
            yoffset = dy;
            dy = -1 * dy;
        }
        if (isNaN(dy)) {
            dy = 0.0;
        }
        if (isNaN(dx)) {
            dx = 0.0;
        }
        zoom_box.transform("T" + xoffset + "," + yoffset);
        zoom_box.attr("width", dx);
        zoom_box.attr("height", dy);
    },
    end: function(root, event) {
        var xscalable = root.hasClass("xscalable"),
            yscalable = root.hasClass("yscalable");
        var zoom_bounds = zoom_box.getBBox();
        if (zoom_bounds.width * zoom_bounds.height <= 0) {
            return;
        }
        var plot_bounds = root.plotbounds();
        var zoom_factor = 1.0;
        if (yscalable) {
            zoom_factor = (plot_bounds.y1 - plot_bounds.y0) / zoom_bounds.height;
        } else {
            zoom_factor = (plot_bounds.x1 - plot_bounds.x0) / zoom_bounds.width;
        }
        var tx = (root.data("tx") - zoom_bounds.x) * zoom_factor + plot_bounds.x0,
            ty = (root.data("ty") - zoom_bounds.y) * zoom_factor + plot_bounds.y0;
        set_plot_pan_zoom(root, tx, ty, root.data("scale") * zoom_factor);
        zoom_box.remove();
    },
    cancel: function(root) {
        zoom_box.remove();
    }
};


Gadfly.guide_background_drag_onstart = function(x, y, event) {
    var root = this.plotroot();
    var scalable = root.hasClass("xscalable") || root.hasClass("yscalable");
    var zoomable = !event.altKey && !event.ctrlKey && event.shiftKey && scalable;
    var panable = !event.altKey && !event.ctrlKey && !event.shiftKey && scalable;
    var drag_action = zoomable ? zoom_action :
                      panable  ? pan_action :
                                 undefined;
    root.data("drag_action", drag_action);
    if (drag_action) {
        var cancel_drag_action = function(event) {
            if (event.which == 27) { // esc key
                drag_action.cancel(root);
                root.data("drag_action", undefined);
            }
        };
        window.addEventListener("keyup", cancel_drag_action);
        root.data("cancel_drag_action", cancel_drag_action);
        drag_action.start(root, x, y, event);
    }
};


Gadfly.guide_background_drag_onmove = function(dx, dy, x, y, event) {
    var root = this.plotroot();
    var drag_action = root.data("drag_action");
    if (drag_action) {
        drag_action.update(root, dx, dy, x, y, event);
    }
};


Gadfly.guide_background_drag_onend = function(event) {
    var root = this.plotroot();
    window.removeEventListener("keyup", root.data("cancel_drag_action"));
    root.data("cancel_drag_action", undefined);
    var drag_action = root.data("drag_action");
    if (drag_action) {
        drag_action.end(root, event);
    }
    root.data("drag_action", undefined);
};


Gadfly.guide_background_scroll = function(event) {
    if (event.shiftKey) {
        increase_zoom_by_position(this.plotroot(), 0.001 * event.wheelDelta);
        event.preventDefault();
    }
};


Gadfly.zoomslider_button_mouseover = function(event) {
    this.select(".button_logo")
         .animate({fill: this.data("mouseover_color")}, 100);
};


Gadfly.zoomslider_button_mouseout = function(event) {
     this.select(".button_logo")
         .animate({fill: this.data("mouseout_color")}, 100);
};


Gadfly.zoomslider_zoomout_click = function(event) {
    increase_zoom_by_position(this.plotroot(), -0.1, true);
};


Gadfly.zoomslider_zoomin_click = function(event) {
    increase_zoom_by_position(this.plotroot(), 0.1, true);
};


Gadfly.zoomslider_track_click = function(event) {
    // TODO
};


// Map slider position x to scale y using the function y = a*exp(b*x)+c.
// The constants a, b, and c are solved using the constraint that the function
// should go through the points (0; min_scale), (0.5; 1), and (1; max_scale).
var scale_from_slider_position = function(position, min_scale, max_scale) {
    var a = (1 - 2 * min_scale + min_scale * min_scale) / (min_scale + max_scale - 2),
        b = 2 * Math.log((max_scale - 1) / (1 - min_scale)),
        c = (min_scale * max_scale - 1) / (min_scale + max_scale - 2);
    return a * Math.exp(b * position) + c;
}

// inverse of scale_from_slider_position
var slider_position_from_scale = function(scale, min_scale, max_scale) {
    var a = (1 - 2 * min_scale + min_scale * min_scale) / (min_scale + max_scale - 2),
        b = 2 * Math.log((max_scale - 1) / (1 - min_scale)),
        c = (min_scale * max_scale - 1) / (min_scale + max_scale - 2);
    return 1 / b * Math.log((scale - c) / a);
}

var increase_zoom_by_position = function(root, delta_position, animate) {
    var scale = root.data("scale"),
        min_scale = root.data("min_scale"),
        max_scale = root.data("max_scale");
    var position = slider_position_from_scale(scale, min_scale, max_scale);
    position += delta_position;
    scale = scale_from_slider_position(position, min_scale, max_scale);
    set_zoom(root, scale, animate);
}

var set_zoom = function(root, scale, animate) {
    var min_scale = root.data("min_scale"),
        max_scale = root.data("max_scale"),
        old_scale = root.data("scale");
    var new_scale = Math.max(min_scale, Math.min(scale, max_scale));
    if (animate) {
        Snap.animate(
            old_scale,
            new_scale,
            function (new_scale) {
                update_plot_scale(root, new_scale);
            },
            200);
    } else {
        update_plot_scale(root, new_scale);
    }
}


var update_plot_scale = function(root, new_scale) {
    var trans = scale_centered_translation(root, new_scale);
    set_plot_pan_zoom(root, trans.x, trans.y, new_scale);

    root.selectAll(".zoomslider_thumb")
        .forEach(function (element, i) {
            var min_pos = element.data("min_pos"),
                max_pos = element.data("max_pos"),
                min_scale = root.data("min_scale"),
                max_scale = root.data("max_scale");
            var xmid = (min_pos + max_pos) / 2;
            var xpos = slider_position_from_scale(new_scale, min_scale, max_scale);
            element.transform(new Snap.Matrix().translate(
                Math.max(min_pos, Math.min(
                         max_pos, min_pos + (max_pos - min_pos) * xpos)) - xmid, 0));
    });
};


Gadfly.zoomslider_thumb_dragmove = function(dx, dy, x, y, event) {
    var root = this.plotroot();
    var min_pos = this.data("min_pos"),
        max_pos = this.data("max_pos"),
        min_scale = root.data("min_scale"),
        max_scale = root.data("max_scale"),
        old_scale = root.data("old_scale");

    var px_per_mm = root.data("px_per_mm");
    dx /= px_per_mm;
    dy /= px_per_mm;

    var xmid = (min_pos + max_pos) / 2;
    var xpos = slider_position_from_scale(old_scale, min_scale, max_scale) +
                   dx / (max_pos - min_pos);

    // compute the new scale
    var new_scale = scale_from_slider_position(xpos, min_scale, max_scale);
    new_scale = Math.min(max_scale, Math.max(min_scale, new_scale));

    update_plot_scale(root, new_scale);
    event.stopPropagation();
};


Gadfly.zoomslider_thumb_dragstart = function(x, y, event) {
    this.animate({fill: this.data("mouseover_color")}, 100);
    var root = this.plotroot();

    // keep track of what the scale was when we started dragging
    root.data("old_scale", root.data("scale"));
    event.stopPropagation();
};


Gadfly.zoomslider_thumb_dragend = function(event) {
    this.animate({fill: this.data("mouseout_color")}, 100);
    event.stopPropagation();
};


var toggle_color_class = function(root, color_class, ison) {
    var guides = root.selectAll(".guide." + color_class + ",.guide ." + color_class);
    var geoms = root.selectAll(".geometry." + color_class + ",.geometry ." + color_class);
    if (ison) {
        guides.animate({opacity: 0.5}, 250);
        geoms.animate({opacity: 0.0}, 250);
    } else {
        guides.animate({opacity: 1.0}, 250);
        geoms.animate({opacity: 1.0}, 250);
    }
};


Gadfly.colorkey_swatch_click = function(event) {
    var root = this.plotroot();
    var color_class = this.data("color_class");

    if (event.shiftKey) {
        root.selectAll(".colorkey text")
            .forEach(function (element) {
                var other_color_class = element.data("color_class");
                if (other_color_class != color_class) {
                    toggle_color_class(root, other_color_class,
                                       element.attr("opacity") == 1.0);
                }
            });
    } else {
        toggle_color_class(root, color_class, this.attr("opacity") == 1.0);
    }
};


return Gadfly;

}));


//@ sourceURL=gadfly.js

(function (glob, factory) {
    // AMD support
      if (typeof require === "function" && typeof define === "function" && define.amd) {
        require(["Snap.svg", "Gadfly"], function (Snap, Gadfly) {
            factory(Snap, Gadfly);
        });
      } else {
          factory(glob.Snap, glob.Gadfly);
      }
})(window, function (Snap, Gadfly) {
    var fig = Snap("#fig-8cf350439686410badaaa561ba84a807");
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-4")
   .drag(function() {}, function() {}, function() {});
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-8")
   .init_gadfly();
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-11")
   .plotroot().data("unfocused_ygrid_color", "#D0D0E0")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-11")
   .plotroot().data("focused_ygrid_color", "#A0A0A0")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-12")
   .plotroot().data("unfocused_xgrid_color", "#D0D0E0")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-12")
   .plotroot().data("focused_xgrid_color", "#A0A0A0")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-19")
   .data("mouseover_color", "#CD5C5C")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-19")
   .data("mouseout_color", "#6A6A6A")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-19")
   .click(Gadfly.zoomslider_zoomin_click)
.mouseenter(Gadfly.zoomslider_button_mouseover)
.mouseleave(Gadfly.zoomslider_button_mouseout)
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-21")
   .data("max_pos", 96.01)
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-21")
   .data("min_pos", 79.01)
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-21")
   .click(Gadfly.zoomslider_track_click);
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-22")
   .data("max_pos", 96.01)
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-22")
   .data("min_pos", 79.01)
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-22")
   .data("mouseover_color", "#CD5C5C")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-22")
   .data("mouseout_color", "#6A6A6A")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-22")
   .drag(Gadfly.zoomslider_thumb_dragmove,
     Gadfly.zoomslider_thumb_dragstart,
     Gadfly.zoomslider_thumb_dragend)
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-23")
   .data("mouseover_color", "#CD5C5C")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-23")
   .data("mouseout_color", "#6A6A6A")
;
fig.select("#fig-8cf350439686410badaaa561ba84a807-element-23")
   .click(Gadfly.zoomslider_zoomout_click)
.mouseenter(Gadfly.zoomslider_button_mouseover)
.mouseleave(Gadfly.zoomslider_button_mouseout)
;
    });
]]> </script>
</svg>




Looking for the full code without having to read through the entire document? We'll here you go :)


```julia
using StateSpace
using Distributions
using Gadfly
using Colors

#Set the Parameters
elevation_angle = 45.0
muzzle_speed = 100.0 
initial_velocity = [muzzle_speed*cos(deg2rad(elevation_angle)), muzzle_speed*sin(deg2rad(elevation_angle))]
gravAcc = 9.81
initial_location = [0.0, 0.0]
Δt = 0.1

#Functions describing the position of canonball
x_pos(x0::Float64, Vx::Float64, t::Float64) = x0 + Vx*t
y_pos(y0::Float64, Vy::Float64, t::Float64, g::Float64) = y0 + Vy*t - (g * t^2)/2
#Function to describe the evolution of the velocity in the vertical direction
velocityY(Vy::Float64, t::Float64, g::Float64) = Vy - g * t

#Give variances of the observation noise for the position and velocity
x_pos_var = 200.0
y_pos_var = 200.0
Vx_var = 1.0
Vy_var = 1.0

#Set the number of observations and preallocate vectors to store true and noisy measurement values
numObs = 145
x_pos_true = Vector{Float64}(numObs)
x_pos_obs = Vector{Float64}(numObs)
y_pos_true = Vector{Float64}(numObs)
y_pos_obs = Vector{Float64}(numObs)

Vx_true = Vector{Float64}(numObs)
Vx_obs = Vector{Float64}(numObs)
Vy_true = Vector{Float64}(numObs)
Vy_obs = Vector{Float64}(numObs)

#Generate the data (true values and noisy observations)
for i in 1:numObs
    x_pos_true[i] = x_pos(initial_location[1], initial_velocity[1], (i-1)*Δt)
    y_pos_true[i] = y_pos(initial_location[2], initial_velocity[2], (i-1)*Δt, gravAcc)
    Vx_true[i] = initial_velocity[1]
    Vy_true[i] = velocityY(initial_velocity[2], (i-1)*Δt, gravAcc)

    x_pos_obs[i] = x_pos_true[i] + randn() * sqrt(x_pos_var)
    y_pos_obs[i] = y_pos_true[i] + randn() * sqrt(y_pos_var)
    Vx_obs[i] = Vx_true[i] + randn() * sqrt(Vx_var)
    Vy_obs[i] = Vy_true[i] + randn() * sqrt(Vy_var)
end
#Create the observations vector for the Kalman filter
observations = [x_pos_obs Vx_obs y_pos_obs Vy_obs]'

#Describe the system parameters
process_matrix = [[1.0, Δt, 0.0, 0.0] [0.0, 1.0, 0.0, 0.0] [0.0, 0.0, 1.0, Δt] [0.0, 0.0, 0.0, 1.0]]'
process_covariance = 0.01*eye(4)
observation_matrix = eye(4)
observation_covariance = 0.2*eye(4)
control_matrix = [[0.0, 0.0, 0.0, 0.0] [0.0, 0.0, 0.0, 0.0] [0.0, 0.0, 1.0, 0.0] [0.0, 0.0, 0.0, 1.0]]
control_input = [0.0, 0.0, -(gravAcc * Δt^2)/2, -(gravAcc * Δt)]

#Create an instance of the LKF with the control inputs
linCISMM = LinearGaussianCISSM(process_matrix, process_covariance, observation_matrix, observation_covariance, control_matrix, control_input)

#Set Initial Guess
initial_guess_state = [0.0, initial_velocity[1], 500.0, initial_velocity[2]]
initial_guess_covariance = eye(4)
initial_guess = MvNormal(initial_guess_state, initial_guess_covariance)

#Execute Kalman Filter
filtered_state = filter(linCISMM, observations, initial_guess)

#Plot Filtered results
x_filt = Vector{Float64}(numObs)
y_filt = Vector{Float64}(numObs)
for i in 1:numObs
    current_state = filtered_state.state[i]
    x_filt[i] = current_state.μ[1]
    y_filt[i] = current_state.μ[3]
end

n = 3
getColors = distinguishable_colors(n, Color[LCHab(70, 60, 240)],
                                   transform=c -> deuteranopic(c, 0.5),
                                   lchoices=Float64[65, 70, 75, 80],
                                   cchoices=Float64[0, 50, 60, 70],
                                   hchoices=linspace(0, 330, 24))

cannonball_plot = plot(
    layer(x=x_pos_true, y=y_pos_true, Geom.line, Theme(default_color=getColors[3])),
    layer(x=[initial_guess_state[1]; x_filt], y=[initial_guess_state[3]; y_filt], Geom.line, Theme(default_color=getColors[1])),
    layer(x=x_pos_obs, y=y_pos_obs, Geom.point, Theme(default_color=getColors[2])),
    Guide.xlabel("X position"), Guide.ylabel("Y position"),
    Guide.manual_color_key("Colour Key",["Filtered Estimate", "Measurements","True Value "],[getColors[1],getColors[2],getColors[3]]),
    Guide.title("Measurement of a Canonball in Flight")
    )
```




<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:gadfly="http://www.gadflyjl.org/ns"
     version="1.2"
     width="141.42mm" height="100mm" viewBox="0 0 141.42 100"
     stroke="none"
     fill="#000000"
     stroke-width="0.3"
     font-size="3.88"

     id="fig-f679eb34e3304a2b9eea5b9025b9d353">
<g class="plotroot xscalable yscalable" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-1">
  <g font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" fill="#564A55" stroke="#000000" stroke-opacity="0.000" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-2">
    <text x="66.38" y="88.39" text-anchor="middle" dy="0.6em">X position</text>
  </g>
  <g class="guide xlabels" font-size="2.82" font-family="'PT Sans Caption','Helvetica Neue','Helvetica',sans-serif" fill="#6C606B" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-3">
    <text x="-93.61" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-2000</text>
    <text x="-64.52" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-1500</text>
    <text x="-35.43" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-1000</text>
    <text x="-6.34" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">-500</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">0</text>
    <text x="51.83" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">500</text>
    <text x="80.92" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">1000</text>
    <text x="110.01" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="visible">1500</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">2000</text>
    <text x="168.18" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">2500</text>
    <text x="197.27" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">3000</text>
    <text x="226.36" y="84.39" text-anchor="middle" gadfly:scale="1.0" visibility="hidden">3500</text>
    <text x="-64.52" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1500</text>
    <text x="-61.61" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1450</text>
    <text x="-58.7" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1400</text>
    <text x="-55.79" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1350</text>
    <text x="-52.88" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1300</text>
    <text x="-49.97" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1250</text>
    <text x="-47.07" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1200</text>
    <text x="-44.16" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1150</text>
    <text x="-41.25" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1100</text>
    <text x="-38.34" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1050</text>
    <text x="-35.43" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-1000</text>
    <text x="-32.52" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-950</text>
    <text x="-29.61" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-900</text>
    <text x="-26.7" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-850</text>
    <text x="-23.8" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-800</text>
    <text x="-20.89" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-750</text>
    <text x="-17.98" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-700</text>
    <text x="-15.07" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-650</text>
    <text x="-12.16" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-600</text>
    <text x="-9.25" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-550</text>
    <text x="-6.34" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-500</text>
    <text x="-3.43" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-450</text>
    <text x="-0.53" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-400</text>
    <text x="2.38" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-350</text>
    <text x="5.29" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-300</text>
    <text x="8.2" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-250</text>
    <text x="11.11" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-200</text>
    <text x="14.02" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-150</text>
    <text x="16.93" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-100</text>
    <text x="19.84" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">-50</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">0</text>
    <text x="25.65" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">50</text>
    <text x="28.56" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">100</text>
    <text x="31.47" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">150</text>
    <text x="34.38" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">200</text>
    <text x="37.29" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">250</text>
    <text x="40.2" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">300</text>
    <text x="43.11" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">350</text>
    <text x="46.02" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">400</text>
    <text x="48.92" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">450</text>
    <text x="51.83" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">500</text>
    <text x="54.74" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">550</text>
    <text x="57.65" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">600</text>
    <text x="60.56" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">650</text>
    <text x="63.47" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">700</text>
    <text x="66.38" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">750</text>
    <text x="69.29" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">800</text>
    <text x="72.19" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">850</text>
    <text x="75.1" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">900</text>
    <text x="78.01" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">950</text>
    <text x="80.92" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1000</text>
    <text x="83.83" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1050</text>
    <text x="86.74" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1100</text>
    <text x="89.65" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1150</text>
    <text x="92.56" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1200</text>
    <text x="95.46" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1250</text>
    <text x="98.37" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1300</text>
    <text x="101.28" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1350</text>
    <text x="104.19" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1400</text>
    <text x="107.1" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1450</text>
    <text x="110.01" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1500</text>
    <text x="112.92" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1550</text>
    <text x="115.83" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1600</text>
    <text x="118.73" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1650</text>
    <text x="121.64" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1700</text>
    <text x="124.55" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1750</text>
    <text x="127.46" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1800</text>
    <text x="130.37" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1850</text>
    <text x="133.28" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1900</text>
    <text x="136.19" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">1950</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2000</text>
    <text x="142" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2050</text>
    <text x="144.91" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2100</text>
    <text x="147.82" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2150</text>
    <text x="150.73" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2200</text>
    <text x="153.64" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2250</text>
    <text x="156.55" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2300</text>
    <text x="159.46" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2350</text>
    <text x="162.37" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2400</text>
    <text x="165.27" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2450</text>
    <text x="168.18" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2500</text>
    <text x="171.09" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2550</text>
    <text x="174" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2600</text>
    <text x="176.91" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2650</text>
    <text x="179.82" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2700</text>
    <text x="182.73" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2750</text>
    <text x="185.64" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2800</text>
    <text x="188.54" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2850</text>
    <text x="191.45" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2900</text>
    <text x="194.36" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">2950</text>
    <text x="197.27" y="84.39" text-anchor="middle" gadfly:scale="10.0" visibility="hidden">3000</text>
    <text x="-93.61" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">-2000</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">0</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">2000</text>
    <text x="255.45" y="84.39" text-anchor="middle" gadfly:scale="0.5" visibility="hidden">4000</text>
    <text x="-64.52" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1500</text>
    <text x="-58.7" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1400</text>
    <text x="-52.88" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1300</text>
    <text x="-47.07" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1200</text>
    <text x="-41.25" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1100</text>
    <text x="-35.43" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-1000</text>
    <text x="-29.61" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-900</text>
    <text x="-23.8" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-800</text>
    <text x="-17.98" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-700</text>
    <text x="-12.16" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-600</text>
    <text x="-6.34" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-500</text>
    <text x="-0.53" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-400</text>
    <text x="5.29" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-300</text>
    <text x="11.11" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-200</text>
    <text x="16.93" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">-100</text>
    <text x="22.75" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">0</text>
    <text x="28.56" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">100</text>
    <text x="34.38" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">200</text>
    <text x="40.2" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">300</text>
    <text x="46.02" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">400</text>
    <text x="51.83" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">500</text>
    <text x="57.65" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">600</text>
    <text x="63.47" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">700</text>
    <text x="69.29" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">800</text>
    <text x="75.1" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">900</text>
    <text x="80.92" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1000</text>
    <text x="86.74" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1100</text>
    <text x="92.56" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1200</text>
    <text x="98.37" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1300</text>
    <text x="104.19" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1400</text>
    <text x="110.01" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1500</text>
    <text x="115.83" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1600</text>
    <text x="121.64" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1700</text>
    <text x="127.46" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1800</text>
    <text x="133.28" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">1900</text>
    <text x="139.1" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2000</text>
    <text x="144.91" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2100</text>
    <text x="150.73" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2200</text>
    <text x="156.55" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2300</text>
    <text x="162.37" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2400</text>
    <text x="168.18" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2500</text>
    <text x="174" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2600</text>
    <text x="179.82" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2700</text>
    <text x="185.64" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2800</text>
    <text x="191.45" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">2900</text>
    <text x="197.27" y="84.39" text-anchor="middle" gadfly:scale="5.0" visibility="hidden">3000</text>
  </g>
  <g class="guide colorkey" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-4">
    <g fill="#4C404B" font-size="2.82" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-5">
      <text x="115.82" y="44.85" dy="0.35em">Filtered Estimate</text>
      <text x="115.82" y="48.48" dy="0.35em">Measurements</text>
      <text x="115.82" y="52.1" dy="0.35em">True Value </text>
    </g>
    <g stroke="#000000" stroke-opacity="0.000" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-6">
      <rect x="113.01" y="43.94" width="1.81" height="1.81" fill="#00BFFF"/>
      <rect x="113.01" y="47.57" width="1.81" height="1.81" fill="#D4CA3A"/>
      <rect x="113.01" y="51.2" width="1.81" height="1.81" fill="#FF5EA0"/>
    </g>
    <g fill="#362A35" font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" stroke="#000000" stroke-opacity="0.000" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-7">
      <text x="113.01" y="41.03">Colour Key</text>
    </g>
  </g>
  <g clip-path="url(#fig-f679eb34e3304a2b9eea5b9025b9d353-element-9)" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-8">
    <g pointer-events="visible" opacity="1" fill="#000000" fill-opacity="0.000" stroke="#000000" stroke-opacity="0.000" class="guide background" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-10">
      <rect x="20.75" y="12.61" width="91.26" height="68.1"/>
    </g>
    <g class="guide ygridlines xfixed" stroke-dasharray="0.5,0.5" stroke-width="0.2" stroke="#D0D0E0" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-11">
      <path fill="none" d="M20.75,153.5 L 112.01 153.5" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,142.82 L 112.01 142.82" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,132.13 L 112.01 132.13" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,121.45 L 112.01 121.45" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,110.77 L 112.01 110.77" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,100.08 L 112.01 100.08" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,89.4 L 112.01 89.4" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,78.71 L 112.01 78.71" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,57.35 L 112.01 57.35" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,46.66 L 112.01 46.66" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,35.98 L 112.01 35.98" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,25.3 L 112.01 25.3" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,14.61 L 112.01 14.61" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M20.75,3.93 L 112.01 3.93" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-6.76 L 112.01 -6.76" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-17.44 L 112.01 -17.44" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-28.12 L 112.01 -28.12" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-49.49 L 112.01 -49.49" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-60.18 L 112.01 -60.18" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M20.75,142.82 L 112.01 142.82" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,140.68 L 112.01 140.68" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,138.54 L 112.01 138.54" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,136.41 L 112.01 136.41" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,134.27 L 112.01 134.27" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,132.13 L 112.01 132.13" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,130 L 112.01 130" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,127.86 L 112.01 127.86" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,125.72 L 112.01 125.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,123.59 L 112.01 123.59" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,121.45 L 112.01 121.45" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,119.31 L 112.01 119.31" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,117.18 L 112.01 117.18" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,115.04 L 112.01 115.04" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,112.9 L 112.01 112.9" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,110.77 L 112.01 110.77" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,108.63 L 112.01 108.63" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,106.49 L 112.01 106.49" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,104.36 L 112.01 104.36" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,102.22 L 112.01 102.22" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,100.08 L 112.01 100.08" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,97.95 L 112.01 97.95" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,95.81 L 112.01 95.81" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,93.67 L 112.01 93.67" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,91.54 L 112.01 91.54" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,89.4 L 112.01 89.4" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,87.26 L 112.01 87.26" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,85.13 L 112.01 85.13" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,82.99 L 112.01 82.99" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,80.85 L 112.01 80.85" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,78.71 L 112.01 78.71" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,76.58 L 112.01 76.58" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,74.44 L 112.01 74.44" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,72.3 L 112.01 72.3" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,70.17 L 112.01 70.17" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,65.89 L 112.01 65.89" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,63.76 L 112.01 63.76" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,61.62 L 112.01 61.62" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,59.48 L 112.01 59.48" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,57.35 L 112.01 57.35" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,55.21 L 112.01 55.21" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,53.07 L 112.01 53.07" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,50.94 L 112.01 50.94" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,48.8 L 112.01 48.8" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,46.66 L 112.01 46.66" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,44.53 L 112.01 44.53" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,42.39 L 112.01 42.39" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,40.25 L 112.01 40.25" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,38.12 L 112.01 38.12" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,35.98 L 112.01 35.98" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,33.84 L 112.01 33.84" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,31.71 L 112.01 31.71" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,29.57 L 112.01 29.57" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,27.43 L 112.01 27.43" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,25.3 L 112.01 25.3" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,23.16 L 112.01 23.16" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,21.02 L 112.01 21.02" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,18.89 L 112.01 18.89" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,16.75 L 112.01 16.75" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,14.61 L 112.01 14.61" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,12.47 L 112.01 12.47" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,10.34 L 112.01 10.34" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,8.2 L 112.01 8.2" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,6.06 L 112.01 6.06" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,3.93 L 112.01 3.93" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,1.79 L 112.01 1.79" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-0.35 L 112.01 -0.35" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-2.48 L 112.01 -2.48" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-4.62 L 112.01 -4.62" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-6.76 L 112.01 -6.76" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-8.89 L 112.01 -8.89" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-11.03 L 112.01 -11.03" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-13.17 L 112.01 -13.17" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-15.3 L 112.01 -15.3" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-17.44 L 112.01 -17.44" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-19.58 L 112.01 -19.58" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-21.71 L 112.01 -21.71" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-23.85 L 112.01 -23.85" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-25.99 L 112.01 -25.99" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-28.12 L 112.01 -28.12" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-30.26 L 112.01 -30.26" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-32.4 L 112.01 -32.4" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-34.53 L 112.01 -34.53" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-36.67 L 112.01 -36.67" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-40.94 L 112.01 -40.94" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-43.08 L 112.01 -43.08" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-45.22 L 112.01 -45.22" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-47.35 L 112.01 -47.35" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-49.49 L 112.01 -49.49" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M20.75,174.87 L 112.01 174.87" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,-145.65 L 112.01 -145.65" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M20.75,142.82 L 112.01 142.82" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,137.48 L 112.01 137.48" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,132.13 L 112.01 132.13" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,126.79 L 112.01 126.79" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,121.45 L 112.01 121.45" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,116.11 L 112.01 116.11" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,110.77 L 112.01 110.77" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,105.42 L 112.01 105.42" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,100.08 L 112.01 100.08" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,94.74 L 112.01 94.74" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,89.4 L 112.01 89.4" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,84.06 L 112.01 84.06" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,78.71 L 112.01 78.71" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,73.37 L 112.01 73.37" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,68.03 L 112.01 68.03" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,62.69 L 112.01 62.69" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,57.35 L 112.01 57.35" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,52.01 L 112.01 52.01" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,46.66 L 112.01 46.66" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,41.32 L 112.01 41.32" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,35.98 L 112.01 35.98" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,30.64 L 112.01 30.64" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,25.3 L 112.01 25.3" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,19.95 L 112.01 19.95" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,14.61 L 112.01 14.61" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,9.27 L 112.01 9.27" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,3.93 L 112.01 3.93" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-1.41 L 112.01 -1.41" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-6.76 L 112.01 -6.76" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-12.1 L 112.01 -12.1" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-17.44 L 112.01 -17.44" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-22.78 L 112.01 -22.78" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-28.12 L 112.01 -28.12" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-33.47 L 112.01 -33.47" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-38.81 L 112.01 -38.81" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-44.15 L 112.01 -44.15" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M20.75,-49.49 L 112.01 -49.49" gadfly:scale="5.0" visibility="hidden"/>
    </g>
    <g class="guide xgridlines yfixed" stroke-dasharray="0.5,0.5" stroke-width="0.2" stroke="#D0D0E0" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-12">
      <path fill="none" d="M-93.61,12.61 L -93.61 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-64.52,12.61 L -64.52 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-35.43,12.61 L -35.43 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-6.34,12.61 L -6.34 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M51.83,12.61 L 51.83 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M80.92,12.61 L 80.92 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M110.01,12.61 L 110.01 80.72" gadfly:scale="1.0" visibility="visible"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M168.18,12.61 L 168.18 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M197.27,12.61 L 197.27 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M226.36,12.61 L 226.36 80.72" gadfly:scale="1.0" visibility="hidden"/>
      <path fill="none" d="M-64.52,12.61 L -64.52 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-61.61,12.61 L -61.61 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-58.7,12.61 L -58.7 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-55.79,12.61 L -55.79 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-52.88,12.61 L -52.88 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-49.97,12.61 L -49.97 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-47.07,12.61 L -47.07 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-44.16,12.61 L -44.16 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-41.25,12.61 L -41.25 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-38.34,12.61 L -38.34 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-35.43,12.61 L -35.43 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-32.52,12.61 L -32.52 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-29.61,12.61 L -29.61 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-26.7,12.61 L -26.7 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-23.8,12.61 L -23.8 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-20.89,12.61 L -20.89 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-17.98,12.61 L -17.98 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-15.07,12.61 L -15.07 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-12.16,12.61 L -12.16 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-9.25,12.61 L -9.25 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-6.34,12.61 L -6.34 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-3.43,12.61 L -3.43 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-0.53,12.61 L -0.53 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M2.38,12.61 L 2.38 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M5.29,12.61 L 5.29 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M8.2,12.61 L 8.2 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M11.11,12.61 L 11.11 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M14.02,12.61 L 14.02 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M16.93,12.61 L 16.93 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M19.84,12.61 L 19.84 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M25.65,12.61 L 25.65 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M28.56,12.61 L 28.56 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M31.47,12.61 L 31.47 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M34.38,12.61 L 34.38 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M37.29,12.61 L 37.29 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M40.2,12.61 L 40.2 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M43.11,12.61 L 43.11 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M46.02,12.61 L 46.02 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M48.92,12.61 L 48.92 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M51.83,12.61 L 51.83 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M54.74,12.61 L 54.74 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M57.65,12.61 L 57.65 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M60.56,12.61 L 60.56 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M63.47,12.61 L 63.47 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M66.38,12.61 L 66.38 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M69.29,12.61 L 69.29 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M72.19,12.61 L 72.19 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M75.1,12.61 L 75.1 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M78.01,12.61 L 78.01 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M80.92,12.61 L 80.92 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M83.83,12.61 L 83.83 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M86.74,12.61 L 86.74 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M89.65,12.61 L 89.65 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M92.56,12.61 L 92.56 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M95.46,12.61 L 95.46 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M98.37,12.61 L 98.37 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M101.28,12.61 L 101.28 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M104.19,12.61 L 104.19 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M107.1,12.61 L 107.1 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M110.01,12.61 L 110.01 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M112.92,12.61 L 112.92 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M115.83,12.61 L 115.83 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M118.73,12.61 L 118.73 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M121.64,12.61 L 121.64 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M124.55,12.61 L 124.55 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M127.46,12.61 L 127.46 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M130.37,12.61 L 130.37 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M133.28,12.61 L 133.28 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M136.19,12.61 L 136.19 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M142,12.61 L 142 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M144.91,12.61 L 144.91 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M147.82,12.61 L 147.82 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M150.73,12.61 L 150.73 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M153.64,12.61 L 153.64 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M156.55,12.61 L 156.55 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M159.46,12.61 L 159.46 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M162.37,12.61 L 162.37 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M165.27,12.61 L 165.27 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M168.18,12.61 L 168.18 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M171.09,12.61 L 171.09 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M174,12.61 L 174 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M176.91,12.61 L 176.91 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M179.82,12.61 L 179.82 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M182.73,12.61 L 182.73 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M185.64,12.61 L 185.64 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M188.54,12.61 L 188.54 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M191.45,12.61 L 191.45 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M194.36,12.61 L 194.36 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M197.27,12.61 L 197.27 80.72" gadfly:scale="10.0" visibility="hidden"/>
      <path fill="none" d="M-93.61,12.61 L -93.61 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M255.45,12.61 L 255.45 80.72" gadfly:scale="0.5" visibility="hidden"/>
      <path fill="none" d="M-64.52,12.61 L -64.52 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-58.7,12.61 L -58.7 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-52.88,12.61 L -52.88 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-47.07,12.61 L -47.07 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-41.25,12.61 L -41.25 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-35.43,12.61 L -35.43 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-29.61,12.61 L -29.61 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-23.8,12.61 L -23.8 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-17.98,12.61 L -17.98 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-12.16,12.61 L -12.16 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-6.34,12.61 L -6.34 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M-0.53,12.61 L -0.53 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M5.29,12.61 L 5.29 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M11.11,12.61 L 11.11 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M16.93,12.61 L 16.93 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M22.75,12.61 L 22.75 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M28.56,12.61 L 28.56 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M34.38,12.61 L 34.38 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M40.2,12.61 L 40.2 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M46.02,12.61 L 46.02 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M51.83,12.61 L 51.83 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M57.65,12.61 L 57.65 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M63.47,12.61 L 63.47 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M69.29,12.61 L 69.29 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M75.1,12.61 L 75.1 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M80.92,12.61 L 80.92 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M86.74,12.61 L 86.74 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M92.56,12.61 L 92.56 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M98.37,12.61 L 98.37 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M104.19,12.61 L 104.19 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M110.01,12.61 L 110.01 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M115.83,12.61 L 115.83 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M121.64,12.61 L 121.64 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M127.46,12.61 L 127.46 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M133.28,12.61 L 133.28 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M139.1,12.61 L 139.1 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M144.91,12.61 L 144.91 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M150.73,12.61 L 150.73 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M156.55,12.61 L 156.55 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M162.37,12.61 L 162.37 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M168.18,12.61 L 168.18 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M174,12.61 L 174 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M179.82,12.61 L 179.82 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M185.64,12.61 L 185.64 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M191.45,12.61 L 191.45 80.72" gadfly:scale="5.0" visibility="hidden"/>
      <path fill="none" d="M197.27,12.61 L 197.27 80.72" gadfly:scale="5.0" visibility="hidden"/>
    </g>
    <g class="plotpanel" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-13">
      <g class="geometry" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-14">
        <g class="color_RGBA{Float32}(0.83092886f0,0.79346967f0,0.22566344f0,1.0f0)" stroke="#FFFFFF" stroke-width="0.3" fill="#D4CA3A" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-15">
          <circle cx="23.65" cy="67.82" r="0.9"/>
          <circle cx="23.16" cy="67.37" r="0.9"/>
          <circle cx="22.9" cy="63.82" r="0.9"/>
          <circle cx="22.79" cy="66.93" r="0.9"/>
          <circle cx="23.14" cy="62.73" r="0.9"/>
          <circle cx="23.86" cy="64.91" r="0.9"/>
          <circle cx="25.81" cy="64.64" r="0.9"/>
          <circle cx="26.82" cy="62.91" r="0.9"/>
          <circle cx="26.69" cy="61.73" r="0.9"/>
          <circle cx="27.28" cy="59.4" r="0.9"/>
          <circle cx="27.67" cy="60.81" r="0.9"/>
          <circle cx="27.57" cy="59.28" r="0.9"/>
          <circle cx="24.93" cy="59.61" r="0.9"/>
          <circle cx="27.25" cy="59.6" r="0.9"/>
          <circle cx="27.46" cy="55.7" r="0.9"/>
          <circle cx="28.33" cy="59.6" r="0.9"/>
          <circle cx="30.7" cy="58.54" r="0.9"/>
          <circle cx="31.59" cy="54.37" r="0.9"/>
          <circle cx="31.16" cy="54.99" r="0.9"/>
          <circle cx="30.14" cy="57.04" r="0.9"/>
          <circle cx="31.49" cy="54.52" r="0.9"/>
          <circle cx="33.39" cy="52.12" r="0.9"/>
          <circle cx="33.39" cy="56.97" r="0.9"/>
          <circle cx="31.69" cy="52.23" r="0.9"/>
          <circle cx="32.74" cy="54.58" r="0.9"/>
          <circle cx="34.12" cy="51.76" r="0.9"/>
          <circle cx="34" cy="53.62" r="0.9"/>
          <circle cx="33.55" cy="53.11" r="0.9"/>
          <circle cx="33.9" cy="50.62" r="0.9"/>
          <circle cx="35.4" cy="51.85" r="0.9"/>
          <circle cx="36.56" cy="51.85" r="0.9"/>
          <circle cx="37.16" cy="49.98" r="0.9"/>
          <circle cx="36.55" cy="47.53" r="0.9"/>
          <circle cx="34.99" cy="46.4" r="0.9"/>
          <circle cx="37.1" cy="50.9" r="0.9"/>
          <circle cx="37.12" cy="47.66" r="0.9"/>
          <circle cx="37.31" cy="50.96" r="0.9"/>
          <circle cx="37.81" cy="47.62" r="0.9"/>
          <circle cx="38.46" cy="47.48" r="0.9"/>
          <circle cx="39.28" cy="46.1" r="0.9"/>
          <circle cx="37.52" cy="47.32" r="0.9"/>
          <circle cx="39.37" cy="45.71" r="0.9"/>
          <circle cx="38.17" cy="45.17" r="0.9"/>
          <circle cx="40.84" cy="47.15" r="0.9"/>
          <circle cx="39.68" cy="48.36" r="0.9"/>
          <circle cx="41.96" cy="45.85" r="0.9"/>
          <circle cx="41.33" cy="41.74" r="0.9"/>
          <circle cx="42.6" cy="44.77" r="0.9"/>
          <circle cx="42.41" cy="44.71" r="0.9"/>
          <circle cx="42.34" cy="44.57" r="0.9"/>
          <circle cx="41.65" cy="43.94" r="0.9"/>
          <circle cx="43.88" cy="42.6" r="0.9"/>
          <circle cx="44.58" cy="43.49" r="0.9"/>
          <circle cx="45.46" cy="42.92" r="0.9"/>
          <circle cx="44.56" cy="42.48" r="0.9"/>
          <circle cx="46.13" cy="42.37" r="0.9"/>
          <circle cx="45.73" cy="44.97" r="0.9"/>
          <circle cx="45.92" cy="43.97" r="0.9"/>
          <circle cx="45.76" cy="40.6" r="0.9"/>
          <circle cx="47.45" cy="40.54" r="0.9"/>
          <circle cx="47.08" cy="43.89" r="0.9"/>
          <circle cx="47.08" cy="41.7" r="0.9"/>
          <circle cx="49.02" cy="39.81" r="0.9"/>
          <circle cx="47.16" cy="41.55" r="0.9"/>
          <circle cx="48.17" cy="45.26" r="0.9"/>
          <circle cx="49.28" cy="40.26" r="0.9"/>
          <circle cx="48.6" cy="39.81" r="0.9"/>
          <circle cx="50.4" cy="40.88" r="0.9"/>
          <circle cx="50.85" cy="40.36" r="0.9"/>
          <circle cx="51.59" cy="41.34" r="0.9"/>
          <circle cx="52.1" cy="42.27" r="0.9"/>
          <circle cx="51.88" cy="41.73" r="0.9"/>
          <circle cx="50.91" cy="39.8" r="0.9"/>
          <circle cx="51.54" cy="41.14" r="0.9"/>
          <circle cx="53.52" cy="40.38" r="0.9"/>
          <circle cx="52.85" cy="39.85" r="0.9"/>
          <circle cx="53.74" cy="41.29" r="0.9"/>
          <circle cx="54.43" cy="39.75" r="0.9"/>
          <circle cx="55.04" cy="40.19" r="0.9"/>
          <circle cx="53.28" cy="40.68" r="0.9"/>
          <circle cx="56.11" cy="41.91" r="0.9"/>
          <circle cx="56.82" cy="41.48" r="0.9"/>
          <circle cx="57.02" cy="42.38" r="0.9"/>
          <circle cx="57.49" cy="38.41" r="0.9"/>
          <circle cx="57.27" cy="41.87" r="0.9"/>
          <circle cx="57.7" cy="41.93" r="0.9"/>
          <circle cx="58.04" cy="39.06" r="0.9"/>
          <circle cx="57.67" cy="41.09" r="0.9"/>
          <circle cx="57.56" cy="42.83" r="0.9"/>
          <circle cx="60.68" cy="39.94" r="0.9"/>
          <circle cx="60.07" cy="42.44" r="0.9"/>
          <circle cx="60.91" cy="42.88" r="0.9"/>
          <circle cx="59.61" cy="41.56" r="0.9"/>
          <circle cx="60.08" cy="42.75" r="0.9"/>
          <circle cx="61.87" cy="43.24" r="0.9"/>
          <circle cx="62.63" cy="42.12" r="0.9"/>
          <circle cx="61.18" cy="45.23" r="0.9"/>
          <circle cx="63.32" cy="45.58" r="0.9"/>
          <circle cx="62.92" cy="43.29" r="0.9"/>
          <circle cx="63.69" cy="44.14" r="0.9"/>
          <circle cx="62.67" cy="44.92" r="0.9"/>
          <circle cx="63.78" cy="44.72" r="0.9"/>
          <circle cx="65.74" cy="47.02" r="0.9"/>
          <circle cx="65.72" cy="47.28" r="0.9"/>
          <circle cx="65.22" cy="44.81" r="0.9"/>
          <circle cx="65.42" cy="46.11" r="0.9"/>
          <circle cx="65.89" cy="46.52" r="0.9"/>
          <circle cx="67.1" cy="45.14" r="0.9"/>
          <circle cx="67.81" cy="46.27" r="0.9"/>
          <circle cx="67.17" cy="45.57" r="0.9"/>
          <circle cx="67.71" cy="47.88" r="0.9"/>
          <circle cx="66.99" cy="48.52" r="0.9"/>
          <circle cx="68.28" cy="50.06" r="0.9"/>
          <circle cx="67.57" cy="50.88" r="0.9"/>
          <circle cx="69.4" cy="50.25" r="0.9"/>
          <circle cx="69.04" cy="49.14" r="0.9"/>
          <circle cx="71.56" cy="50.26" r="0.9"/>
          <circle cx="71.59" cy="55.88" r="0.9"/>
          <circle cx="72.35" cy="50.61" r="0.9"/>
          <circle cx="72.5" cy="52.56" r="0.9"/>
          <circle cx="73.06" cy="53.19" r="0.9"/>
          <circle cx="72.64" cy="54.26" r="0.9"/>
          <circle cx="72.57" cy="55.43" r="0.9"/>
          <circle cx="75.55" cy="52.45" r="0.9"/>
          <circle cx="74.6" cy="53.72" r="0.9"/>
          <circle cx="75.55" cy="57.27" r="0.9"/>
          <circle cx="73.92" cy="55.25" r="0.9"/>
          <circle cx="74.75" cy="55.45" r="0.9"/>
          <circle cx="75.5" cy="57.65" r="0.9"/>
          <circle cx="75.13" cy="59.51" r="0.9"/>
          <circle cx="78.07" cy="56.48" r="0.9"/>
          <circle cx="77.48" cy="58.22" r="0.9"/>
          <circle cx="76.04" cy="61.92" r="0.9"/>
          <circle cx="77.49" cy="57.73" r="0.9"/>
          <circle cx="79.19" cy="63.62" r="0.9"/>
          <circle cx="78.48" cy="62.03" r="0.9"/>
          <circle cx="79.98" cy="61.87" r="0.9"/>
          <circle cx="78.36" cy="61.94" r="0.9"/>
          <circle cx="79.24" cy="64.23" r="0.9"/>
          <circle cx="81.29" cy="64.61" r="0.9"/>
          <circle cx="81.17" cy="62.98" r="0.9"/>
          <circle cx="81.03" cy="65.51" r="0.9"/>
          <circle cx="80.25" cy="68.2" r="0.9"/>
          <circle cx="82.91" cy="66.1" r="0.9"/>
          <circle cx="81.04" cy="66.58" r="0.9"/>
        </g>
      </g>
      <g stroke-width="0.3" fill="#000000" fill-opacity="0.000" class="geometry" stroke-dasharray="none" stroke="#00BFFF" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-16">
        <path fill="none" d="M22.75,14.61 L 23.57 58.91 23.59 62.52 23.62 62.51 23.67 63.28 23.84 62.63 24.15 62.66 24.84 62.59 25.6 62.15 26.16 61.55 26.73 60.58 27.25 60.12 27.4 58.99 27.65 59.44 27.69 58.63 27.96 57.53 28.36 57.49 29.18 57.24 30.01 56.19 30.58 55.49 30.82 55.37 31.28 54.75 32.05 53.77 32.66 54.01 32.78 53.23 33.1 53.12 33.64 52.45 34.04 52.31 34.26 52.1 34.51 51.42 35.02 51.16 35.66 50.95 36.3 50.4 36.65 48.48 36.68 49.45 37.06 48.68 37.4 48.16 37.7 48.45 38.04 47.98 38.46 47.6 38.95 47.01 38.98 46.81 39.38 46.32 39.45 45.83 40.07 45.86 40.31 46.15 40.99 45.86 41.38 44.77 41.97 44.55 42.38 44.37 42.7 44.22 42.8 43.97 43.35 43.5 43.93 43.33 44.59 43.08 44.91 42.8 45.49 42.56 45.87 42.93 46.21 43.03 46.44 42.4 46.98 41.9 47.32 42.22 47.6 42.03 48.22 41.47 48.32 41.41 48.62 42.15 49.08 41.7 49.3 41.25 49.86 41.13 50.39 40.92 50.97 40.98 51.53 41.23 51.93 41.33 52.04 41 52.26 41.04 52.85 40.91 53.18 40.71 53.62 40.85 54.12 40.66 54.64 40.6 54.67 40.67 55.3 40.99 55.94 41.16 56.5 41.5 57.03 40.94 57.41 41.23 57.79 41.47 58.17 41.07 58.39 41.19 58.53 41.66 59.31 41.44 59.79 41.79 60.35 42.17 60.52 42.2 60.75 42.49 61.31 42.82 61.91 42.86 62.09 43.56 62.67 44.19 63.05 44.21 63.51 44.41 63.65 44.75 64.01 44.98 64.7 45.66 65.24 46.25 65.56 46.2 65.85 46.46 66.19 46.74 66.7 46.68 67.26 46.88 67.57 46.91 67.92 47.41 68.05 47.95 68.43 48.72 68.57 49.5 69.07 50 69.38 50.17 70.17 50.55 70.8 52.04 71.45 52.12 72 52.61 72.55 53.13 72.9 53.77 73.16 54.53 73.99 54.51 74.45 54.77 75.01 55.73 75.11 56.08 75.35 56.4 75.71 57.12 75.91 58.09 76.69 58.23 77.18 58.71 77.27 59.89 77.64 59.94 78.29 61.23 78.65 61.92 79.25 62.44 79.39 62.86 79.68 63.68 80.34 64.43 80.84 64.69 81.21 65.42 81.33 66.59 81.99 67.07 82.11 67.56"/>
      </g>
      <g stroke-width="0.3" fill="#000000" fill-opacity="0.000" class="geometry" stroke-dasharray="none" stroke="#FF5EA0" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-17">
        <path fill="none" d="M22.75,68.03 L 23.16 67.28 23.57 66.54 23.98 65.81 24.39 65.09 24.8 64.38 25.21 63.69 25.62 63 26.04 62.32 26.45 61.66 26.86 61 27.27 60.36 27.68 59.72 28.09 59.1 28.5 58.48 28.92 57.88 29.33 57.29 29.74 56.7 30.15 56.13 30.56 55.57 30.97 55.02 31.38 54.48 31.79 53.95 32.21 53.43 32.62 52.92 33.03 52.42 33.44 51.93 33.85 51.45 34.26 50.99 34.67 50.53 35.09 50.08 35.5 49.65 35.91 49.22 36.32 48.81 36.73 48.4 37.14 48.01 37.55 47.63 37.97 47.25 38.38 46.89 38.79 46.54 39.2 46.2 39.61 45.87 40.02 45.55 40.43 45.24 40.84 44.94 41.26 44.65 41.67 44.37 42.08 44.1 42.49 43.84 42.9 43.6 43.31 43.36 43.72 43.13 44.14 42.92 44.55 42.71 44.96 42.52 45.37 42.33 45.78 42.16 46.19 42 46.6 41.84 47.02 41.7 47.43 41.57 47.84 41.45 48.25 41.34 48.66 41.24 49.07 41.15 49.48 41.07 49.89 41 50.31 40.94 50.72 40.89 51.13 40.85 51.54 40.83 51.95 40.81 52.36 40.8 52.77 40.81 53.19 40.82 53.6 40.85 54.01 40.88 54.42 40.93 54.83 40.99 55.24 41.06 55.65 41.13 56.07 41.22 56.48 41.32 56.89 41.43 57.3 41.55 57.71 41.68 58.12 41.82 58.53 41.97 58.94 42.13 59.36 42.3 59.77 42.49 60.18 42.68 60.59 42.88 61 43.1 61.41 43.32 61.82 43.56 62.24 43.8 62.65 44.06 63.06 44.32 63.47 44.6 63.88 44.89 64.29 45.19 64.7 45.5 65.12 45.81 65.53 46.14 65.94 46.48 66.35 46.83 66.76 47.19 67.17 47.57 67.58 47.95 67.99 48.34 68.41 48.74 68.82 49.16 69.23 49.58 69.64 50.01 70.05 50.46 70.46 50.91 70.87 51.38 71.29 51.85 71.7 52.34 72.11 52.84 72.52 53.35 72.93 53.86 73.34 54.39 73.75 54.93 74.17 55.48 74.58 56.04 74.99 56.61 75.4 57.19 75.81 57.78 76.22 58.38 76.63 59 77.04 59.62 77.46 60.25 77.87 60.9 78.28 61.55 78.69 62.22 79.1 62.89 79.51 63.58 79.92 64.27 80.34 64.98 80.75 65.7 81.16 66.42 81.57 67.16 81.98 67.91"/>
      </g>
    </g>
    <g opacity="0" class="guide zoomslider" stroke="#000000" stroke-opacity="0.000" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-18">
      <g fill="#EAEAEA" stroke-width="0.3" stroke-opacity="0" stroke="#6A6A6A" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-19">
        <rect x="105.01" y="15.61" width="4" height="4"/>
        <g class="button_logo" fill="#6A6A6A" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-20">
          <path d="M105.81,17.21 L 106.61 17.21 106.61 16.41 107.41 16.41 107.41 17.21 108.21 17.21 108.21 18.01 107.41 18.01 107.41 18.81 106.61 18.81 106.61 18.01 105.81 18.01 z"/>
        </g>
      </g>
      <g fill="#EAEAEA" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-21">
        <rect x="85.51" y="15.61" width="19" height="4"/>
      </g>
      <g class="zoomslider_thumb" fill="#6A6A6A" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-22">
        <rect x="94.01" y="15.61" width="2" height="4"/>
      </g>
      <g fill="#EAEAEA" stroke-width="0.3" stroke-opacity="0" stroke="#6A6A6A" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-23">
        <rect x="81.01" y="15.61" width="4" height="4"/>
        <g class="button_logo" fill="#6A6A6A" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-24">
          <path d="M81.81,17.21 L 84.21 17.21 84.21 18.01 81.81 18.01 z"/>
        </g>
      </g>
    </g>
  </g>
  <g class="guide ylabels" font-size="2.82" font-family="'PT Sans Caption','Helvetica Neue','Helvetica',sans-serif" fill="#6C606B" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-25">
    <text x="19.74" y="153.5" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-800</text>
    <text x="19.74" y="142.82" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-700</text>
    <text x="19.74" y="132.13" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-600</text>
    <text x="19.74" y="121.45" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-500</text>
    <text x="19.74" y="110.77" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-400</text>
    <text x="19.74" y="100.08" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-300</text>
    <text x="19.74" y="89.4" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">-200</text>
    <text x="19.74" y="78.71" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">-100</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">0</text>
    <text x="19.74" y="57.35" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">100</text>
    <text x="19.74" y="46.66" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">200</text>
    <text x="19.74" y="35.98" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">300</text>
    <text x="19.74" y="25.3" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">400</text>
    <text x="19.74" y="14.61" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="visible">500</text>
    <text x="19.74" y="3.93" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">600</text>
    <text x="19.74" y="-6.76" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">700</text>
    <text x="19.74" y="-17.44" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">800</text>
    <text x="19.74" y="-28.12" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">900</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">1000</text>
    <text x="19.74" y="-49.49" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">1100</text>
    <text x="19.74" y="-60.18" text-anchor="end" dy="0.35em" gadfly:scale="1.0" visibility="hidden">1200</text>
    <text x="19.74" y="142.82" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-700</text>
    <text x="19.74" y="140.68" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-680</text>
    <text x="19.74" y="138.54" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-660</text>
    <text x="19.74" y="136.41" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-640</text>
    <text x="19.74" y="134.27" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-620</text>
    <text x="19.74" y="132.13" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-600</text>
    <text x="19.74" y="130" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-580</text>
    <text x="19.74" y="127.86" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-560</text>
    <text x="19.74" y="125.72" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-540</text>
    <text x="19.74" y="123.59" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-520</text>
    <text x="19.74" y="121.45" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-500</text>
    <text x="19.74" y="119.31" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-480</text>
    <text x="19.74" y="117.18" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-460</text>
    <text x="19.74" y="115.04" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-440</text>
    <text x="19.74" y="112.9" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-420</text>
    <text x="19.74" y="110.77" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-400</text>
    <text x="19.74" y="108.63" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-380</text>
    <text x="19.74" y="106.49" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-360</text>
    <text x="19.74" y="104.36" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-340</text>
    <text x="19.74" y="102.22" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-320</text>
    <text x="19.74" y="100.08" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-300</text>
    <text x="19.74" y="97.95" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-280</text>
    <text x="19.74" y="95.81" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-260</text>
    <text x="19.74" y="93.67" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-240</text>
    <text x="19.74" y="91.54" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-220</text>
    <text x="19.74" y="89.4" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-200</text>
    <text x="19.74" y="87.26" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-180</text>
    <text x="19.74" y="85.13" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-160</text>
    <text x="19.74" y="82.99" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-140</text>
    <text x="19.74" y="80.85" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-120</text>
    <text x="19.74" y="78.71" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-100</text>
    <text x="19.74" y="76.58" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-80</text>
    <text x="19.74" y="74.44" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-60</text>
    <text x="19.74" y="72.3" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-40</text>
    <text x="19.74" y="70.17" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">-20</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">0</text>
    <text x="19.74" y="65.89" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">20</text>
    <text x="19.74" y="63.76" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">40</text>
    <text x="19.74" y="61.62" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">60</text>
    <text x="19.74" y="59.48" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">80</text>
    <text x="19.74" y="57.35" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">100</text>
    <text x="19.74" y="55.21" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">120</text>
    <text x="19.74" y="53.07" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">140</text>
    <text x="19.74" y="50.94" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">160</text>
    <text x="19.74" y="48.8" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">180</text>
    <text x="19.74" y="46.66" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">200</text>
    <text x="19.74" y="44.53" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">220</text>
    <text x="19.74" y="42.39" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">240</text>
    <text x="19.74" y="40.25" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">260</text>
    <text x="19.74" y="38.12" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">280</text>
    <text x="19.74" y="35.98" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">300</text>
    <text x="19.74" y="33.84" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">320</text>
    <text x="19.74" y="31.71" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">340</text>
    <text x="19.74" y="29.57" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">360</text>
    <text x="19.74" y="27.43" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">380</text>
    <text x="19.74" y="25.3" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">400</text>
    <text x="19.74" y="23.16" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">420</text>
    <text x="19.74" y="21.02" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">440</text>
    <text x="19.74" y="18.89" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">460</text>
    <text x="19.74" y="16.75" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">480</text>
    <text x="19.74" y="14.61" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">500</text>
    <text x="19.74" y="12.47" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">520</text>
    <text x="19.74" y="10.34" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">540</text>
    <text x="19.74" y="8.2" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">560</text>
    <text x="19.74" y="6.06" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">580</text>
    <text x="19.74" y="3.93" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">600</text>
    <text x="19.74" y="1.79" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">620</text>
    <text x="19.74" y="-0.35" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">640</text>
    <text x="19.74" y="-2.48" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">660</text>
    <text x="19.74" y="-4.62" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">680</text>
    <text x="19.74" y="-6.76" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">700</text>
    <text x="19.74" y="-8.89" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">720</text>
    <text x="19.74" y="-11.03" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">740</text>
    <text x="19.74" y="-13.17" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">760</text>
    <text x="19.74" y="-15.3" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">780</text>
    <text x="19.74" y="-17.44" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">800</text>
    <text x="19.74" y="-19.58" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">820</text>
    <text x="19.74" y="-21.71" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">840</text>
    <text x="19.74" y="-23.85" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">860</text>
    <text x="19.74" y="-25.99" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">880</text>
    <text x="19.74" y="-28.12" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">900</text>
    <text x="19.74" y="-30.26" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">920</text>
    <text x="19.74" y="-32.4" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">940</text>
    <text x="19.74" y="-34.53" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">960</text>
    <text x="19.74" y="-36.67" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">980</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1000</text>
    <text x="19.74" y="-40.94" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1020</text>
    <text x="19.74" y="-43.08" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1040</text>
    <text x="19.74" y="-45.22" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1060</text>
    <text x="19.74" y="-47.35" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1080</text>
    <text x="19.74" y="-49.49" text-anchor="end" dy="0.35em" gadfly:scale="10.0" visibility="hidden">1100</text>
    <text x="19.74" y="174.87" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">-1000</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">0</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">1000</text>
    <text x="19.74" y="-145.65" text-anchor="end" dy="0.35em" gadfly:scale="0.5" visibility="hidden">2000</text>
    <text x="19.74" y="142.82" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-700</text>
    <text x="19.74" y="137.48" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-650</text>
    <text x="19.74" y="132.13" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-600</text>
    <text x="19.74" y="126.79" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-550</text>
    <text x="19.74" y="121.45" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-500</text>
    <text x="19.74" y="116.11" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-450</text>
    <text x="19.74" y="110.77" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-400</text>
    <text x="19.74" y="105.42" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-350</text>
    <text x="19.74" y="100.08" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-300</text>
    <text x="19.74" y="94.74" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-250</text>
    <text x="19.74" y="89.4" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-200</text>
    <text x="19.74" y="84.06" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-150</text>
    <text x="19.74" y="78.71" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-100</text>
    <text x="19.74" y="73.37" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">-50</text>
    <text x="19.74" y="68.03" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">0</text>
    <text x="19.74" y="62.69" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">50</text>
    <text x="19.74" y="57.35" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">100</text>
    <text x="19.74" y="52.01" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">150</text>
    <text x="19.74" y="46.66" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">200</text>
    <text x="19.74" y="41.32" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">250</text>
    <text x="19.74" y="35.98" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">300</text>
    <text x="19.74" y="30.64" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">350</text>
    <text x="19.74" y="25.3" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">400</text>
    <text x="19.74" y="19.95" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">450</text>
    <text x="19.74" y="14.61" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">500</text>
    <text x="19.74" y="9.27" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">550</text>
    <text x="19.74" y="3.93" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">600</text>
    <text x="19.74" y="-1.41" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">650</text>
    <text x="19.74" y="-6.76" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">700</text>
    <text x="19.74" y="-12.1" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">750</text>
    <text x="19.74" y="-17.44" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">800</text>
    <text x="19.74" y="-22.78" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">850</text>
    <text x="19.74" y="-28.12" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">900</text>
    <text x="19.74" y="-33.47" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">950</text>
    <text x="19.74" y="-38.81" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">1000</text>
    <text x="19.74" y="-44.15" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">1050</text>
    <text x="19.74" y="-49.49" text-anchor="end" dy="0.35em" gadfly:scale="5.0" visibility="hidden">1100</text>
  </g>
  <g font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" fill="#564A55" stroke="#000000" stroke-opacity="0.000" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-26">
    <text x="8.81" y="44.66" text-anchor="middle" dy="0.35em" transform="rotate(-90, 8.81, 46.66)">Y position</text>
  </g>
  <g font-size="3.88" font-family="'PT Sans','Helvetica Neue','Helvetica',sans-serif" fill="#564A55" stroke="#000000" stroke-opacity="0.000" id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-27">
    <text x="66.38" y="10.61" text-anchor="middle">Measurement of a Canonball in Flight</text>
  </g>
</g>
<defs>
<clipPath id="fig-f679eb34e3304a2b9eea5b9025b9d353-element-9">
  <path d="M20.75,12.61 L 112.01 12.61 112.01 80.72 20.75 80.72" />
</clipPath
></defs>
<script> <![CDATA[
(function(N){var k=/[\.\/]/,L=/\s*,\s*/,C=function(a,d){return a-d},a,v,y={n:{}},M=function(){for(var a=0,d=this.length;a<d;a++)if("undefined"!=typeof this[a])return this[a]},A=function(){for(var a=this.length;--a;)if("undefined"!=typeof this[a])return this[a]},w=function(k,d){k=String(k);var f=v,n=Array.prototype.slice.call(arguments,2),u=w.listeners(k),p=0,b,q=[],e={},l=[],r=a;l.firstDefined=M;l.lastDefined=A;a=k;for(var s=v=0,x=u.length;s<x;s++)"zIndex"in u[s]&&(q.push(u[s].zIndex),0>u[s].zIndex&&
(e[u[s].zIndex]=u[s]));for(q.sort(C);0>q[p];)if(b=e[q[p++] ],l.push(b.apply(d,n)),v)return v=f,l;for(s=0;s<x;s++)if(b=u[s],"zIndex"in b)if(b.zIndex==q[p]){l.push(b.apply(d,n));if(v)break;do if(p++,(b=e[q[p] ])&&l.push(b.apply(d,n)),v)break;while(b)}else e[b.zIndex]=b;else if(l.push(b.apply(d,n)),v)break;v=f;a=r;return l};w._events=y;w.listeners=function(a){a=a.split(k);var d=y,f,n,u,p,b,q,e,l=[d],r=[];u=0;for(p=a.length;u<p;u++){e=[];b=0;for(q=l.length;b<q;b++)for(d=l[b].n,f=[d[a[u] ],d["*"] ],n=2;n--;)if(d=
f[n])e.push(d),r=r.concat(d.f||[]);l=e}return r};w.on=function(a,d){a=String(a);if("function"!=typeof d)return function(){};for(var f=a.split(L),n=0,u=f.length;n<u;n++)(function(a){a=a.split(k);for(var b=y,f,e=0,l=a.length;e<l;e++)b=b.n,b=b.hasOwnProperty(a[e])&&b[a[e] ]||(b[a[e] ]={n:{}});b.f=b.f||[];e=0;for(l=b.f.length;e<l;e++)if(b.f[e]==d){f=!0;break}!f&&b.f.push(d)})(f[n]);return function(a){+a==+a&&(d.zIndex=+a)}};w.f=function(a){var d=[].slice.call(arguments,1);return function(){w.apply(null,
[a,null].concat(d).concat([].slice.call(arguments,0)))}};w.stop=function(){v=1};w.nt=function(k){return k?(new RegExp("(?:\\.|\\/|^)"+k+"(?:\\.|\\/|$)")).test(a):a};w.nts=function(){return a.split(k)};w.off=w.unbind=function(a,d){if(a){var f=a.split(L);if(1<f.length)for(var n=0,u=f.length;n<u;n++)w.off(f[n],d);else{for(var f=a.split(k),p,b,q,e,l=[y],n=0,u=f.length;n<u;n++)for(e=0;e<l.length;e+=q.length-2){q=[e,1];p=l[e].n;if("*"!=f[n])p[f[n] ]&&q.push(p[f[n] ]);else for(b in p)p.hasOwnProperty(b)&&
q.push(p[b]);l.splice.apply(l,q)}n=0;for(u=l.length;n<u;n++)for(p=l[n];p.n;){if(d){if(p.f){e=0;for(f=p.f.length;e<f;e++)if(p.f[e]==d){p.f.splice(e,1);break}!p.f.length&&delete p.f}for(b in p.n)if(p.n.hasOwnProperty(b)&&p.n[b].f){q=p.n[b].f;e=0;for(f=q.length;e<f;e++)if(q[e]==d){q.splice(e,1);break}!q.length&&delete p.n[b].f}}else for(b in delete p.f,p.n)p.n.hasOwnProperty(b)&&p.n[b].f&&delete p.n[b].f;p=p.n}}}else w._events=y={n:{}}};w.once=function(a,d){var f=function(){w.unbind(a,f);return d.apply(this,
arguments)};return w.on(a,f)};w.version="0.4.2";w.toString=function(){return"You are running Eve 0.4.2"};"undefined"!=typeof module&&module.exports?module.exports=w:"function"===typeof define&&define.amd?define("eve",[],function(){return w}):N.eve=w})(this);
(function(N,k){"function"===typeof define&&define.amd?define("Snap.svg",["eve"],function(L){return k(N,L)}):k(N,N.eve)})(this,function(N,k){var L=function(a){var k={},y=N.requestAnimationFrame||N.webkitRequestAnimationFrame||N.mozRequestAnimationFrame||N.oRequestAnimationFrame||N.msRequestAnimationFrame||function(a){setTimeout(a,16)},M=Array.isArray||function(a){return a instanceof Array||"[object Array]"==Object.prototype.toString.call(a)},A=0,w="M"+(+new Date).toString(36),z=function(a){if(null==
a)return this.s;var b=this.s-a;this.b+=this.dur*b;this.B+=this.dur*b;this.s=a},d=function(a){if(null==a)return this.spd;this.spd=a},f=function(a){if(null==a)return this.dur;this.s=this.s*a/this.dur;this.dur=a},n=function(){delete k[this.id];this.update();a("mina.stop."+this.id,this)},u=function(){this.pdif||(delete k[this.id],this.update(),this.pdif=this.get()-this.b)},p=function(){this.pdif&&(this.b=this.get()-this.pdif,delete this.pdif,k[this.id]=this)},b=function(){var a;if(M(this.start)){a=[];
for(var b=0,e=this.start.length;b<e;b++)a[b]=+this.start[b]+(this.end[b]-this.start[b])*this.easing(this.s)}else a=+this.start+(this.end-this.start)*this.easing(this.s);this.set(a)},q=function(){var l=0,b;for(b in k)if(k.hasOwnProperty(b)){var e=k[b],f=e.get();l++;e.s=(f-e.b)/(e.dur/e.spd);1<=e.s&&(delete k[b],e.s=1,l--,function(b){setTimeout(function(){a("mina.finish."+b.id,b)})}(e));e.update()}l&&y(q)},e=function(a,r,s,x,G,h,J){a={id:w+(A++).toString(36),start:a,end:r,b:s,s:0,dur:x-s,spd:1,get:G,
set:h,easing:J||e.linear,status:z,speed:d,duration:f,stop:n,pause:u,resume:p,update:b};k[a.id]=a;r=0;for(var K in k)if(k.hasOwnProperty(K)&&(r++,2==r))break;1==r&&y(q);return a};e.time=Date.now||function(){return+new Date};e.getById=function(a){return k[a]||null};e.linear=function(a){return a};e.easeout=function(a){return Math.pow(a,1.7)};e.easein=function(a){return Math.pow(a,0.48)};e.easeinout=function(a){if(1==a)return 1;if(0==a)return 0;var b=0.48-a/1.04,e=Math.sqrt(0.1734+b*b);a=e-b;a=Math.pow(Math.abs(a),
1/3)*(0>a?-1:1);b=-e-b;b=Math.pow(Math.abs(b),1/3)*(0>b?-1:1);a=a+b+0.5;return 3*(1-a)*a*a+a*a*a};e.backin=function(a){return 1==a?1:a*a*(2.70158*a-1.70158)};e.backout=function(a){if(0==a)return 0;a-=1;return a*a*(2.70158*a+1.70158)+1};e.elastic=function(a){return a==!!a?a:Math.pow(2,-10*a)*Math.sin(2*(a-0.075)*Math.PI/0.3)+1};e.bounce=function(a){a<1/2.75?a*=7.5625*a:a<2/2.75?(a-=1.5/2.75,a=7.5625*a*a+0.75):a<2.5/2.75?(a-=2.25/2.75,a=7.5625*a*a+0.9375):(a-=2.625/2.75,a=7.5625*a*a+0.984375);return a};
return N.mina=e}("undefined"==typeof k?function(){}:k),C=function(){function a(c,t){if(c){if(c.tagName)return x(c);if(y(c,"array")&&a.set)return a.set.apply(a,c);if(c instanceof e)return c;if(null==t)return c=G.doc.querySelector(c),x(c)}return new s(null==c?"100%":c,null==t?"100%":t)}function v(c,a){if(a){"#text"==c&&(c=G.doc.createTextNode(a.text||""));"string"==typeof c&&(c=v(c));if("string"==typeof a)return"xlink:"==a.substring(0,6)?c.getAttributeNS(m,a.substring(6)):"xml:"==a.substring(0,4)?c.getAttributeNS(la,
a.substring(4)):c.getAttribute(a);for(var da in a)if(a[h](da)){var b=J(a[da]);b?"xlink:"==da.substring(0,6)?c.setAttributeNS(m,da.substring(6),b):"xml:"==da.substring(0,4)?c.setAttributeNS(la,da.substring(4),b):c.setAttribute(da,b):c.removeAttribute(da)}}else c=G.doc.createElementNS(la,c);return c}function y(c,a){a=J.prototype.toLowerCase.call(a);return"finite"==a?isFinite(c):"array"==a&&(c instanceof Array||Array.isArray&&Array.isArray(c))?!0:"null"==a&&null===c||a==typeof c&&null!==c||"object"==
a&&c===Object(c)||$.call(c).slice(8,-1).toLowerCase()==a}function M(c){if("function"==typeof c||Object(c)!==c)return c;var a=new c.constructor,b;for(b in c)c[h](b)&&(a[b]=M(c[b]));return a}function A(c,a,b){function m(){var e=Array.prototype.slice.call(arguments,0),f=e.join("\u2400"),d=m.cache=m.cache||{},l=m.count=m.count||[];if(d[h](f)){a:for(var e=l,l=f,B=0,H=e.length;B<H;B++)if(e[B]===l){e.push(e.splice(B,1)[0]);break a}return b?b(d[f]):d[f]}1E3<=l.length&&delete d[l.shift()];l.push(f);d[f]=c.apply(a,
e);return b?b(d[f]):d[f]}return m}function w(c,a,b,m,e,f){return null==e?(c-=b,a-=m,c||a?(180*I.atan2(-a,-c)/C+540)%360:0):w(c,a,e,f)-w(b,m,e,f)}function z(c){return c%360*C/180}function d(c){var a=[];c=c.replace(/(?:^|\s)(\w+)\(([^)]+)\)/g,function(c,b,m){m=m.split(/\s*,\s*|\s+/);"rotate"==b&&1==m.length&&m.push(0,0);"scale"==b&&(2<m.length?m=m.slice(0,2):2==m.length&&m.push(0,0),1==m.length&&m.push(m[0],0,0));"skewX"==b?a.push(["m",1,0,I.tan(z(m[0])),1,0,0]):"skewY"==b?a.push(["m",1,I.tan(z(m[0])),
0,1,0,0]):a.push([b.charAt(0)].concat(m));return c});return a}function f(c,t){var b=O(c),m=new a.Matrix;if(b)for(var e=0,f=b.length;e<f;e++){var h=b[e],d=h.length,B=J(h[0]).toLowerCase(),H=h[0]!=B,l=H?m.invert():0,E;"t"==B&&2==d?m.translate(h[1],0):"t"==B&&3==d?H?(d=l.x(0,0),B=l.y(0,0),H=l.x(h[1],h[2]),l=l.y(h[1],h[2]),m.translate(H-d,l-B)):m.translate(h[1],h[2]):"r"==B?2==d?(E=E||t,m.rotate(h[1],E.x+E.width/2,E.y+E.height/2)):4==d&&(H?(H=l.x(h[2],h[3]),l=l.y(h[2],h[3]),m.rotate(h[1],H,l)):m.rotate(h[1],
h[2],h[3])):"s"==B?2==d||3==d?(E=E||t,m.scale(h[1],h[d-1],E.x+E.width/2,E.y+E.height/2)):4==d?H?(H=l.x(h[2],h[3]),l=l.y(h[2],h[3]),m.scale(h[1],h[1],H,l)):m.scale(h[1],h[1],h[2],h[3]):5==d&&(H?(H=l.x(h[3],h[4]),l=l.y(h[3],h[4]),m.scale(h[1],h[2],H,l)):m.scale(h[1],h[2],h[3],h[4])):"m"==B&&7==d&&m.add(h[1],h[2],h[3],h[4],h[5],h[6])}return m}function n(c,t){if(null==t){var m=!0;t="linearGradient"==c.type||"radialGradient"==c.type?c.node.getAttribute("gradientTransform"):"pattern"==c.type?c.node.getAttribute("patternTransform"):
c.node.getAttribute("transform");if(!t)return new a.Matrix;t=d(t)}else t=a._.rgTransform.test(t)?J(t).replace(/\.{3}|\u2026/g,c._.transform||aa):d(t),y(t,"array")&&(t=a.path?a.path.toString.call(t):J(t)),c._.transform=t;var b=f(t,c.getBBox(1));if(m)return b;c.matrix=b}function u(c){c=c.node.ownerSVGElement&&x(c.node.ownerSVGElement)||c.node.parentNode&&x(c.node.parentNode)||a.select("svg")||a(0,0);var t=c.select("defs"),t=null==t?!1:t.node;t||(t=r("defs",c.node).node);return t}function p(c){return c.node.ownerSVGElement&&
x(c.node.ownerSVGElement)||a.select("svg")}function b(c,a,m){function b(c){if(null==c)return aa;if(c==+c)return c;v(B,{width:c});try{return B.getBBox().width}catch(a){return 0}}function h(c){if(null==c)return aa;if(c==+c)return c;v(B,{height:c});try{return B.getBBox().height}catch(a){return 0}}function e(b,B){null==a?d[b]=B(c.attr(b)||0):b==a&&(d=B(null==m?c.attr(b)||0:m))}var f=p(c).node,d={},B=f.querySelector(".svg---mgr");B||(B=v("rect"),v(B,{x:-9E9,y:-9E9,width:10,height:10,"class":"svg---mgr",
fill:"none"}),f.appendChild(B));switch(c.type){case "rect":e("rx",b),e("ry",h);case "image":e("width",b),e("height",h);case "text":e("x",b);e("y",h);break;case "circle":e("cx",b);e("cy",h);e("r",b);break;case "ellipse":e("cx",b);e("cy",h);e("rx",b);e("ry",h);break;case "line":e("x1",b);e("x2",b);e("y1",h);e("y2",h);break;case "marker":e("refX",b);e("markerWidth",b);e("refY",h);e("markerHeight",h);break;case "radialGradient":e("fx",b);e("fy",h);break;case "tspan":e("dx",b);e("dy",h);break;default:e(a,
b)}f.removeChild(B);return d}function q(c){y(c,"array")||(c=Array.prototype.slice.call(arguments,0));for(var a=0,b=0,m=this.node;this[a];)delete this[a++];for(a=0;a<c.length;a++)"set"==c[a].type?c[a].forEach(function(c){m.appendChild(c.node)}):m.appendChild(c[a].node);for(var h=m.childNodes,a=0;a<h.length;a++)this[b++]=x(h[a]);return this}function e(c){if(c.snap in E)return E[c.snap];var a=this.id=V(),b;try{b=c.ownerSVGElement}catch(m){}this.node=c;b&&(this.paper=new s(b));this.type=c.tagName;this.anims=
{};this._={transform:[]};c.snap=a;E[a]=this;"g"==this.type&&(this.add=q);if(this.type in{g:1,mask:1,pattern:1})for(var e in s.prototype)s.prototype[h](e)&&(this[e]=s.prototype[e])}function l(c){this.node=c}function r(c,a){var b=v(c);a.appendChild(b);return x(b)}function s(c,a){var b,m,f,d=s.prototype;if(c&&"svg"==c.tagName){if(c.snap in E)return E[c.snap];var l=c.ownerDocument;b=new e(c);m=c.getElementsByTagName("desc")[0];f=c.getElementsByTagName("defs")[0];m||(m=v("desc"),m.appendChild(l.createTextNode("Created with Snap")),
b.node.appendChild(m));f||(f=v("defs"),b.node.appendChild(f));b.defs=f;for(var ca in d)d[h](ca)&&(b[ca]=d[ca]);b.paper=b.root=b}else b=r("svg",G.doc.body),v(b.node,{height:a,version:1.1,width:c,xmlns:la});return b}function x(c){return!c||c instanceof e||c instanceof l?c:c.tagName&&"svg"==c.tagName.toLowerCase()?new s(c):c.tagName&&"object"==c.tagName.toLowerCase()&&"image/svg+xml"==c.type?new s(c.contentDocument.getElementsByTagName("svg")[0]):new e(c)}a.version="0.3.0";a.toString=function(){return"Snap v"+
this.version};a._={};var G={win:N,doc:N.document};a._.glob=G;var h="hasOwnProperty",J=String,K=parseFloat,U=parseInt,I=Math,P=I.max,Q=I.min,Y=I.abs,C=I.PI,aa="",$=Object.prototype.toString,F=/^\s*((#[a-f\d]{6})|(#[a-f\d]{3})|rgba?\(\s*([\d\.]+%?\s*,\s*[\d\.]+%?\s*,\s*[\d\.]+%?(?:\s*,\s*[\d\.]+%?)?)\s*\)|hsba?\(\s*([\d\.]+(?:deg|\xb0|%)?\s*,\s*[\d\.]+%?\s*,\s*[\d\.]+(?:%?\s*,\s*[\d\.]+)?%?)\s*\)|hsla?\(\s*([\d\.]+(?:deg|\xb0|%)?\s*,\s*[\d\.]+%?\s*,\s*[\d\.]+(?:%?\s*,\s*[\d\.]+)?%?)\s*\))\s*$/i;a._.separator=
RegExp("[,\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]+");var S=RegExp("[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*"),X={hs:1,rg:1},W=RegExp("([a-z])[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029,]*((-?\\d*\\.?\\d*(?:e[\\-+]?\\d+)?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*)+)",
"ig"),ma=RegExp("([rstm])[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029,]*((-?\\d*\\.?\\d*(?:e[\\-+]?\\d+)?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*)+)","ig"),Z=RegExp("(-?\\d*\\.?\\d*(?:e[\\-+]?\\d+)?)[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*,?[\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*",
"ig"),na=0,ba="S"+(+new Date).toString(36),V=function(){return ba+(na++).toString(36)},m="http://www.w3.org/1999/xlink",la="http://www.w3.org/2000/svg",E={},ca=a.url=function(c){return"url('#"+c+"')"};a._.$=v;a._.id=V;a.format=function(){var c=/\{([^\}]+)\}/g,a=/(?:(?:^|\.)(.+?)(?=\[|\.|$|\()|\[('|")(.+?)\2\])(\(\))?/g,b=function(c,b,m){var h=m;b.replace(a,function(c,a,b,m,t){a=a||m;h&&(a in h&&(h=h[a]),"function"==typeof h&&t&&(h=h()))});return h=(null==h||h==m?c:h)+""};return function(a,m){return J(a).replace(c,
function(c,a){return b(c,a,m)})}}();a._.clone=M;a._.cacher=A;a.rad=z;a.deg=function(c){return 180*c/C%360};a.angle=w;a.is=y;a.snapTo=function(c,a,b){b=y(b,"finite")?b:10;if(y(c,"array"))for(var m=c.length;m--;){if(Y(c[m]-a)<=b)return c[m]}else{c=+c;m=a%c;if(m<b)return a-m;if(m>c-b)return a-m+c}return a};a.getRGB=A(function(c){if(!c||(c=J(c)).indexOf("-")+1)return{r:-1,g:-1,b:-1,hex:"none",error:1,toString:ka};if("none"==c)return{r:-1,g:-1,b:-1,hex:"none",toString:ka};!X[h](c.toLowerCase().substring(0,
2))&&"#"!=c.charAt()&&(c=T(c));if(!c)return{r:-1,g:-1,b:-1,hex:"none",error:1,toString:ka};var b,m,e,f,d;if(c=c.match(F)){c[2]&&(e=U(c[2].substring(5),16),m=U(c[2].substring(3,5),16),b=U(c[2].substring(1,3),16));c[3]&&(e=U((d=c[3].charAt(3))+d,16),m=U((d=c[3].charAt(2))+d,16),b=U((d=c[3].charAt(1))+d,16));c[4]&&(d=c[4].split(S),b=K(d[0]),"%"==d[0].slice(-1)&&(b*=2.55),m=K(d[1]),"%"==d[1].slice(-1)&&(m*=2.55),e=K(d[2]),"%"==d[2].slice(-1)&&(e*=2.55),"rgba"==c[1].toLowerCase().slice(0,4)&&(f=K(d[3])),
d[3]&&"%"==d[3].slice(-1)&&(f/=100));if(c[5])return d=c[5].split(S),b=K(d[0]),"%"==d[0].slice(-1)&&(b/=100),m=K(d[1]),"%"==d[1].slice(-1)&&(m/=100),e=K(d[2]),"%"==d[2].slice(-1)&&(e/=100),"deg"!=d[0].slice(-3)&&"\u00b0"!=d[0].slice(-1)||(b/=360),"hsba"==c[1].toLowerCase().slice(0,4)&&(f=K(d[3])),d[3]&&"%"==d[3].slice(-1)&&(f/=100),a.hsb2rgb(b,m,e,f);if(c[6])return d=c[6].split(S),b=K(d[0]),"%"==d[0].slice(-1)&&(b/=100),m=K(d[1]),"%"==d[1].slice(-1)&&(m/=100),e=K(d[2]),"%"==d[2].slice(-1)&&(e/=100),
"deg"!=d[0].slice(-3)&&"\u00b0"!=d[0].slice(-1)||(b/=360),"hsla"==c[1].toLowerCase().slice(0,4)&&(f=K(d[3])),d[3]&&"%"==d[3].slice(-1)&&(f/=100),a.hsl2rgb(b,m,e,f);b=Q(I.round(b),255);m=Q(I.round(m),255);e=Q(I.round(e),255);f=Q(P(f,0),1);c={r:b,g:m,b:e,toString:ka};c.hex="#"+(16777216|e|m<<8|b<<16).toString(16).slice(1);c.opacity=y(f,"finite")?f:1;return c}return{r:-1,g:-1,b:-1,hex:"none",error:1,toString:ka}},a);a.hsb=A(function(c,b,m){return a.hsb2rgb(c,b,m).hex});a.hsl=A(function(c,b,m){return a.hsl2rgb(c,
b,m).hex});a.rgb=A(function(c,a,b,m){if(y(m,"finite")){var e=I.round;return"rgba("+[e(c),e(a),e(b),+m.toFixed(2)]+")"}return"#"+(16777216|b|a<<8|c<<16).toString(16).slice(1)});var T=function(c){var a=G.doc.getElementsByTagName("head")[0]||G.doc.getElementsByTagName("svg")[0];T=A(function(c){if("red"==c.toLowerCase())return"rgb(255, 0, 0)";a.style.color="rgb(255, 0, 0)";a.style.color=c;c=G.doc.defaultView.getComputedStyle(a,aa).getPropertyValue("color");return"rgb(255, 0, 0)"==c?null:c});return T(c)},
qa=function(){return"hsb("+[this.h,this.s,this.b]+")"},ra=function(){return"hsl("+[this.h,this.s,this.l]+")"},ka=function(){return 1==this.opacity||null==this.opacity?this.hex:"rgba("+[this.r,this.g,this.b,this.opacity]+")"},D=function(c,b,m){null==b&&y(c,"object")&&"r"in c&&"g"in c&&"b"in c&&(m=c.b,b=c.g,c=c.r);null==b&&y(c,string)&&(m=a.getRGB(c),c=m.r,b=m.g,m=m.b);if(1<c||1<b||1<m)c/=255,b/=255,m/=255;return[c,b,m]},oa=function(c,b,m,e){c=I.round(255*c);b=I.round(255*b);m=I.round(255*m);c={r:c,
g:b,b:m,opacity:y(e,"finite")?e:1,hex:a.rgb(c,b,m),toString:ka};y(e,"finite")&&(c.opacity=e);return c};a.color=function(c){var b;y(c,"object")&&"h"in c&&"s"in c&&"b"in c?(b=a.hsb2rgb(c),c.r=b.r,c.g=b.g,c.b=b.b,c.opacity=1,c.hex=b.hex):y(c,"object")&&"h"in c&&"s"in c&&"l"in c?(b=a.hsl2rgb(c),c.r=b.r,c.g=b.g,c.b=b.b,c.opacity=1,c.hex=b.hex):(y(c,"string")&&(c=a.getRGB(c)),y(c,"object")&&"r"in c&&"g"in c&&"b"in c&&!("error"in c)?(b=a.rgb2hsl(c),c.h=b.h,c.s=b.s,c.l=b.l,b=a.rgb2hsb(c),c.v=b.b):(c={hex:"none"},
c.r=c.g=c.b=c.h=c.s=c.v=c.l=-1,c.error=1));c.toString=ka;return c};a.hsb2rgb=function(c,a,b,m){y(c,"object")&&"h"in c&&"s"in c&&"b"in c&&(b=c.b,a=c.s,c=c.h,m=c.o);var e,h,d;c=360*c%360/60;d=b*a;a=d*(1-Y(c%2-1));b=e=h=b-d;c=~~c;b+=[d,a,0,0,a,d][c];e+=[a,d,d,a,0,0][c];h+=[0,0,a,d,d,a][c];return oa(b,e,h,m)};a.hsl2rgb=function(c,a,b,m){y(c,"object")&&"h"in c&&"s"in c&&"l"in c&&(b=c.l,a=c.s,c=c.h);if(1<c||1<a||1<b)c/=360,a/=100,b/=100;var e,h,d;c=360*c%360/60;d=2*a*(0.5>b?b:1-b);a=d*(1-Y(c%2-1));b=e=
h=b-d/2;c=~~c;b+=[d,a,0,0,a,d][c];e+=[a,d,d,a,0,0][c];h+=[0,0,a,d,d,a][c];return oa(b,e,h,m)};a.rgb2hsb=function(c,a,b){b=D(c,a,b);c=b[0];a=b[1];b=b[2];var m,e;m=P(c,a,b);e=m-Q(c,a,b);c=((0==e?0:m==c?(a-b)/e:m==a?(b-c)/e+2:(c-a)/e+4)+360)%6*60/360;return{h:c,s:0==e?0:e/m,b:m,toString:qa}};a.rgb2hsl=function(c,a,b){b=D(c,a,b);c=b[0];a=b[1];b=b[2];var m,e,h;m=P(c,a,b);e=Q(c,a,b);h=m-e;c=((0==h?0:m==c?(a-b)/h:m==a?(b-c)/h+2:(c-a)/h+4)+360)%6*60/360;m=(m+e)/2;return{h:c,s:0==h?0:0.5>m?h/(2*m):h/(2-2*
m),l:m,toString:ra}};a.parsePathString=function(c){if(!c)return null;var b=a.path(c);if(b.arr)return a.path.clone(b.arr);var m={a:7,c:6,o:2,h:1,l:2,m:2,r:4,q:4,s:4,t:2,v:1,u:3,z:0},e=[];y(c,"array")&&y(c[0],"array")&&(e=a.path.clone(c));e.length||J(c).replace(W,function(c,a,b){var h=[];c=a.toLowerCase();b.replace(Z,function(c,a){a&&h.push(+a)});"m"==c&&2<h.length&&(e.push([a].concat(h.splice(0,2))),c="l",a="m"==a?"l":"L");"o"==c&&1==h.length&&e.push([a,h[0] ]);if("r"==c)e.push([a].concat(h));else for(;h.length>=
m[c]&&(e.push([a].concat(h.splice(0,m[c]))),m[c]););});e.toString=a.path.toString;b.arr=a.path.clone(e);return e};var O=a.parseTransformString=function(c){if(!c)return null;var b=[];y(c,"array")&&y(c[0],"array")&&(b=a.path.clone(c));b.length||J(c).replace(ma,function(c,a,m){var e=[];a.toLowerCase();m.replace(Z,function(c,a){a&&e.push(+a)});b.push([a].concat(e))});b.toString=a.path.toString;return b};a._.svgTransform2string=d;a._.rgTransform=RegExp("^[a-z][\t\n\x0B\f\r \u00a0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000\u2028\u2029]*-?\\.?\\d",
"i");a._.transform2matrix=f;a._unit2px=b;a._.getSomeDefs=u;a._.getSomeSVG=p;a.select=function(c){return x(G.doc.querySelector(c))};a.selectAll=function(c){c=G.doc.querySelectorAll(c);for(var b=(a.set||Array)(),m=0;m<c.length;m++)b.push(x(c[m]));return b};setInterval(function(){for(var c in E)if(E[h](c)){var a=E[c],b=a.node;("svg"!=a.type&&!b.ownerSVGElement||"svg"==a.type&&(!b.parentNode||"ownerSVGElement"in b.parentNode&&!b.ownerSVGElement))&&delete E[c]}},1E4);(function(c){function m(c){function a(c,
b){var m=v(c.node,b);(m=(m=m&&m.match(d))&&m[2])&&"#"==m.charAt()&&(m=m.substring(1))&&(f[m]=(f[m]||[]).concat(function(a){var m={};m[b]=ca(a);v(c.node,m)}))}function b(c){var a=v(c.node,"xlink:href");a&&"#"==a.charAt()&&(a=a.substring(1))&&(f[a]=(f[a]||[]).concat(function(a){c.attr("xlink:href","#"+a)}))}var e=c.selectAll("*"),h,d=/^\s*url\(("|'|)(.*)\1\)\s*$/;c=[];for(var f={},l=0,E=e.length;l<E;l++){h=e[l];a(h,"fill");a(h,"stroke");a(h,"filter");a(h,"mask");a(h,"clip-path");b(h);var t=v(h.node,
"id");t&&(v(h.node,{id:h.id}),c.push({old:t,id:h.id}))}l=0;for(E=c.length;l<E;l++)if(e=f[c[l].old])for(h=0,t=e.length;h<t;h++)e[h](c[l].id)}function e(c,a,b){return function(m){m=m.slice(c,a);1==m.length&&(m=m[0]);return b?b(m):m}}function d(c){return function(){var a=c?"<"+this.type:"",b=this.node.attributes,m=this.node.childNodes;if(c)for(var e=0,h=b.length;e<h;e++)a+=" "+b[e].name+'="'+b[e].value.replace(/"/g,'\\"')+'"';if(m.length){c&&(a+=">");e=0;for(h=m.length;e<h;e++)3==m[e].nodeType?a+=m[e].nodeValue:
1==m[e].nodeType&&(a+=x(m[e]).toString());c&&(a+="</"+this.type+">")}else c&&(a+="/>");return a}}c.attr=function(c,a){if(!c)return this;if(y(c,"string"))if(1<arguments.length){var b={};b[c]=a;c=b}else return k("snap.util.getattr."+c,this).firstDefined();for(var m in c)c[h](m)&&k("snap.util.attr."+m,this,c[m]);return this};c.getBBox=function(c){if(!a.Matrix||!a.path)return this.node.getBBox();var b=this,m=new a.Matrix;if(b.removed)return a._.box();for(;"use"==b.type;)if(c||(m=m.add(b.transform().localMatrix.translate(b.attr("x")||
0,b.attr("y")||0))),b.original)b=b.original;else var e=b.attr("xlink:href"),b=b.original=b.node.ownerDocument.getElementById(e.substring(e.indexOf("#")+1));var e=b._,h=a.path.get[b.type]||a.path.get.deflt;try{if(c)return e.bboxwt=h?a.path.getBBox(b.realPath=h(b)):a._.box(b.node.getBBox()),a._.box(e.bboxwt);b.realPath=h(b);b.matrix=b.transform().localMatrix;e.bbox=a.path.getBBox(a.path.map(b.realPath,m.add(b.matrix)));return a._.box(e.bbox)}catch(d){return a._.box()}};var f=function(){return this.string};
c.transform=function(c){var b=this._;if(null==c){var m=this;c=new a.Matrix(this.node.getCTM());for(var e=n(this),h=[e],d=new a.Matrix,l=e.toTransformString(),b=J(e)==J(this.matrix)?J(b.transform):l;"svg"!=m.type&&(m=m.parent());)h.push(n(m));for(m=h.length;m--;)d.add(h[m]);return{string:b,globalMatrix:c,totalMatrix:d,localMatrix:e,diffMatrix:c.clone().add(e.invert()),global:c.toTransformString(),total:d.toTransformString(),local:l,toString:f}}c instanceof a.Matrix?this.matrix=c:n(this,c);this.node&&
("linearGradient"==this.type||"radialGradient"==this.type?v(this.node,{gradientTransform:this.matrix}):"pattern"==this.type?v(this.node,{patternTransform:this.matrix}):v(this.node,{transform:this.matrix}));return this};c.parent=function(){return x(this.node.parentNode)};c.append=c.add=function(c){if(c){if("set"==c.type){var a=this;c.forEach(function(c){a.add(c)});return this}c=x(c);this.node.appendChild(c.node);c.paper=this.paper}return this};c.appendTo=function(c){c&&(c=x(c),c.append(this));return this};
c.prepend=function(c){if(c){if("set"==c.type){var a=this,b;c.forEach(function(c){b?b.after(c):a.prepend(c);b=c});return this}c=x(c);var m=c.parent();this.node.insertBefore(c.node,this.node.firstChild);this.add&&this.add();c.paper=this.paper;this.parent()&&this.parent().add();m&&m.add()}return this};c.prependTo=function(c){c=x(c);c.prepend(this);return this};c.before=function(c){if("set"==c.type){var a=this;c.forEach(function(c){var b=c.parent();a.node.parentNode.insertBefore(c.node,a.node);b&&b.add()});
this.parent().add();return this}c=x(c);var b=c.parent();this.node.parentNode.insertBefore(c.node,this.node);this.parent()&&this.parent().add();b&&b.add();c.paper=this.paper;return this};c.after=function(c){c=x(c);var a=c.parent();this.node.nextSibling?this.node.parentNode.insertBefore(c.node,this.node.nextSibling):this.node.parentNode.appendChild(c.node);this.parent()&&this.parent().add();a&&a.add();c.paper=this.paper;return this};c.insertBefore=function(c){c=x(c);var a=this.parent();c.node.parentNode.insertBefore(this.node,
c.node);this.paper=c.paper;a&&a.add();c.parent()&&c.parent().add();return this};c.insertAfter=function(c){c=x(c);var a=this.parent();c.node.parentNode.insertBefore(this.node,c.node.nextSibling);this.paper=c.paper;a&&a.add();c.parent()&&c.parent().add();return this};c.remove=function(){var c=this.parent();this.node.parentNode&&this.node.parentNode.removeChild(this.node);delete this.paper;this.removed=!0;c&&c.add();return this};c.select=function(c){return x(this.node.querySelector(c))};c.selectAll=
function(c){c=this.node.querySelectorAll(c);for(var b=(a.set||Array)(),m=0;m<c.length;m++)b.push(x(c[m]));return b};c.asPX=function(c,a){null==a&&(a=this.attr(c));return+b(this,c,a)};c.use=function(){var c,a=this.node.id;a||(a=this.id,v(this.node,{id:a}));c="linearGradient"==this.type||"radialGradient"==this.type||"pattern"==this.type?r(this.type,this.node.parentNode):r("use",this.node.parentNode);v(c.node,{"xlink:href":"#"+a});c.original=this;return c};var l=/\S+/g;c.addClass=function(c){var a=(c||
"").match(l)||[];c=this.node;var b=c.className.baseVal,m=b.match(l)||[],e,h,d;if(a.length){for(e=0;d=a[e++];)h=m.indexOf(d),~h||m.push(d);a=m.join(" ");b!=a&&(c.className.baseVal=a)}return this};c.removeClass=function(c){var a=(c||"").match(l)||[];c=this.node;var b=c.className.baseVal,m=b.match(l)||[],e,h;if(m.length){for(e=0;h=a[e++];)h=m.indexOf(h),~h&&m.splice(h,1);a=m.join(" ");b!=a&&(c.className.baseVal=a)}return this};c.hasClass=function(c){return!!~(this.node.className.baseVal.match(l)||[]).indexOf(c)};
c.toggleClass=function(c,a){if(null!=a)return a?this.addClass(c):this.removeClass(c);var b=(c||"").match(l)||[],m=this.node,e=m.className.baseVal,h=e.match(l)||[],d,f,E;for(d=0;E=b[d++];)f=h.indexOf(E),~f?h.splice(f,1):h.push(E);b=h.join(" ");e!=b&&(m.className.baseVal=b);return this};c.clone=function(){var c=x(this.node.cloneNode(!0));v(c.node,"id")&&v(c.node,{id:c.id});m(c);c.insertAfter(this);return c};c.toDefs=function(){u(this).appendChild(this.node);return this};c.pattern=c.toPattern=function(c,
a,b,m){var e=r("pattern",u(this));null==c&&(c=this.getBBox());y(c,"object")&&"x"in c&&(a=c.y,b=c.width,m=c.height,c=c.x);v(e.node,{x:c,y:a,width:b,height:m,patternUnits:"userSpaceOnUse",id:e.id,viewBox:[c,a,b,m].join(" ")});e.node.appendChild(this.node);return e};c.marker=function(c,a,b,m,e,h){var d=r("marker",u(this));null==c&&(c=this.getBBox());y(c,"object")&&"x"in c&&(a=c.y,b=c.width,m=c.height,e=c.refX||c.cx,h=c.refY||c.cy,c=c.x);v(d.node,{viewBox:[c,a,b,m].join(" "),markerWidth:b,markerHeight:m,
orient:"auto",refX:e||0,refY:h||0,id:d.id});d.node.appendChild(this.node);return d};var E=function(c,a,b,m){"function"!=typeof b||b.length||(m=b,b=L.linear);this.attr=c;this.dur=a;b&&(this.easing=b);m&&(this.callback=m)};a._.Animation=E;a.animation=function(c,a,b,m){return new E(c,a,b,m)};c.inAnim=function(){var c=[],a;for(a in this.anims)this.anims[h](a)&&function(a){c.push({anim:new E(a._attrs,a.dur,a.easing,a._callback),mina:a,curStatus:a.status(),status:function(c){return a.status(c)},stop:function(){a.stop()}})}(this.anims[a]);
return c};a.animate=function(c,a,b,m,e,h){"function"!=typeof e||e.length||(h=e,e=L.linear);var d=L.time();c=L(c,a,d,d+m,L.time,b,e);h&&k.once("mina.finish."+c.id,h);return c};c.stop=function(){for(var c=this.inAnim(),a=0,b=c.length;a<b;a++)c[a].stop();return this};c.animate=function(c,a,b,m){"function"!=typeof b||b.length||(m=b,b=L.linear);c instanceof E&&(m=c.callback,b=c.easing,a=b.dur,c=c.attr);var d=[],f=[],l={},t,ca,n,T=this,q;for(q in c)if(c[h](q)){T.equal?(n=T.equal(q,J(c[q])),t=n.from,ca=
n.to,n=n.f):(t=+T.attr(q),ca=+c[q]);var la=y(t,"array")?t.length:1;l[q]=e(d.length,d.length+la,n);d=d.concat(t);f=f.concat(ca)}t=L.time();var p=L(d,f,t,t+a,L.time,function(c){var a={},b;for(b in l)l[h](b)&&(a[b]=l[b](c));T.attr(a)},b);T.anims[p.id]=p;p._attrs=c;p._callback=m;k("snap.animcreated."+T.id,p);k.once("mina.finish."+p.id,function(){delete T.anims[p.id];m&&m.call(T)});k.once("mina.stop."+p.id,function(){delete T.anims[p.id]});return T};var T={};c.data=function(c,b){var m=T[this.id]=T[this.id]||
{};if(0==arguments.length)return k("snap.data.get."+this.id,this,m,null),m;if(1==arguments.length){if(a.is(c,"object")){for(var e in c)c[h](e)&&this.data(e,c[e]);return this}k("snap.data.get."+this.id,this,m[c],c);return m[c]}m[c]=b;k("snap.data.set."+this.id,this,b,c);return this};c.removeData=function(c){null==c?T[this.id]={}:T[this.id]&&delete T[this.id][c];return this};c.outerSVG=c.toString=d(1);c.innerSVG=d()})(e.prototype);a.parse=function(c){var a=G.doc.createDocumentFragment(),b=!0,m=G.doc.createElement("div");
c=J(c);c.match(/^\s*<\s*svg(?:\s|>)/)||(c="<svg>"+c+"</svg>",b=!1);m.innerHTML=c;if(c=m.getElementsByTagName("svg")[0])if(b)a=c;else for(;c.firstChild;)a.appendChild(c.firstChild);m.innerHTML=aa;return new l(a)};l.prototype.select=e.prototype.select;l.prototype.selectAll=e.prototype.selectAll;a.fragment=function(){for(var c=Array.prototype.slice.call(arguments,0),b=G.doc.createDocumentFragment(),m=0,e=c.length;m<e;m++){var h=c[m];h.node&&h.node.nodeType&&b.appendChild(h.node);h.nodeType&&b.appendChild(h);
"string"==typeof h&&b.appendChild(a.parse(h).node)}return new l(b)};a._.make=r;a._.wrap=x;s.prototype.el=function(c,a){var b=r(c,this.node);a&&b.attr(a);return b};k.on("snap.util.getattr",function(){var c=k.nt(),c=c.substring(c.lastIndexOf(".")+1),a=c.replace(/[A-Z]/g,function(c){return"-"+c.toLowerCase()});return pa[h](a)?this.node.ownerDocument.defaultView.getComputedStyle(this.node,null).getPropertyValue(a):v(this.node,c)});var pa={"alignment-baseline":0,"baseline-shift":0,clip:0,"clip-path":0,
"clip-rule":0,color:0,"color-interpolation":0,"color-interpolation-filters":0,"color-profile":0,"color-rendering":0,cursor:0,direction:0,display:0,"dominant-baseline":0,"enable-background":0,fill:0,"fill-opacity":0,"fill-rule":0,filter:0,"flood-color":0,"flood-opacity":0,font:0,"font-family":0,"font-size":0,"font-size-adjust":0,"font-stretch":0,"font-style":0,"font-variant":0,"font-weight":0,"glyph-orientation-horizontal":0,"glyph-orientation-vertical":0,"image-rendering":0,kerning:0,"letter-spacing":0,
"lighting-color":0,marker:0,"marker-end":0,"marker-mid":0,"marker-start":0,mask:0,opacity:0,overflow:0,"pointer-events":0,"shape-rendering":0,"stop-color":0,"stop-opacity":0,stroke:0,"stroke-dasharray":0,"stroke-dashoffset":0,"stroke-linecap":0,"stroke-linejoin":0,"stroke-miterlimit":0,"stroke-opacity":0,"stroke-width":0,"text-anchor":0,"text-decoration":0,"text-rendering":0,"unicode-bidi":0,visibility:0,"word-spacing":0,"writing-mode":0};k.on("snap.util.attr",function(c){var a=k.nt(),b={},a=a.substring(a.lastIndexOf(".")+
1);b[a]=c;var m=a.replace(/-(\w)/gi,function(c,a){return a.toUpperCase()}),a=a.replace(/[A-Z]/g,function(c){return"-"+c.toLowerCase()});pa[h](a)?this.node.style[m]=null==c?aa:c:v(this.node,b)});a.ajax=function(c,a,b,m){var e=new XMLHttpRequest,h=V();if(e){if(y(a,"function"))m=b,b=a,a=null;else if(y(a,"object")){var d=[],f;for(f in a)a.hasOwnProperty(f)&&d.push(encodeURIComponent(f)+"="+encodeURIComponent(a[f]));a=d.join("&")}e.open(a?"POST":"GET",c,!0);a&&(e.setRequestHeader("X-Requested-With","XMLHttpRequest"),
e.setRequestHeader("Content-type","application/x-www-form-urlencoded"));b&&(k.once("snap.ajax."+h+".0",b),k.once("snap.ajax."+h+".200",b),k.once("snap.ajax."+h+".304",b));e.onreadystatechange=function(){4==e.readyState&&k("snap.ajax."+h+"."+e.status,m,e)};if(4==e.readyState)return e;e.send(a);return e}};a.load=function(c,b,m){a.ajax(c,function(c){c=a.parse(c.responseText);m?b.call(m,c):b(c)})};a.getElementByPoint=function(c,a){var b,m,e=G.doc.elementFromPoint(c,a);if(G.win.opera&&"svg"==e.tagName){b=
e;m=b.getBoundingClientRect();b=b.ownerDocument;var h=b.body,d=b.documentElement;b=m.top+(g.win.pageYOffset||d.scrollTop||h.scrollTop)-(d.clientTop||h.clientTop||0);m=m.left+(g.win.pageXOffset||d.scrollLeft||h.scrollLeft)-(d.clientLeft||h.clientLeft||0);h=e.createSVGRect();h.x=c-m;h.y=a-b;h.width=h.height=1;b=e.getIntersectionList(h,null);b.length&&(e=b[b.length-1])}return e?x(e):null};a.plugin=function(c){c(a,e,s,G,l)};return G.win.Snap=a}();C.plugin(function(a,k,y,M,A){function w(a,d,f,b,q,e){null==
d&&"[object SVGMatrix]"==z.call(a)?(this.a=a.a,this.b=a.b,this.c=a.c,this.d=a.d,this.e=a.e,this.f=a.f):null!=a?(this.a=+a,this.b=+d,this.c=+f,this.d=+b,this.e=+q,this.f=+e):(this.a=1,this.c=this.b=0,this.d=1,this.f=this.e=0)}var z=Object.prototype.toString,d=String,f=Math;(function(n){function k(a){return a[0]*a[0]+a[1]*a[1]}function p(a){var d=f.sqrt(k(a));a[0]&&(a[0]/=d);a[1]&&(a[1]/=d)}n.add=function(a,d,e,f,n,p){var k=[[],[],[] ],u=[[this.a,this.c,this.e],[this.b,this.d,this.f],[0,0,1] ];d=[[a,
e,n],[d,f,p],[0,0,1] ];a&&a instanceof w&&(d=[[a.a,a.c,a.e],[a.b,a.d,a.f],[0,0,1] ]);for(a=0;3>a;a++)for(e=0;3>e;e++){for(f=n=0;3>f;f++)n+=u[a][f]*d[f][e];k[a][e]=n}this.a=k[0][0];this.b=k[1][0];this.c=k[0][1];this.d=k[1][1];this.e=k[0][2];this.f=k[1][2];return this};n.invert=function(){var a=this.a*this.d-this.b*this.c;return new w(this.d/a,-this.b/a,-this.c/a,this.a/a,(this.c*this.f-this.d*this.e)/a,(this.b*this.e-this.a*this.f)/a)};n.clone=function(){return new w(this.a,this.b,this.c,this.d,this.e,
this.f)};n.translate=function(a,d){return this.add(1,0,0,1,a,d)};n.scale=function(a,d,e,f){null==d&&(d=a);(e||f)&&this.add(1,0,0,1,e,f);this.add(a,0,0,d,0,0);(e||f)&&this.add(1,0,0,1,-e,-f);return this};n.rotate=function(b,d,e){b=a.rad(b);d=d||0;e=e||0;var l=+f.cos(b).toFixed(9);b=+f.sin(b).toFixed(9);this.add(l,b,-b,l,d,e);return this.add(1,0,0,1,-d,-e)};n.x=function(a,d){return a*this.a+d*this.c+this.e};n.y=function(a,d){return a*this.b+d*this.d+this.f};n.get=function(a){return+this[d.fromCharCode(97+
a)].toFixed(4)};n.toString=function(){return"matrix("+[this.get(0),this.get(1),this.get(2),this.get(3),this.get(4),this.get(5)].join()+")"};n.offset=function(){return[this.e.toFixed(4),this.f.toFixed(4)]};n.determinant=function(){return this.a*this.d-this.b*this.c};n.split=function(){var b={};b.dx=this.e;b.dy=this.f;var d=[[this.a,this.c],[this.b,this.d] ];b.scalex=f.sqrt(k(d[0]));p(d[0]);b.shear=d[0][0]*d[1][0]+d[0][1]*d[1][1];d[1]=[d[1][0]-d[0][0]*b.shear,d[1][1]-d[0][1]*b.shear];b.scaley=f.sqrt(k(d[1]));
p(d[1]);b.shear/=b.scaley;0>this.determinant()&&(b.scalex=-b.scalex);var e=-d[0][1],d=d[1][1];0>d?(b.rotate=a.deg(f.acos(d)),0>e&&(b.rotate=360-b.rotate)):b.rotate=a.deg(f.asin(e));b.isSimple=!+b.shear.toFixed(9)&&(b.scalex.toFixed(9)==b.scaley.toFixed(9)||!b.rotate);b.isSuperSimple=!+b.shear.toFixed(9)&&b.scalex.toFixed(9)==b.scaley.toFixed(9)&&!b.rotate;b.noRotation=!+b.shear.toFixed(9)&&!b.rotate;return b};n.toTransformString=function(a){a=a||this.split();if(+a.shear.toFixed(9))return"m"+[this.get(0),
this.get(1),this.get(2),this.get(3),this.get(4),this.get(5)];a.scalex=+a.scalex.toFixed(4);a.scaley=+a.scaley.toFixed(4);a.rotate=+a.rotate.toFixed(4);return(a.dx||a.dy?"t"+[+a.dx.toFixed(4),+a.dy.toFixed(4)]:"")+(1!=a.scalex||1!=a.scaley?"s"+[a.scalex,a.scaley,0,0]:"")+(a.rotate?"r"+[+a.rotate.toFixed(4),0,0]:"")}})(w.prototype);a.Matrix=w;a.matrix=function(a,d,f,b,k,e){return new w(a,d,f,b,k,e)}});C.plugin(function(a,v,y,M,A){function w(h){return function(d){k.stop();d instanceof A&&1==d.node.childNodes.length&&
("radialGradient"==d.node.firstChild.tagName||"linearGradient"==d.node.firstChild.tagName||"pattern"==d.node.firstChild.tagName)&&(d=d.node.firstChild,b(this).appendChild(d),d=u(d));if(d instanceof v)if("radialGradient"==d.type||"linearGradient"==d.type||"pattern"==d.type){d.node.id||e(d.node,{id:d.id});var f=l(d.node.id)}else f=d.attr(h);else f=a.color(d),f.error?(f=a(b(this).ownerSVGElement).gradient(d))?(f.node.id||e(f.node,{id:f.id}),f=l(f.node.id)):f=d:f=r(f);d={};d[h]=f;e(this.node,d);this.node.style[h]=
x}}function z(a){k.stop();a==+a&&(a+="px");this.node.style.fontSize=a}function d(a){var b=[];a=a.childNodes;for(var e=0,f=a.length;e<f;e++){var l=a[e];3==l.nodeType&&b.push(l.nodeValue);"tspan"==l.tagName&&(1==l.childNodes.length&&3==l.firstChild.nodeType?b.push(l.firstChild.nodeValue):b.push(d(l)))}return b}function f(){k.stop();return this.node.style.fontSize}var n=a._.make,u=a._.wrap,p=a.is,b=a._.getSomeDefs,q=/^url\(#?([^)]+)\)$/,e=a._.$,l=a.url,r=String,s=a._.separator,x="";k.on("snap.util.attr.mask",
function(a){if(a instanceof v||a instanceof A){k.stop();a instanceof A&&1==a.node.childNodes.length&&(a=a.node.firstChild,b(this).appendChild(a),a=u(a));if("mask"==a.type)var d=a;else d=n("mask",b(this)),d.node.appendChild(a.node);!d.node.id&&e(d.node,{id:d.id});e(this.node,{mask:l(d.id)})}});(function(a){k.on("snap.util.attr.clip",a);k.on("snap.util.attr.clip-path",a);k.on("snap.util.attr.clipPath",a)})(function(a){if(a instanceof v||a instanceof A){k.stop();if("clipPath"==a.type)var d=a;else d=
n("clipPath",b(this)),d.node.appendChild(a.node),!d.node.id&&e(d.node,{id:d.id});e(this.node,{"clip-path":l(d.id)})}});k.on("snap.util.attr.fill",w("fill"));k.on("snap.util.attr.stroke",w("stroke"));var G=/^([lr])(?:\(([^)]*)\))?(.*)$/i;k.on("snap.util.grad.parse",function(a){a=r(a);var b=a.match(G);if(!b)return null;a=b[1];var e=b[2],b=b[3],e=e.split(/\s*,\s*/).map(function(a){return+a==a?+a:a});1==e.length&&0==e[0]&&(e=[]);b=b.split("-");b=b.map(function(a){a=a.split(":");var b={color:a[0]};a[1]&&
(b.offset=parseFloat(a[1]));return b});return{type:a,params:e,stops:b}});k.on("snap.util.attr.d",function(b){k.stop();p(b,"array")&&p(b[0],"array")&&(b=a.path.toString.call(b));b=r(b);b.match(/[ruo]/i)&&(b=a.path.toAbsolute(b));e(this.node,{d:b})})(-1);k.on("snap.util.attr.#text",function(a){k.stop();a=r(a);for(a=M.doc.createTextNode(a);this.node.firstChild;)this.node.removeChild(this.node.firstChild);this.node.appendChild(a)})(-1);k.on("snap.util.attr.path",function(a){k.stop();this.attr({d:a})})(-1);
k.on("snap.util.attr.class",function(a){k.stop();this.node.className.baseVal=a})(-1);k.on("snap.util.attr.viewBox",function(a){a=p(a,"object")&&"x"in a?[a.x,a.y,a.width,a.height].join(" "):p(a,"array")?a.join(" "):a;e(this.node,{viewBox:a});k.stop()})(-1);k.on("snap.util.attr.transform",function(a){this.transform(a);k.stop()})(-1);k.on("snap.util.attr.r",function(a){"rect"==this.type&&(k.stop(),e(this.node,{rx:a,ry:a}))})(-1);k.on("snap.util.attr.textpath",function(a){k.stop();if("text"==this.type){var d,
f;if(!a&&this.textPath){for(a=this.textPath;a.node.firstChild;)this.node.appendChild(a.node.firstChild);a.remove();delete this.textPath}else if(p(a,"string")?(d=b(this),a=u(d.parentNode).path(a),d.appendChild(a.node),d=a.id,a.attr({id:d})):(a=u(a),a instanceof v&&(d=a.attr("id"),d||(d=a.id,a.attr({id:d})))),d)if(a=this.textPath,f=this.node,a)a.attr({"xlink:href":"#"+d});else{for(a=e("textPath",{"xlink:href":"#"+d});f.firstChild;)a.appendChild(f.firstChild);f.appendChild(a);this.textPath=u(a)}}})(-1);
k.on("snap.util.attr.text",function(a){if("text"==this.type){for(var b=this.node,d=function(a){var b=e("tspan");if(p(a,"array"))for(var f=0;f<a.length;f++)b.appendChild(d(a[f]));else b.appendChild(M.doc.createTextNode(a));b.normalize&&b.normalize();return b};b.firstChild;)b.removeChild(b.firstChild);for(a=d(a);a.firstChild;)b.appendChild(a.firstChild)}k.stop()})(-1);k.on("snap.util.attr.fontSize",z)(-1);k.on("snap.util.attr.font-size",z)(-1);k.on("snap.util.getattr.transform",function(){k.stop();
return this.transform()})(-1);k.on("snap.util.getattr.textpath",function(){k.stop();return this.textPath})(-1);(function(){function b(d){return function(){k.stop();var b=M.doc.defaultView.getComputedStyle(this.node,null).getPropertyValue("marker-"+d);return"none"==b?b:a(M.doc.getElementById(b.match(q)[1]))}}function d(a){return function(b){k.stop();var d="marker"+a.charAt(0).toUpperCase()+a.substring(1);if(""==b||!b)this.node.style[d]="none";else if("marker"==b.type){var f=b.node.id;f||e(b.node,{id:b.id});
this.node.style[d]=l(f)}}}k.on("snap.util.getattr.marker-end",b("end"))(-1);k.on("snap.util.getattr.markerEnd",b("end"))(-1);k.on("snap.util.getattr.marker-start",b("start"))(-1);k.on("snap.util.getattr.markerStart",b("start"))(-1);k.on("snap.util.getattr.marker-mid",b("mid"))(-1);k.on("snap.util.getattr.markerMid",b("mid"))(-1);k.on("snap.util.attr.marker-end",d("end"))(-1);k.on("snap.util.attr.markerEnd",d("end"))(-1);k.on("snap.util.attr.marker-start",d("start"))(-1);k.on("snap.util.attr.markerStart",
d("start"))(-1);k.on("snap.util.attr.marker-mid",d("mid"))(-1);k.on("snap.util.attr.markerMid",d("mid"))(-1)})();k.on("snap.util.getattr.r",function(){if("rect"==this.type&&e(this.node,"rx")==e(this.node,"ry"))return k.stop(),e(this.node,"rx")})(-1);k.on("snap.util.getattr.text",function(){if("text"==this.type||"tspan"==this.type){k.stop();var a=d(this.node);return 1==a.length?a[0]:a}})(-1);k.on("snap.util.getattr.#text",function(){return this.node.textContent})(-1);k.on("snap.util.getattr.viewBox",
function(){k.stop();var b=e(this.node,"viewBox");if(b)return b=b.split(s),a._.box(+b[0],+b[1],+b[2],+b[3])})(-1);k.on("snap.util.getattr.points",function(){var a=e(this.node,"points");k.stop();if(a)return a.split(s)})(-1);k.on("snap.util.getattr.path",function(){var a=e(this.node,"d");k.stop();return a})(-1);k.on("snap.util.getattr.class",function(){return this.node.className.baseVal})(-1);k.on("snap.util.getattr.fontSize",f)(-1);k.on("snap.util.getattr.font-size",f)(-1)});C.plugin(function(a,v,y,
M,A){function w(a){return a}function z(a){return function(b){return+b.toFixed(3)+a}}var d={"+":function(a,b){return a+b},"-":function(a,b){return a-b},"/":function(a,b){return a/b},"*":function(a,b){return a*b}},f=String,n=/[a-z]+$/i,u=/^\s*([+\-\/*])\s*=\s*([\d.eE+\-]+)\s*([^\d\s]+)?\s*$/;k.on("snap.util.attr",function(a){if(a=f(a).match(u)){var b=k.nt(),b=b.substring(b.lastIndexOf(".")+1),q=this.attr(b),e={};k.stop();var l=a[3]||"",r=q.match(n),s=d[a[1] ];r&&r==l?a=s(parseFloat(q),+a[2]):(q=this.asPX(b),
a=s(this.asPX(b),this.asPX(b,a[2]+l)));isNaN(q)||isNaN(a)||(e[b]=a,this.attr(e))}})(-10);k.on("snap.util.equal",function(a,b){var q=f(this.attr(a)||""),e=f(b).match(u);if(e){k.stop();var l=e[3]||"",r=q.match(n),s=d[e[1] ];if(r&&r==l)return{from:parseFloat(q),to:s(parseFloat(q),+e[2]),f:z(r)};q=this.asPX(a);return{from:q,to:s(q,this.asPX(a,e[2]+l)),f:w}}})(-10)});C.plugin(function(a,v,y,M,A){var w=y.prototype,z=a.is;w.rect=function(a,d,k,p,b,q){var e;null==q&&(q=b);z(a,"object")&&"[object Object]"==
a?e=a:null!=a&&(e={x:a,y:d,width:k,height:p},null!=b&&(e.rx=b,e.ry=q));return this.el("rect",e)};w.circle=function(a,d,k){var p;z(a,"object")&&"[object Object]"==a?p=a:null!=a&&(p={cx:a,cy:d,r:k});return this.el("circle",p)};var d=function(){function a(){this.parentNode.removeChild(this)}return function(d,k){var p=M.doc.createElement("img"),b=M.doc.body;p.style.cssText="position:absolute;left:-9999em;top:-9999em";p.onload=function(){k.call(p);p.onload=p.onerror=null;b.removeChild(p)};p.onerror=a;
b.appendChild(p);p.src=d}}();w.image=function(f,n,k,p,b){var q=this.el("image");if(z(f,"object")&&"src"in f)q.attr(f);else if(null!=f){var e={"xlink:href":f,preserveAspectRatio:"none"};null!=n&&null!=k&&(e.x=n,e.y=k);null!=p&&null!=b?(e.width=p,e.height=b):d(f,function(){a._.$(q.node,{width:this.offsetWidth,height:this.offsetHeight})});a._.$(q.node,e)}return q};w.ellipse=function(a,d,k,p){var b;z(a,"object")&&"[object Object]"==a?b=a:null!=a&&(b={cx:a,cy:d,rx:k,ry:p});return this.el("ellipse",b)};
w.path=function(a){var d;z(a,"object")&&!z(a,"array")?d=a:a&&(d={d:a});return this.el("path",d)};w.group=w.g=function(a){var d=this.el("g");1==arguments.length&&a&&!a.type?d.attr(a):arguments.length&&d.add(Array.prototype.slice.call(arguments,0));return d};w.svg=function(a,d,k,p,b,q,e,l){var r={};z(a,"object")&&null==d?r=a:(null!=a&&(r.x=a),null!=d&&(r.y=d),null!=k&&(r.width=k),null!=p&&(r.height=p),null!=b&&null!=q&&null!=e&&null!=l&&(r.viewBox=[b,q,e,l]));return this.el("svg",r)};w.mask=function(a){var d=
this.el("mask");1==arguments.length&&a&&!a.type?d.attr(a):arguments.length&&d.add(Array.prototype.slice.call(arguments,0));return d};w.ptrn=function(a,d,k,p,b,q,e,l){if(z(a,"object"))var r=a;else arguments.length?(r={},null!=a&&(r.x=a),null!=d&&(r.y=d),null!=k&&(r.width=k),null!=p&&(r.height=p),null!=b&&null!=q&&null!=e&&null!=l&&(r.viewBox=[b,q,e,l])):r={patternUnits:"userSpaceOnUse"};return this.el("pattern",r)};w.use=function(a){return null!=a?(make("use",this.node),a instanceof v&&(a.attr("id")||
a.attr({id:ID()}),a=a.attr("id")),this.el("use",{"xlink:href":a})):v.prototype.use.call(this)};w.text=function(a,d,k){var p={};z(a,"object")?p=a:null!=a&&(p={x:a,y:d,text:k||""});return this.el("text",p)};w.line=function(a,d,k,p){var b={};z(a,"object")?b=a:null!=a&&(b={x1:a,x2:k,y1:d,y2:p});return this.el("line",b)};w.polyline=function(a){1<arguments.length&&(a=Array.prototype.slice.call(arguments,0));var d={};z(a,"object")&&!z(a,"array")?d=a:null!=a&&(d={points:a});return this.el("polyline",d)};
w.polygon=function(a){1<arguments.length&&(a=Array.prototype.slice.call(arguments,0));var d={};z(a,"object")&&!z(a,"array")?d=a:null!=a&&(d={points:a});return this.el("polygon",d)};(function(){function d(){return this.selectAll("stop")}function n(b,d){var f=e("stop"),k={offset:+d+"%"};b=a.color(b);k["stop-color"]=b.hex;1>b.opacity&&(k["stop-opacity"]=b.opacity);e(f,k);this.node.appendChild(f);return this}function u(){if("linearGradient"==this.type){var b=e(this.node,"x1")||0,d=e(this.node,"x2")||
1,f=e(this.node,"y1")||0,k=e(this.node,"y2")||0;return a._.box(b,f,math.abs(d-b),math.abs(k-f))}b=this.node.r||0;return a._.box((this.node.cx||0.5)-b,(this.node.cy||0.5)-b,2*b,2*b)}function p(a,d){function f(a,b){for(var d=(b-u)/(a-w),e=w;e<a;e++)h[e].offset=+(+u+d*(e-w)).toFixed(2);w=a;u=b}var n=k("snap.util.grad.parse",null,d).firstDefined(),p;if(!n)return null;n.params.unshift(a);p="l"==n.type.toLowerCase()?b.apply(0,n.params):q.apply(0,n.params);n.type!=n.type.toLowerCase()&&e(p.node,{gradientUnits:"userSpaceOnUse"});
var h=n.stops,n=h.length,u=0,w=0;n--;for(var v=0;v<n;v++)"offset"in h[v]&&f(v,h[v].offset);h[n].offset=h[n].offset||100;f(n,h[n].offset);for(v=0;v<=n;v++){var y=h[v];p.addStop(y.color,y.offset)}return p}function b(b,k,p,q,w){b=a._.make("linearGradient",b);b.stops=d;b.addStop=n;b.getBBox=u;null!=k&&e(b.node,{x1:k,y1:p,x2:q,y2:w});return b}function q(b,k,p,q,w,h){b=a._.make("radialGradient",b);b.stops=d;b.addStop=n;b.getBBox=u;null!=k&&e(b.node,{cx:k,cy:p,r:q});null!=w&&null!=h&&e(b.node,{fx:w,fy:h});
return b}var e=a._.$;w.gradient=function(a){return p(this.defs,a)};w.gradientLinear=function(a,d,e,f){return b(this.defs,a,d,e,f)};w.gradientRadial=function(a,b,d,e,f){return q(this.defs,a,b,d,e,f)};w.toString=function(){var b=this.node.ownerDocument,d=b.createDocumentFragment(),b=b.createElement("div"),e=this.node.cloneNode(!0);d.appendChild(b);b.appendChild(e);a._.$(e,{xmlns:"http://www.w3.org/2000/svg"});b=b.innerHTML;d.removeChild(d.firstChild);return b};w.clear=function(){for(var a=this.node.firstChild,
b;a;)b=a.nextSibling,"defs"!=a.tagName?a.parentNode.removeChild(a):w.clear.call({node:a}),a=b}})()});C.plugin(function(a,k,y,M){function A(a){var b=A.ps=A.ps||{};b[a]?b[a].sleep=100:b[a]={sleep:100};setTimeout(function(){for(var d in b)b[L](d)&&d!=a&&(b[d].sleep--,!b[d].sleep&&delete b[d])});return b[a]}function w(a,b,d,e){null==a&&(a=b=d=e=0);null==b&&(b=a.y,d=a.width,e=a.height,a=a.x);return{x:a,y:b,width:d,w:d,height:e,h:e,x2:a+d,y2:b+e,cx:a+d/2,cy:b+e/2,r1:F.min(d,e)/2,r2:F.max(d,e)/2,r0:F.sqrt(d*
d+e*e)/2,path:s(a,b,d,e),vb:[a,b,d,e].join(" ")}}function z(){return this.join(",").replace(N,"$1")}function d(a){a=C(a);a.toString=z;return a}function f(a,b,d,h,f,k,l,n,p){if(null==p)return e(a,b,d,h,f,k,l,n);if(0>p||e(a,b,d,h,f,k,l,n)<p)p=void 0;else{var q=0.5,O=1-q,s;for(s=e(a,b,d,h,f,k,l,n,O);0.01<Z(s-p);)q/=2,O+=(s<p?1:-1)*q,s=e(a,b,d,h,f,k,l,n,O);p=O}return u(a,b,d,h,f,k,l,n,p)}function n(b,d){function e(a){return+(+a).toFixed(3)}return a._.cacher(function(a,h,l){a instanceof k&&(a=a.attr("d"));
a=I(a);for(var n,p,D,q,O="",s={},c=0,t=0,r=a.length;t<r;t++){D=a[t];if("M"==D[0])n=+D[1],p=+D[2];else{q=f(n,p,D[1],D[2],D[3],D[4],D[5],D[6]);if(c+q>h){if(d&&!s.start){n=f(n,p,D[1],D[2],D[3],D[4],D[5],D[6],h-c);O+=["C"+e(n.start.x),e(n.start.y),e(n.m.x),e(n.m.y),e(n.x),e(n.y)];if(l)return O;s.start=O;O=["M"+e(n.x),e(n.y)+"C"+e(n.n.x),e(n.n.y),e(n.end.x),e(n.end.y),e(D[5]),e(D[6])].join();c+=q;n=+D[5];p=+D[6];continue}if(!b&&!d)return n=f(n,p,D[1],D[2],D[3],D[4],D[5],D[6],h-c)}c+=q;n=+D[5];p=+D[6]}O+=
D.shift()+D}s.end=O;return n=b?c:d?s:u(n,p,D[0],D[1],D[2],D[3],D[4],D[5],1)},null,a._.clone)}function u(a,b,d,e,h,f,k,l,n){var p=1-n,q=ma(p,3),s=ma(p,2),c=n*n,t=c*n,r=q*a+3*s*n*d+3*p*n*n*h+t*k,q=q*b+3*s*n*e+3*p*n*n*f+t*l,s=a+2*n*(d-a)+c*(h-2*d+a),t=b+2*n*(e-b)+c*(f-2*e+b),x=d+2*n*(h-d)+c*(k-2*h+d),c=e+2*n*(f-e)+c*(l-2*f+e);a=p*a+n*d;b=p*b+n*e;h=p*h+n*k;f=p*f+n*l;l=90-180*F.atan2(s-x,t-c)/S;return{x:r,y:q,m:{x:s,y:t},n:{x:x,y:c},start:{x:a,y:b},end:{x:h,y:f},alpha:l}}function p(b,d,e,h,f,n,k,l){a.is(b,
"array")||(b=[b,d,e,h,f,n,k,l]);b=U.apply(null,b);return w(b.min.x,b.min.y,b.max.x-b.min.x,b.max.y-b.min.y)}function b(a,b,d){return b>=a.x&&b<=a.x+a.width&&d>=a.y&&d<=a.y+a.height}function q(a,d){a=w(a);d=w(d);return b(d,a.x,a.y)||b(d,a.x2,a.y)||b(d,a.x,a.y2)||b(d,a.x2,a.y2)||b(a,d.x,d.y)||b(a,d.x2,d.y)||b(a,d.x,d.y2)||b(a,d.x2,d.y2)||(a.x<d.x2&&a.x>d.x||d.x<a.x2&&d.x>a.x)&&(a.y<d.y2&&a.y>d.y||d.y<a.y2&&d.y>a.y)}function e(a,b,d,e,h,f,n,k,l){null==l&&(l=1);l=(1<l?1:0>l?0:l)/2;for(var p=[-0.1252,
0.1252,-0.3678,0.3678,-0.5873,0.5873,-0.7699,0.7699,-0.9041,0.9041,-0.9816,0.9816],q=[0.2491,0.2491,0.2335,0.2335,0.2032,0.2032,0.1601,0.1601,0.1069,0.1069,0.0472,0.0472],s=0,c=0;12>c;c++)var t=l*p[c]+l,r=t*(t*(-3*a+9*d-9*h+3*n)+6*a-12*d+6*h)-3*a+3*d,t=t*(t*(-3*b+9*e-9*f+3*k)+6*b-12*e+6*f)-3*b+3*e,s=s+q[c]*F.sqrt(r*r+t*t);return l*s}function l(a,b,d){a=I(a);b=I(b);for(var h,f,l,n,k,s,r,O,x,c,t=d?0:[],w=0,v=a.length;w<v;w++)if(x=a[w],"M"==x[0])h=k=x[1],f=s=x[2];else{"C"==x[0]?(x=[h,f].concat(x.slice(1)),
h=x[6],f=x[7]):(x=[h,f,h,f,k,s,k,s],h=k,f=s);for(var G=0,y=b.length;G<y;G++)if(c=b[G],"M"==c[0])l=r=c[1],n=O=c[2];else{"C"==c[0]?(c=[l,n].concat(c.slice(1)),l=c[6],n=c[7]):(c=[l,n,l,n,r,O,r,O],l=r,n=O);var z;var K=x,B=c;z=d;var H=p(K),J=p(B);if(q(H,J)){for(var H=e.apply(0,K),J=e.apply(0,B),H=~~(H/8),J=~~(J/8),U=[],A=[],F={},M=z?0:[],P=0;P<H+1;P++){var C=u.apply(0,K.concat(P/H));U.push({x:C.x,y:C.y,t:P/H})}for(P=0;P<J+1;P++)C=u.apply(0,B.concat(P/J)),A.push({x:C.x,y:C.y,t:P/J});for(P=0;P<H;P++)for(K=
0;K<J;K++){var Q=U[P],L=U[P+1],B=A[K],C=A[K+1],N=0.001>Z(L.x-Q.x)?"y":"x",S=0.001>Z(C.x-B.x)?"y":"x",R;R=Q.x;var Y=Q.y,V=L.x,ea=L.y,fa=B.x,ga=B.y,ha=C.x,ia=C.y;if(W(R,V)<X(fa,ha)||X(R,V)>W(fa,ha)||W(Y,ea)<X(ga,ia)||X(Y,ea)>W(ga,ia))R=void 0;else{var $=(R*ea-Y*V)*(fa-ha)-(R-V)*(fa*ia-ga*ha),aa=(R*ea-Y*V)*(ga-ia)-(Y-ea)*(fa*ia-ga*ha),ja=(R-V)*(ga-ia)-(Y-ea)*(fa-ha);if(ja){var $=$/ja,aa=aa/ja,ja=+$.toFixed(2),ba=+aa.toFixed(2);R=ja<+X(R,V).toFixed(2)||ja>+W(R,V).toFixed(2)||ja<+X(fa,ha).toFixed(2)||
ja>+W(fa,ha).toFixed(2)||ba<+X(Y,ea).toFixed(2)||ba>+W(Y,ea).toFixed(2)||ba<+X(ga,ia).toFixed(2)||ba>+W(ga,ia).toFixed(2)?void 0:{x:$,y:aa}}else R=void 0}R&&F[R.x.toFixed(4)]!=R.y.toFixed(4)&&(F[R.x.toFixed(4)]=R.y.toFixed(4),Q=Q.t+Z((R[N]-Q[N])/(L[N]-Q[N]))*(L.t-Q.t),B=B.t+Z((R[S]-B[S])/(C[S]-B[S]))*(C.t-B.t),0<=Q&&1>=Q&&0<=B&&1>=B&&(z?M++:M.push({x:R.x,y:R.y,t1:Q,t2:B})))}z=M}else z=z?0:[];if(d)t+=z;else{H=0;for(J=z.length;H<J;H++)z[H].segment1=w,z[H].segment2=G,z[H].bez1=x,z[H].bez2=c;t=t.concat(z)}}}return t}
function r(a){var b=A(a);if(b.bbox)return C(b.bbox);if(!a)return w();a=I(a);for(var d=0,e=0,h=[],f=[],l,n=0,k=a.length;n<k;n++)l=a[n],"M"==l[0]?(d=l[1],e=l[2],h.push(d),f.push(e)):(d=U(d,e,l[1],l[2],l[3],l[4],l[5],l[6]),h=h.concat(d.min.x,d.max.x),f=f.concat(d.min.y,d.max.y),d=l[5],e=l[6]);a=X.apply(0,h);l=X.apply(0,f);h=W.apply(0,h);f=W.apply(0,f);f=w(a,l,h-a,f-l);b.bbox=C(f);return f}function s(a,b,d,e,h){if(h)return[["M",+a+ +h,b],["l",d-2*h,0],["a",h,h,0,0,1,h,h],["l",0,e-2*h],["a",h,h,0,0,1,
-h,h],["l",2*h-d,0],["a",h,h,0,0,1,-h,-h],["l",0,2*h-e],["a",h,h,0,0,1,h,-h],["z"] ];a=[["M",a,b],["l",d,0],["l",0,e],["l",-d,0],["z"] ];a.toString=z;return a}function x(a,b,d,e,h){null==h&&null==e&&(e=d);a=+a;b=+b;d=+d;e=+e;if(null!=h){var f=Math.PI/180,l=a+d*Math.cos(-e*f);a+=d*Math.cos(-h*f);var n=b+d*Math.sin(-e*f);b+=d*Math.sin(-h*f);d=[["M",l,n],["A",d,d,0,+(180<h-e),0,a,b] ]}else d=[["M",a,b],["m",0,-e],["a",d,e,0,1,1,0,2*e],["a",d,e,0,1,1,0,-2*e],["z"] ];d.toString=z;return d}function G(b){var e=
A(b);if(e.abs)return d(e.abs);Q(b,"array")&&Q(b&&b[0],"array")||(b=a.parsePathString(b));if(!b||!b.length)return[["M",0,0] ];var h=[],f=0,l=0,n=0,k=0,p=0;"M"==b[0][0]&&(f=+b[0][1],l=+b[0][2],n=f,k=l,p++,h[0]=["M",f,l]);for(var q=3==b.length&&"M"==b[0][0]&&"R"==b[1][0].toUpperCase()&&"Z"==b[2][0].toUpperCase(),s,r,w=p,c=b.length;w<c;w++){h.push(s=[]);r=b[w];p=r[0];if(p!=p.toUpperCase())switch(s[0]=p.toUpperCase(),s[0]){case "A":s[1]=r[1];s[2]=r[2];s[3]=r[3];s[4]=r[4];s[5]=r[5];s[6]=+r[6]+f;s[7]=+r[7]+
l;break;case "V":s[1]=+r[1]+l;break;case "H":s[1]=+r[1]+f;break;case "R":for(var t=[f,l].concat(r.slice(1)),u=2,v=t.length;u<v;u++)t[u]=+t[u]+f,t[++u]=+t[u]+l;h.pop();h=h.concat(P(t,q));break;case "O":h.pop();t=x(f,l,r[1],r[2]);t.push(t[0]);h=h.concat(t);break;case "U":h.pop();h=h.concat(x(f,l,r[1],r[2],r[3]));s=["U"].concat(h[h.length-1].slice(-2));break;case "M":n=+r[1]+f,k=+r[2]+l;default:for(u=1,v=r.length;u<v;u++)s[u]=+r[u]+(u%2?f:l)}else if("R"==p)t=[f,l].concat(r.slice(1)),h.pop(),h=h.concat(P(t,
q)),s=["R"].concat(r.slice(-2));else if("O"==p)h.pop(),t=x(f,l,r[1],r[2]),t.push(t[0]),h=h.concat(t);else if("U"==p)h.pop(),h=h.concat(x(f,l,r[1],r[2],r[3])),s=["U"].concat(h[h.length-1].slice(-2));else for(t=0,u=r.length;t<u;t++)s[t]=r[t];p=p.toUpperCase();if("O"!=p)switch(s[0]){case "Z":f=+n;l=+k;break;case "H":f=s[1];break;case "V":l=s[1];break;case "M":n=s[s.length-2],k=s[s.length-1];default:f=s[s.length-2],l=s[s.length-1]}}h.toString=z;e.abs=d(h);return h}function h(a,b,d,e){return[a,b,d,e,d,
e]}function J(a,b,d,e,h,f){var l=1/3,n=2/3;return[l*a+n*d,l*b+n*e,l*h+n*d,l*f+n*e,h,f]}function K(b,d,e,h,f,l,n,k,p,s){var r=120*S/180,q=S/180*(+f||0),c=[],t,x=a._.cacher(function(a,b,c){var d=a*F.cos(c)-b*F.sin(c);a=a*F.sin(c)+b*F.cos(c);return{x:d,y:a}});if(s)v=s[0],t=s[1],l=s[2],u=s[3];else{t=x(b,d,-q);b=t.x;d=t.y;t=x(k,p,-q);k=t.x;p=t.y;F.cos(S/180*f);F.sin(S/180*f);t=(b-k)/2;v=(d-p)/2;u=t*t/(e*e)+v*v/(h*h);1<u&&(u=F.sqrt(u),e*=u,h*=u);var u=e*e,w=h*h,u=(l==n?-1:1)*F.sqrt(Z((u*w-u*v*v-w*t*t)/
(u*v*v+w*t*t)));l=u*e*v/h+(b+k)/2;var u=u*-h*t/e+(d+p)/2,v=F.asin(((d-u)/h).toFixed(9));t=F.asin(((p-u)/h).toFixed(9));v=b<l?S-v:v;t=k<l?S-t:t;0>v&&(v=2*S+v);0>t&&(t=2*S+t);n&&v>t&&(v-=2*S);!n&&t>v&&(t-=2*S)}if(Z(t-v)>r){var c=t,w=k,G=p;t=v+r*(n&&t>v?1:-1);k=l+e*F.cos(t);p=u+h*F.sin(t);c=K(k,p,e,h,f,0,n,w,G,[t,c,l,u])}l=t-v;f=F.cos(v);r=F.sin(v);n=F.cos(t);t=F.sin(t);l=F.tan(l/4);e=4/3*e*l;l*=4/3*h;h=[b,d];b=[b+e*r,d-l*f];d=[k+e*t,p-l*n];k=[k,p];b[0]=2*h[0]-b[0];b[1]=2*h[1]-b[1];if(s)return[b,d,k].concat(c);
c=[b,d,k].concat(c).join().split(",");s=[];k=0;for(p=c.length;k<p;k++)s[k]=k%2?x(c[k-1],c[k],q).y:x(c[k],c[k+1],q).x;return s}function U(a,b,d,e,h,f,l,k){for(var n=[],p=[[],[] ],s,r,c,t,q=0;2>q;++q)0==q?(r=6*a-12*d+6*h,s=-3*a+9*d-9*h+3*l,c=3*d-3*a):(r=6*b-12*e+6*f,s=-3*b+9*e-9*f+3*k,c=3*e-3*b),1E-12>Z(s)?1E-12>Z(r)||(s=-c/r,0<s&&1>s&&n.push(s)):(t=r*r-4*c*s,c=F.sqrt(t),0>t||(t=(-r+c)/(2*s),0<t&&1>t&&n.push(t),s=(-r-c)/(2*s),0<s&&1>s&&n.push(s)));for(r=q=n.length;q--;)s=n[q],c=1-s,p[0][q]=c*c*c*a+3*
c*c*s*d+3*c*s*s*h+s*s*s*l,p[1][q]=c*c*c*b+3*c*c*s*e+3*c*s*s*f+s*s*s*k;p[0][r]=a;p[1][r]=b;p[0][r+1]=l;p[1][r+1]=k;p[0].length=p[1].length=r+2;return{min:{x:X.apply(0,p[0]),y:X.apply(0,p[1])},max:{x:W.apply(0,p[0]),y:W.apply(0,p[1])}}}function I(a,b){var e=!b&&A(a);if(!b&&e.curve)return d(e.curve);var f=G(a),l=b&&G(b),n={x:0,y:0,bx:0,by:0,X:0,Y:0,qx:null,qy:null},k={x:0,y:0,bx:0,by:0,X:0,Y:0,qx:null,qy:null},p=function(a,b,c){if(!a)return["C",b.x,b.y,b.x,b.y,b.x,b.y];a[0]in{T:1,Q:1}||(b.qx=b.qy=null);
switch(a[0]){case "M":b.X=a[1];b.Y=a[2];break;case "A":a=["C"].concat(K.apply(0,[b.x,b.y].concat(a.slice(1))));break;case "S":"C"==c||"S"==c?(c=2*b.x-b.bx,b=2*b.y-b.by):(c=b.x,b=b.y);a=["C",c,b].concat(a.slice(1));break;case "T":"Q"==c||"T"==c?(b.qx=2*b.x-b.qx,b.qy=2*b.y-b.qy):(b.qx=b.x,b.qy=b.y);a=["C"].concat(J(b.x,b.y,b.qx,b.qy,a[1],a[2]));break;case "Q":b.qx=a[1];b.qy=a[2];a=["C"].concat(J(b.x,b.y,a[1],a[2],a[3],a[4]));break;case "L":a=["C"].concat(h(b.x,b.y,a[1],a[2]));break;case "H":a=["C"].concat(h(b.x,
b.y,a[1],b.y));break;case "V":a=["C"].concat(h(b.x,b.y,b.x,a[1]));break;case "Z":a=["C"].concat(h(b.x,b.y,b.X,b.Y))}return a},s=function(a,b){if(7<a[b].length){a[b].shift();for(var c=a[b];c.length;)q[b]="A",l&&(u[b]="A"),a.splice(b++,0,["C"].concat(c.splice(0,6)));a.splice(b,1);v=W(f.length,l&&l.length||0)}},r=function(a,b,c,d,e){a&&b&&"M"==a[e][0]&&"M"!=b[e][0]&&(b.splice(e,0,["M",d.x,d.y]),c.bx=0,c.by=0,c.x=a[e][1],c.y=a[e][2],v=W(f.length,l&&l.length||0))},q=[],u=[],c="",t="",x=0,v=W(f.length,
l&&l.length||0);for(;x<v;x++){f[x]&&(c=f[x][0]);"C"!=c&&(q[x]=c,x&&(t=q[x-1]));f[x]=p(f[x],n,t);"A"!=q[x]&&"C"==c&&(q[x]="C");s(f,x);l&&(l[x]&&(c=l[x][0]),"C"!=c&&(u[x]=c,x&&(t=u[x-1])),l[x]=p(l[x],k,t),"A"!=u[x]&&"C"==c&&(u[x]="C"),s(l,x));r(f,l,n,k,x);r(l,f,k,n,x);var w=f[x],z=l&&l[x],y=w.length,U=l&&z.length;n.x=w[y-2];n.y=w[y-1];n.bx=$(w[y-4])||n.x;n.by=$(w[y-3])||n.y;k.bx=l&&($(z[U-4])||k.x);k.by=l&&($(z[U-3])||k.y);k.x=l&&z[U-2];k.y=l&&z[U-1]}l||(e.curve=d(f));return l?[f,l]:f}function P(a,
b){for(var d=[],e=0,h=a.length;h-2*!b>e;e+=2){var f=[{x:+a[e-2],y:+a[e-1]},{x:+a[e],y:+a[e+1]},{x:+a[e+2],y:+a[e+3]},{x:+a[e+4],y:+a[e+5]}];b?e?h-4==e?f[3]={x:+a[0],y:+a[1]}:h-2==e&&(f[2]={x:+a[0],y:+a[1]},f[3]={x:+a[2],y:+a[3]}):f[0]={x:+a[h-2],y:+a[h-1]}:h-4==e?f[3]=f[2]:e||(f[0]={x:+a[e],y:+a[e+1]});d.push(["C",(-f[0].x+6*f[1].x+f[2].x)/6,(-f[0].y+6*f[1].y+f[2].y)/6,(f[1].x+6*f[2].x-f[3].x)/6,(f[1].y+6*f[2].y-f[3].y)/6,f[2].x,f[2].y])}return d}y=k.prototype;var Q=a.is,C=a._.clone,L="hasOwnProperty",
N=/,?([a-z]),?/gi,$=parseFloat,F=Math,S=F.PI,X=F.min,W=F.max,ma=F.pow,Z=F.abs;M=n(1);var na=n(),ba=n(0,1),V=a._unit2px;a.path=A;a.path.getTotalLength=M;a.path.getPointAtLength=na;a.path.getSubpath=function(a,b,d){if(1E-6>this.getTotalLength(a)-d)return ba(a,b).end;a=ba(a,d,1);return b?ba(a,b).end:a};y.getTotalLength=function(){if(this.node.getTotalLength)return this.node.getTotalLength()};y.getPointAtLength=function(a){return na(this.attr("d"),a)};y.getSubpath=function(b,d){return a.path.getSubpath(this.attr("d"),
b,d)};a._.box=w;a.path.findDotsAtSegment=u;a.path.bezierBBox=p;a.path.isPointInsideBBox=b;a.path.isBBoxIntersect=q;a.path.intersection=function(a,b){return l(a,b)};a.path.intersectionNumber=function(a,b){return l(a,b,1)};a.path.isPointInside=function(a,d,e){var h=r(a);return b(h,d,e)&&1==l(a,[["M",d,e],["H",h.x2+10] ],1)%2};a.path.getBBox=r;a.path.get={path:function(a){return a.attr("path")},circle:function(a){a=V(a);return x(a.cx,a.cy,a.r)},ellipse:function(a){a=V(a);return x(a.cx||0,a.cy||0,a.rx,
a.ry)},rect:function(a){a=V(a);return s(a.x||0,a.y||0,a.width,a.height,a.rx,a.ry)},image:function(a){a=V(a);return s(a.x||0,a.y||0,a.width,a.height)},line:function(a){return"M"+[a.attr("x1")||0,a.attr("y1")||0,a.attr("x2"),a.attr("y2")]},polyline:function(a){return"M"+a.attr("points")},polygon:function(a){return"M"+a.attr("points")+"z"},deflt:function(a){a=a.node.getBBox();return s(a.x,a.y,a.width,a.height)}};a.path.toRelative=function(b){var e=A(b),h=String.prototype.toLowerCase;if(e.rel)return d(e.rel);
a.is(b,"array")&&a.is(b&&b[0],"array")||(b=a.parsePathString(b));var f=[],l=0,n=0,k=0,p=0,s=0;"M"==b[0][0]&&(l=b[0][1],n=b[0][2],k=l,p=n,s++,f.push(["M",l,n]));for(var r=b.length;s<r;s++){var q=f[s]=[],x=b[s];if(x[0]!=h.call(x[0]))switch(q[0]=h.call(x[0]),q[0]){case "a":q[1]=x[1];q[2]=x[2];q[3]=x[3];q[4]=x[4];q[5]=x[5];q[6]=+(x[6]-l).toFixed(3);q[7]=+(x[7]-n).toFixed(3);break;case "v":q[1]=+(x[1]-n).toFixed(3);break;case "m":k=x[1],p=x[2];default:for(var c=1,t=x.length;c<t;c++)q[c]=+(x[c]-(c%2?l:
n)).toFixed(3)}else for(f[s]=[],"m"==x[0]&&(k=x[1]+l,p=x[2]+n),q=0,c=x.length;q<c;q++)f[s][q]=x[q];x=f[s].length;switch(f[s][0]){case "z":l=k;n=p;break;case "h":l+=+f[s][x-1];break;case "v":n+=+f[s][x-1];break;default:l+=+f[s][x-2],n+=+f[s][x-1]}}f.toString=z;e.rel=d(f);return f};a.path.toAbsolute=G;a.path.toCubic=I;a.path.map=function(a,b){if(!b)return a;var d,e,h,f,l,n,k;a=I(a);h=0;for(l=a.length;h<l;h++)for(k=a[h],f=1,n=k.length;f<n;f+=2)d=b.x(k[f],k[f+1]),e=b.y(k[f],k[f+1]),k[f]=d,k[f+1]=e;return a};
a.path.toString=z;a.path.clone=d});C.plugin(function(a,v,y,C){var A=Math.max,w=Math.min,z=function(a){this.items=[];this.bindings={};this.length=0;this.type="set";if(a)for(var f=0,n=a.length;f<n;f++)a[f]&&(this[this.items.length]=this.items[this.items.length]=a[f],this.length++)};v=z.prototype;v.push=function(){for(var a,f,n=0,k=arguments.length;n<k;n++)if(a=arguments[n])f=this.items.length,this[f]=this.items[f]=a,this.length++;return this};v.pop=function(){this.length&&delete this[this.length--];
return this.items.pop()};v.forEach=function(a,f){for(var n=0,k=this.items.length;n<k&&!1!==a.call(f,this.items[n],n);n++);return this};v.animate=function(d,f,n,u){"function"!=typeof n||n.length||(u=n,n=L.linear);d instanceof a._.Animation&&(u=d.callback,n=d.easing,f=n.dur,d=d.attr);var p=arguments;if(a.is(d,"array")&&a.is(p[p.length-1],"array"))var b=!0;var q,e=function(){q?this.b=q:q=this.b},l=0,r=u&&function(){l++==this.length&&u.call(this)};return this.forEach(function(a,l){k.once("snap.animcreated."+
a.id,e);b?p[l]&&a.animate.apply(a,p[l]):a.animate(d,f,n,r)})};v.remove=function(){for(;this.length;)this.pop().remove();return this};v.bind=function(a,f,k){var u={};if("function"==typeof f)this.bindings[a]=f;else{var p=k||a;this.bindings[a]=function(a){u[p]=a;f.attr(u)}}return this};v.attr=function(a){var f={},k;for(k in a)if(this.bindings[k])this.bindings[k](a[k]);else f[k]=a[k];a=0;for(k=this.items.length;a<k;a++)this.items[a].attr(f);return this};v.clear=function(){for(;this.length;)this.pop()};
v.splice=function(a,f,k){a=0>a?A(this.length+a,0):a;f=A(0,w(this.length-a,f));var u=[],p=[],b=[],q;for(q=2;q<arguments.length;q++)b.push(arguments[q]);for(q=0;q<f;q++)p.push(this[a+q]);for(;q<this.length-a;q++)u.push(this[a+q]);var e=b.length;for(q=0;q<e+u.length;q++)this.items[a+q]=this[a+q]=q<e?b[q]:u[q-e];for(q=this.items.length=this.length-=f-e;this[q];)delete this[q++];return new z(p)};v.exclude=function(a){for(var f=0,k=this.length;f<k;f++)if(this[f]==a)return this.splice(f,1),!0;return!1};
v.insertAfter=function(a){for(var f=this.items.length;f--;)this.items[f].insertAfter(a);return this};v.getBBox=function(){for(var a=[],f=[],k=[],u=[],p=this.items.length;p--;)if(!this.items[p].removed){var b=this.items[p].getBBox();a.push(b.x);f.push(b.y);k.push(b.x+b.width);u.push(b.y+b.height)}a=w.apply(0,a);f=w.apply(0,f);k=A.apply(0,k);u=A.apply(0,u);return{x:a,y:f,x2:k,y2:u,width:k-a,height:u-f,cx:a+(k-a)/2,cy:f+(u-f)/2}};v.clone=function(a){a=new z;for(var f=0,k=this.items.length;f<k;f++)a.push(this.items[f].clone());
return a};v.toString=function(){return"Snap\u2018s set"};v.type="set";a.set=function(){var a=new z;arguments.length&&a.push.apply(a,Array.prototype.slice.call(arguments,0));return a}});C.plugin(function(a,v,y,C){function A(a){var b=a[0];switch(b.toLowerCase()){case "t":return[b,0,0];case "m":return[b,1,0,0,1,0,0];case "r":return 4==a.length?[b,0,a[2],a[3] ]:[b,0];case "s":return 5==a.length?[b,1,1,a[3],a[4] ]:3==a.length?[b,1,1]:[b,1]}}function w(b,d,f){d=q(d).replace(/\.{3}|\u2026/g,b);b=a.parseTransformString(b)||
[];d=a.parseTransformString(d)||[];for(var k=Math.max(b.length,d.length),p=[],v=[],h=0,w,z,y,I;h<k;h++){y=b[h]||A(d[h]);I=d[h]||A(y);if(y[0]!=I[0]||"r"==y[0].toLowerCase()&&(y[2]!=I[2]||y[3]!=I[3])||"s"==y[0].toLowerCase()&&(y[3]!=I[3]||y[4]!=I[4])){b=a._.transform2matrix(b,f());d=a._.transform2matrix(d,f());p=[["m",b.a,b.b,b.c,b.d,b.e,b.f] ];v=[["m",d.a,d.b,d.c,d.d,d.e,d.f] ];break}p[h]=[];v[h]=[];w=0;for(z=Math.max(y.length,I.length);w<z;w++)w in y&&(p[h][w]=y[w]),w in I&&(v[h][w]=I[w])}return{from:u(p),
to:u(v),f:n(p)}}function z(a){return a}function d(a){return function(b){return+b.toFixed(3)+a}}function f(b){return a.rgb(b[0],b[1],b[2])}function n(a){var b=0,d,f,k,n,h,p,q=[];d=0;for(f=a.length;d<f;d++){h="[";p=['"'+a[d][0]+'"'];k=1;for(n=a[d].length;k<n;k++)p[k]="val["+b++ +"]";h+=p+"]";q[d]=h}return Function("val","return Snap.path.toString.call(["+q+"])")}function u(a){for(var b=[],d=0,f=a.length;d<f;d++)for(var k=1,n=a[d].length;k<n;k++)b.push(a[d][k]);return b}var p={},b=/[a-z]+$/i,q=String;
p.stroke=p.fill="colour";v.prototype.equal=function(a,b){return k("snap.util.equal",this,a,b).firstDefined()};k.on("snap.util.equal",function(e,k){var r,s;r=q(this.attr(e)||"");var x=this;if(r==+r&&k==+k)return{from:+r,to:+k,f:z};if("colour"==p[e])return r=a.color(r),s=a.color(k),{from:[r.r,r.g,r.b,r.opacity],to:[s.r,s.g,s.b,s.opacity],f:f};if("transform"==e||"gradientTransform"==e||"patternTransform"==e)return k instanceof a.Matrix&&(k=k.toTransformString()),a._.rgTransform.test(k)||(k=a._.svgTransform2string(k)),
w(r,k,function(){return x.getBBox(1)});if("d"==e||"path"==e)return r=a.path.toCubic(r,k),{from:u(r[0]),to:u(r[1]),f:n(r[0])};if("points"==e)return r=q(r).split(a._.separator),s=q(k).split(a._.separator),{from:r,to:s,f:function(a){return a}};aUnit=r.match(b);s=q(k).match(b);return aUnit&&aUnit==s?{from:parseFloat(r),to:parseFloat(k),f:d(aUnit)}:{from:this.asPX(e),to:this.asPX(e,k),f:z}})});C.plugin(function(a,v,y,C){var A=v.prototype,w="createTouch"in C.doc;v="click dblclick mousedown mousemove mouseout mouseover mouseup touchstart touchmove touchend touchcancel".split(" ");
var z={mousedown:"touchstart",mousemove:"touchmove",mouseup:"touchend"},d=function(a,b){var d="y"==a?"scrollTop":"scrollLeft",e=b&&b.node?b.node.ownerDocument:C.doc;return e[d in e.documentElement?"documentElement":"body"][d]},f=function(){this.returnValue=!1},n=function(){return this.originalEvent.preventDefault()},u=function(){this.cancelBubble=!0},p=function(){return this.originalEvent.stopPropagation()},b=function(){if(C.doc.addEventListener)return function(a,b,e,f){var k=w&&z[b]?z[b]:b,l=function(k){var l=
d("y",f),q=d("x",f);if(w&&z.hasOwnProperty(b))for(var r=0,u=k.targetTouches&&k.targetTouches.length;r<u;r++)if(k.targetTouches[r].target==a||a.contains(k.targetTouches[r].target)){u=k;k=k.targetTouches[r];k.originalEvent=u;k.preventDefault=n;k.stopPropagation=p;break}return e.call(f,k,k.clientX+q,k.clientY+l)};b!==k&&a.addEventListener(b,l,!1);a.addEventListener(k,l,!1);return function(){b!==k&&a.removeEventListener(b,l,!1);a.removeEventListener(k,l,!1);return!0}};if(C.doc.attachEvent)return function(a,
b,e,h){var k=function(a){a=a||h.node.ownerDocument.window.event;var b=d("y",h),k=d("x",h),k=a.clientX+k,b=a.clientY+b;a.preventDefault=a.preventDefault||f;a.stopPropagation=a.stopPropagation||u;return e.call(h,a,k,b)};a.attachEvent("on"+b,k);return function(){a.detachEvent("on"+b,k);return!0}}}(),q=[],e=function(a){for(var b=a.clientX,e=a.clientY,f=d("y"),l=d("x"),n,p=q.length;p--;){n=q[p];if(w)for(var r=a.touches&&a.touches.length,u;r--;){if(u=a.touches[r],u.identifier==n.el._drag.id||n.el.node.contains(u.target)){b=
u.clientX;e=u.clientY;(a.originalEvent?a.originalEvent:a).preventDefault();break}}else a.preventDefault();b+=l;e+=f;k("snap.drag.move."+n.el.id,n.move_scope||n.el,b-n.el._drag.x,e-n.el._drag.y,b,e,a)}},l=function(b){a.unmousemove(e).unmouseup(l);for(var d=q.length,f;d--;)f=q[d],f.el._drag={},k("snap.drag.end."+f.el.id,f.end_scope||f.start_scope||f.move_scope||f.el,b);q=[]};for(y=v.length;y--;)(function(d){a[d]=A[d]=function(e,f){a.is(e,"function")&&(this.events=this.events||[],this.events.push({name:d,
f:e,unbind:b(this.node||document,d,e,f||this)}));return this};a["un"+d]=A["un"+d]=function(a){for(var b=this.events||[],e=b.length;e--;)if(b[e].name==d&&(b[e].f==a||!a)){b[e].unbind();b.splice(e,1);!b.length&&delete this.events;break}return this}})(v[y]);A.hover=function(a,b,d,e){return this.mouseover(a,d).mouseout(b,e||d)};A.unhover=function(a,b){return this.unmouseover(a).unmouseout(b)};var r=[];A.drag=function(b,d,f,h,n,p){function u(r,v,w){(r.originalEvent||r).preventDefault();this._drag.x=v;
this._drag.y=w;this._drag.id=r.identifier;!q.length&&a.mousemove(e).mouseup(l);q.push({el:this,move_scope:h,start_scope:n,end_scope:p});d&&k.on("snap.drag.start."+this.id,d);b&&k.on("snap.drag.move."+this.id,b);f&&k.on("snap.drag.end."+this.id,f);k("snap.drag.start."+this.id,n||h||this,v,w,r)}if(!arguments.length){var v;return this.drag(function(a,b){this.attr({transform:v+(v?"T":"t")+[a,b]})},function(){v=this.transform().local})}this._drag={};r.push({el:this,start:u});this.mousedown(u);return this};
A.undrag=function(){for(var b=r.length;b--;)r[b].el==this&&(this.unmousedown(r[b].start),r.splice(b,1),k.unbind("snap.drag.*."+this.id));!r.length&&a.unmousemove(e).unmouseup(l);return this}});C.plugin(function(a,v,y,C){y=y.prototype;var A=/^\s*url\((.+)\)/,w=String,z=a._.$;a.filter={};y.filter=function(d){var f=this;"svg"!=f.type&&(f=f.paper);d=a.parse(w(d));var k=a._.id(),u=z("filter");z(u,{id:k,filterUnits:"userSpaceOnUse"});u.appendChild(d.node);f.defs.appendChild(u);return new v(u)};k.on("snap.util.getattr.filter",
function(){k.stop();var d=z(this.node,"filter");if(d)return(d=w(d).match(A))&&a.select(d[1])});k.on("snap.util.attr.filter",function(d){if(d instanceof v&&"filter"==d.type){k.stop();var f=d.node.id;f||(z(d.node,{id:d.id}),f=d.id);z(this.node,{filter:a.url(f)})}d&&"none"!=d||(k.stop(),this.node.removeAttribute("filter"))});a.filter.blur=function(d,f){null==d&&(d=2);return a.format('<feGaussianBlur stdDeviation="{def}"/>',{def:null==f?d:[d,f]})};a.filter.blur.toString=function(){return this()};a.filter.shadow=
function(d,f,k,u,p){"string"==typeof k&&(p=u=k,k=4);"string"!=typeof u&&(p=u,u="#000");null==k&&(k=4);null==p&&(p=1);null==d&&(d=0,f=2);null==f&&(f=d);u=a.color(u||"#000");return a.format('<feGaussianBlur in="SourceAlpha" stdDeviation="{blur}"/><feOffset dx="{dx}" dy="{dy}" result="offsetblur"/><feFlood flood-color="{color}"/><feComposite in2="offsetblur" operator="in"/><feComponentTransfer><feFuncA type="linear" slope="{opacity}"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>',
{color:u,dx:d,dy:f,blur:k,opacity:p})};a.filter.shadow.toString=function(){return this()};a.filter.grayscale=function(d){null==d&&(d=1);return a.format('<feColorMatrix type="matrix" values="{a} {b} {c} 0 0 {d} {e} {f} 0 0 {g} {b} {h} 0 0 0 0 0 1 0"/>',{a:0.2126+0.7874*(1-d),b:0.7152-0.7152*(1-d),c:0.0722-0.0722*(1-d),d:0.2126-0.2126*(1-d),e:0.7152+0.2848*(1-d),f:0.0722-0.0722*(1-d),g:0.2126-0.2126*(1-d),h:0.0722+0.9278*(1-d)})};a.filter.grayscale.toString=function(){return this()};a.filter.sepia=
function(d){null==d&&(d=1);return a.format('<feColorMatrix type="matrix" values="{a} {b} {c} 0 0 {d} {e} {f} 0 0 {g} {h} {i} 0 0 0 0 0 1 0"/>',{a:0.393+0.607*(1-d),b:0.769-0.769*(1-d),c:0.189-0.189*(1-d),d:0.349-0.349*(1-d),e:0.686+0.314*(1-d),f:0.168-0.168*(1-d),g:0.272-0.272*(1-d),h:0.534-0.534*(1-d),i:0.131+0.869*(1-d)})};a.filter.sepia.toString=function(){return this()};a.filter.saturate=function(d){null==d&&(d=1);return a.format('<feColorMatrix type="saturate" values="{amount}"/>',{amount:1-
d})};a.filter.saturate.toString=function(){return this()};a.filter.hueRotate=function(d){return a.format('<feColorMatrix type="hueRotate" values="{angle}"/>',{angle:d||0})};a.filter.hueRotate.toString=function(){return this()};a.filter.invert=function(d){null==d&&(d=1);return a.format('<feComponentTransfer><feFuncR type="table" tableValues="{amount} {amount2}"/><feFuncG type="table" tableValues="{amount} {amount2}"/><feFuncB type="table" tableValues="{amount} {amount2}"/></feComponentTransfer>',{amount:d,
amount2:1-d})};a.filter.invert.toString=function(){return this()};a.filter.brightness=function(d){null==d&&(d=1);return a.format('<feComponentTransfer><feFuncR type="linear" slope="{amount}"/><feFuncG type="linear" slope="{amount}"/><feFuncB type="linear" slope="{amount}"/></feComponentTransfer>',{amount:d})};a.filter.brightness.toString=function(){return this()};a.filter.contrast=function(d){null==d&&(d=1);return a.format('<feComponentTransfer><feFuncR type="linear" slope="{amount}" intercept="{amount2}"/><feFuncG type="linear" slope="{amount}" intercept="{amount2}"/><feFuncB type="linear" slope="{amount}" intercept="{amount2}"/></feComponentTransfer>',
{amount:d,amount2:0.5-d/2})};a.filter.contrast.toString=function(){return this()}});return C});

]]> </script>
<script> <![CDATA[

(function (glob, factory) {
    // AMD support
    if (typeof define === "function" && define.amd) {
        // Define as an anonymous module
        define("Gadfly", ["Snap.svg"], function (Snap) {
            return factory(Snap);
        });
    } else {
        // Browser globals (glob is window)
        // Snap adds itself to window
        glob.Gadfly = factory(glob.Snap);
    }
}(this, function (Snap) {

var Gadfly = {};

// Get an x/y coordinate value in pixels
var xPX = function(fig, x) {
    var client_box = fig.node.getBoundingClientRect();
    return x * fig.node.viewBox.baseVal.width / client_box.width;
};

var yPX = function(fig, y) {
    var client_box = fig.node.getBoundingClientRect();
    return y * fig.node.viewBox.baseVal.height / client_box.height;
};


Snap.plugin(function (Snap, Element, Paper, global) {
    // Traverse upwards from a snap element to find and return the first
    // note with the "plotroot" class.
    Element.prototype.plotroot = function () {
        var element = this;
        while (!element.hasClass("plotroot") && element.parent() != null) {
            element = element.parent();
        }
        return element;
    };

    Element.prototype.svgroot = function () {
        var element = this;
        while (element.node.nodeName != "svg" && element.parent() != null) {
            element = element.parent();
        }
        return element;
    };

    Element.prototype.plotbounds = function () {
        var root = this.plotroot()
        var bbox = root.select(".guide.background").node.getBBox();
        return {
            x0: bbox.x,
            x1: bbox.x + bbox.width,
            y0: bbox.y,
            y1: bbox.y + bbox.height
        };
    };

    Element.prototype.plotcenter = function () {
        var root = this.plotroot()
        var bbox = root.select(".guide.background").node.getBBox();
        return {
            x: bbox.x + bbox.width / 2,
            y: bbox.y + bbox.height / 2
        };
    };

    // Emulate IE style mouseenter/mouseleave events, since Microsoft always
    // does everything right.
    // See: http://www.dynamic-tools.net/toolbox/isMouseLeaveOrEnter/
    var events = ["mouseenter", "mouseleave"];

    for (i in events) {
        (function (event_name) {
            var event_name = events[i];
            Element.prototype[event_name] = function (fn, scope) {
                if (Snap.is(fn, "function")) {
                    var fn2 = function (event) {
                        if (event.type != "mouseover" && event.type != "mouseout") {
                            return;
                        }

                        var reltg = event.relatedTarget ? event.relatedTarget :
                            event.type == "mouseout" ? event.toElement : event.fromElement;
                        while (reltg && reltg != this.node) reltg = reltg.parentNode;

                        if (reltg != this.node) {
                            return fn.apply(this, event);
                        }
                    };

                    if (event_name == "mouseenter") {
                        this.mouseover(fn2, scope);
                    } else {
                        this.mouseout(fn2, scope);
                    }
                }
                return this;
            };
        })(events[i]);
    }


    Element.prototype.mousewheel = function (fn, scope) {
        if (Snap.is(fn, "function")) {
            var el = this;
            var fn2 = function (event) {
                fn.apply(el, [event]);
            };
        }

        this.node.addEventListener(
            /Firefox/i.test(navigator.userAgent) ? "DOMMouseScroll" : "mousewheel",
            fn2);

        return this;
    };


    // Snap's attr function can be too slow for things like panning/zooming.
    // This is a function to directly update element attributes without going
    // through eve.
    Element.prototype.attribute = function(key, val) {
        if (val === undefined) {
            return this.node.getAttribute(key);
        } else {
            this.node.setAttribute(key, val);
            return this;
        }
    };

    Element.prototype.init_gadfly = function() {
        this.mouseenter(Gadfly.plot_mouseover)
            .mouseleave(Gadfly.plot_mouseout)
            .dblclick(Gadfly.plot_dblclick)
            .mousewheel(Gadfly.guide_background_scroll)
            .drag(Gadfly.guide_background_drag_onmove,
                  Gadfly.guide_background_drag_onstart,
                  Gadfly.guide_background_drag_onend);
        this.mouseenter(function (event) {
            init_pan_zoom(this.plotroot());
        });
        return this;
    };
});


// When the plot is moused over, emphasize the grid lines.
Gadfly.plot_mouseover = function(event) {
    var root = this.plotroot();

    var keyboard_zoom = function(event) {
        if (event.which == 187) { // plus
            increase_zoom_by_position(root, 0.1, true);
        } else if (event.which == 189) { // minus
            increase_zoom_by_position(root, -0.1, true);
        }
    };
    root.data("keyboard_zoom", keyboard_zoom);
    window.addEventListener("keyup", keyboard_zoom);

    var xgridlines = root.select(".xgridlines"),
        ygridlines = root.select(".ygridlines");

    xgridlines.data("unfocused_strokedash",
                    xgridlines.attribute("stroke-dasharray").replace(/(\d)(,|$)/g, "$1mm$2"));
    ygridlines.data("unfocused_strokedash",
                    ygridlines.attribute("stroke-dasharray").replace(/(\d)(,|$)/g, "$1mm$2"));

    // emphasize grid lines
    var destcolor = root.data("focused_xgrid_color");
    xgridlines.attribute("stroke-dasharray", "none")
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    destcolor = root.data("focused_ygrid_color");
    ygridlines.attribute("stroke-dasharray", "none")
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    // reveal zoom slider
    root.select(".zoomslider")
        .animate({opacity: 1.0}, 250);
};

// Reset pan and zoom on double click
Gadfly.plot_dblclick = function(event) {
  set_plot_pan_zoom(this.plotroot(), 0.0, 0.0, 1.0);
};

// Unemphasize grid lines on mouse out.
Gadfly.plot_mouseout = function(event) {
    var root = this.plotroot();

    window.removeEventListener("keyup", root.data("keyboard_zoom"));
    root.data("keyboard_zoom", undefined);

    var xgridlines = root.select(".xgridlines"),
        ygridlines = root.select(".ygridlines");

    var destcolor = root.data("unfocused_xgrid_color");

    xgridlines.attribute("stroke-dasharray", xgridlines.data("unfocused_strokedash"))
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    destcolor = root.data("unfocused_ygrid_color");
    ygridlines.attribute("stroke-dasharray", ygridlines.data("unfocused_strokedash"))
              .selectAll("path")
              .animate({stroke: destcolor}, 250);

    // hide zoom slider
    root.select(".zoomslider")
        .animate({opacity: 0.0}, 250);
};


var set_geometry_transform = function(root, tx, ty, scale) {
    var xscalable = root.hasClass("xscalable"),
        yscalable = root.hasClass("yscalable");

    var old_scale = root.data("scale");

    var xscale = xscalable ? scale : 1.0,
        yscale = yscalable ? scale : 1.0;

    tx = xscalable ? tx : 0.0;
    ty = yscalable ? ty : 0.0;

    var t = new Snap.Matrix().translate(tx, ty).scale(xscale, yscale);

    root.selectAll(".geometry, image")
        .forEach(function (element, i) {
            element.transform(t);
        });

    bounds = root.plotbounds();

    if (yscalable) {
        var xfixed_t = new Snap.Matrix().translate(0, ty).scale(1.0, yscale);
        root.selectAll(".xfixed")
            .forEach(function (element, i) {
                element.transform(xfixed_t);
            });

        root.select(".ylabels")
            .transform(xfixed_t)
            .selectAll("text")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var cx = element.asPX("x"),
                        cy = element.asPX("y");
                    var st = element.data("static_transform");
                    unscale_t = new Snap.Matrix();
                    unscale_t.scale(1, 1/scale, cx, cy).add(st);
                    element.transform(unscale_t);

                    var y = cy * scale + ty;
                    element.attr("visibility",
                        bounds.y0 <= y && y <= bounds.y1 ? "visible" : "hidden");
                }
            });
    }

    if (xscalable) {
        var yfixed_t = new Snap.Matrix().translate(tx, 0).scale(xscale, 1.0);
        var xtrans = new Snap.Matrix().translate(tx, 0);
        root.selectAll(".yfixed")
            .forEach(function (element, i) {
                element.transform(yfixed_t);
            });

        root.select(".xlabels")
            .transform(yfixed_t)
            .selectAll("text")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var cx = element.asPX("x"),
                        cy = element.asPX("y");
                    var st = element.data("static_transform");
                    unscale_t = new Snap.Matrix();
                    unscale_t.scale(1/scale, 1, cx, cy).add(st);

                    element.transform(unscale_t);

                    var x = cx * scale + tx;
                    element.attr("visibility",
                        bounds.x0 <= x && x <= bounds.x1 ? "visible" : "hidden");
                    }
            });
    }

    // we must unscale anything that is scale invariance: widths, raiduses, etc.
    var size_attribs = ["font-size"];
    var unscaled_selection = ".geometry, .geometry *";
    if (xscalable) {
        size_attribs.push("rx");
        unscaled_selection += ", .xgridlines";
    }
    if (yscalable) {
        size_attribs.push("ry");
        unscaled_selection += ", .ygridlines";
    }

    root.selectAll(unscaled_selection)
        .forEach(function (element, i) {
            // circle need special help
            if (element.node.nodeName == "circle") {
                var cx = element.attribute("cx"),
                    cy = element.attribute("cy");
                unscale_t = new Snap.Matrix().scale(1/xscale, 1/yscale,
                                                        cx, cy);
                element.transform(unscale_t);
                return;
            }

            for (i in size_attribs) {
                var key = size_attribs[i];
                var val = parseFloat(element.attribute(key));
                if (val !== undefined && val != 0 && !isNaN(val)) {
                    element.attribute(key, val * old_scale / scale);
                }
            }
        });
};


// Find the most appropriate tick scale and update label visibility.
var update_tickscale = function(root, scale, axis) {
    if (!root.hasClass(axis + "scalable")) return;

    var tickscales = root.data(axis + "tickscales");
    var best_tickscale = 1.0;
    var best_tickscale_dist = Infinity;
    for (tickscale in tickscales) {
        var dist = Math.abs(Math.log(tickscale) - Math.log(scale));
        if (dist < best_tickscale_dist) {
            best_tickscale_dist = dist;
            best_tickscale = tickscale;
        }
    }

    if (best_tickscale != root.data(axis + "tickscale")) {
        root.data(axis + "tickscale", best_tickscale);
        var mark_inscale_gridlines = function (element, i) {
            var inscale = element.attr("gadfly:scale") == best_tickscale;
            element.attribute("gadfly:inscale", inscale);
            element.attr("visibility", inscale ? "visible" : "hidden");
        };

        var mark_inscale_labels = function (element, i) {
            var inscale = element.attr("gadfly:scale") == best_tickscale;
            element.attribute("gadfly:inscale", inscale);
            element.attr("visibility", inscale ? "visible" : "hidden");
        };

        root.select("." + axis + "gridlines").selectAll("path").forEach(mark_inscale_gridlines);
        root.select("." + axis + "labels").selectAll("text").forEach(mark_inscale_labels);
    }
};


var set_plot_pan_zoom = function(root, tx, ty, scale) {
    var old_scale = root.data("scale");
    var bounds = root.plotbounds();

    var width = bounds.x1 - bounds.x0,
        height = bounds.y1 - bounds.y0;

    // compute the viewport derived from tx, ty, and scale
    var x_min = -width * scale - (scale * width - width),
        x_max = width * scale,
        y_min = -height * scale - (scale * height - height),
        y_max = height * scale;

    var x0 = bounds.x0 - scale * bounds.x0,
        y0 = bounds.y0 - scale * bounds.y0;

    var tx = Math.max(Math.min(tx - x0, x_max), x_min),
        ty = Math.max(Math.min(ty - y0, y_max), y_min);

    tx += x0;
    ty += y0;

    // when the scale change, we may need to alter which set of
    // ticks is being displayed
    if (scale != old_scale) {
        update_tickscale(root, scale, "x");
        update_tickscale(root, scale, "y");
    }

    set_geometry_transform(root, tx, ty, scale);

    root.data("scale", scale);
    root.data("tx", tx);
    root.data("ty", ty);
};


var scale_centered_translation = function(root, scale) {
    var bounds = root.plotbounds();

    var width = bounds.x1 - bounds.x0,
        height = bounds.y1 - bounds.y0;

    var tx0 = root.data("tx"),
        ty0 = root.data("ty");

    var scale0 = root.data("scale");

    // how off from center the current view is
    var xoff = tx0 - (bounds.x0 * (1 - scale0) + (width * (1 - scale0)) / 2),
        yoff = ty0 - (bounds.y0 * (1 - scale0) + (height * (1 - scale0)) / 2);

    // rescale offsets
    xoff = xoff * scale / scale0;
    yoff = yoff * scale / scale0;

    // adjust for the panel position being scaled
    var x_edge_adjust = bounds.x0 * (1 - scale),
        y_edge_adjust = bounds.y0 * (1 - scale);

    return {
        x: xoff + x_edge_adjust + (width - width * scale) / 2,
        y: yoff + y_edge_adjust + (height - height * scale) / 2
    };
};


// Initialize data for panning zooming if it isn't already.
var init_pan_zoom = function(root) {
    if (root.data("zoompan-ready")) {
        return;
    }

    // The non-scaling-stroke trick. Rather than try to correct for the
    // stroke-width when zooming, we force it to a fixed value.
    var px_per_mm = root.node.getCTM().a;

    // Drag events report deltas in pixels, which we'd like to convert to
    // millimeters.
    root.data("px_per_mm", px_per_mm);

    root.selectAll("path")
        .forEach(function (element, i) {
        sw = element.asPX("stroke-width") * px_per_mm;
        if (sw > 0) {
            element.attribute("stroke-width", sw);
            element.attribute("vector-effect", "non-scaling-stroke");
        }
    });

    // Store ticks labels original tranformation
    root.selectAll(".xlabels > text, .ylabels > text")
        .forEach(function (element, i) {
            var lm = element.transform().localMatrix;
            element.data("static_transform",
                new Snap.Matrix(lm.a, lm.b, lm.c, lm.d, lm.e, lm.f));
        });

    var xgridlines = root.select(".xgridlines");
    var ygridlines = root.select(".ygridlines");
    var xlabels = root.select(".xlabels");
    var ylabels = root.select(".ylabels");

    if (root.data("tx") === undefined) root.data("tx", 0);
    if (root.data("ty") === undefined) root.data("ty", 0);
    if (root.data("scale") === undefined) root.data("scale", 1.0);
    if (root.data("xtickscales") === undefined) {

        // index all the tick scales that are listed
        var xtickscales = {};
        var ytickscales = {};
        var add_x_tick_scales = function (element, i) {
            xtickscales[element.attribute("gadfly:scale")] = true;
        };
        var add_y_tick_scales = function (element, i) {
            ytickscales[element.attribute("gadfly:scale")] = true;
        };

        if (xgridlines) xgridlines.selectAll("path").forEach(add_x_tick_scales);
        if (ygridlines) ygridlines.selectAll("path").forEach(add_y_tick_scales);
        if (xlabels) xlabels.selectAll("text").forEach(add_x_tick_scales);
        if (ylabels) ylabels.selectAll("text").forEach(add_y_tick_scales);

        root.data("xtickscales", xtickscales);
        root.data("ytickscales", ytickscales);
        root.data("xtickscale", 1.0);
    }

    var min_scale = 1.0, max_scale = 1.0;
    for (scale in xtickscales) {
        min_scale = Math.min(min_scale, scale);
        max_scale = Math.max(max_scale, scale);
    }
    for (scale in ytickscales) {
        min_scale = Math.min(min_scale, scale);
        max_scale = Math.max(max_scale, scale);
    }
    root.data("min_scale", min_scale);
    root.data("max_scale", max_scale);

    // store the original positions of labels
    if (xlabels) {
        xlabels.selectAll("text")
               .forEach(function (element, i) {
                   element.data("x", element.asPX("x"));
               });
    }

    if (ylabels) {
        ylabels.selectAll("text")
               .forEach(function (element, i) {
                   element.data("y", element.asPX("y"));
               });
    }

    // mark grid lines and ticks as in or out of scale.
    var mark_inscale = function (element, i) {
        element.attribute("gadfly:inscale", element.attribute("gadfly:scale") == 1.0);
    };

    if (xgridlines) xgridlines.selectAll("path").forEach(mark_inscale);
    if (ygridlines) ygridlines.selectAll("path").forEach(mark_inscale);
    if (xlabels) xlabels.selectAll("text").forEach(mark_inscale);
    if (ylabels) ylabels.selectAll("text").forEach(mark_inscale);

    // figure out the upper ond lower bounds on panning using the maximum
    // and minum grid lines
    var bounds = root.plotbounds();
    var pan_bounds = {
        x0: 0.0,
        y0: 0.0,
        x1: 0.0,
        y1: 0.0
    };

    if (xgridlines) {
        xgridlines
            .selectAll("path")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var bbox = element.node.getBBox();
                    if (bounds.x1 - bbox.x < pan_bounds.x0) {
                        pan_bounds.x0 = bounds.x1 - bbox.x;
                    }
                    if (bounds.x0 - bbox.x > pan_bounds.x1) {
                        pan_bounds.x1 = bounds.x0 - bbox.x;
                    }
                    element.attr("visibility", "visible");
                }
            });
    }

    if (ygridlines) {
        ygridlines
            .selectAll("path")
            .forEach(function (element, i) {
                if (element.attribute("gadfly:inscale") == "true") {
                    var bbox = element.node.getBBox();
                    if (bounds.y1 - bbox.y < pan_bounds.y0) {
                        pan_bounds.y0 = bounds.y1 - bbox.y;
                    }
                    if (bounds.y0 - bbox.y > pan_bounds.y1) {
                        pan_bounds.y1 = bounds.y0 - bbox.y;
                    }
                    element.attr("visibility", "visible");
                }
            });
    }

    // nudge these values a little
    pan_bounds.x0 -= 5;
    pan_bounds.x1 += 5;
    pan_bounds.y0 -= 5;
    pan_bounds.y1 += 5;
    root.data("pan_bounds", pan_bounds);

    root.data("zoompan-ready", true)
};


// drag actions, i.e. zooming and panning
var pan_action = {
    start: function(root, x, y, event) {
        root.data("dx", 0);
        root.data("dy", 0);
        root.data("tx0", root.data("tx"));
        root.data("ty0", root.data("ty"));
    },
    update: function(root, dx, dy, x, y, event) {
        var px_per_mm = root.data("px_per_mm");
        dx /= px_per_mm;
        dy /= px_per_mm;

        var tx0 = root.data("tx"),
            ty0 = root.data("ty");

        var dx0 = root.data("dx"),
            dy0 = root.data("dy");

        root.data("dx", dx);
        root.data("dy", dy);

        dx = dx - dx0;
        dy = dy - dy0;

        var tx = tx0 + dx,
            ty = ty0 + dy;

        set_plot_pan_zoom(root, tx, ty, root.data("scale"));
    },
    end: function(root, event) {

    },
    cancel: function(root) {
        set_plot_pan_zoom(root, root.data("tx0"), root.data("ty0"), root.data("scale"));
    }
};

var zoom_box;
var zoom_action = {
    start: function(root, x, y, event) {
        var bounds = root.plotbounds();
        var width = bounds.x1 - bounds.x0,
            height = bounds.y1 - bounds.y0;
        var ratio = width / height;
        var xscalable = root.hasClass("xscalable"),
            yscalable = root.hasClass("yscalable");
        var px_per_mm = root.data("px_per_mm");
        x = xscalable ? x / px_per_mm : bounds.x0;
        y = yscalable ? y / px_per_mm : bounds.y0;
        var w = xscalable ? 0 : width;
        var h = yscalable ? 0 : height;
        zoom_box = root.rect(x, y, w, h).attr({
            "fill": "#000",
            "opacity": 0.25
        });
        zoom_box.data("ratio", ratio);
    },
    update: function(root, dx, dy, x, y, event) {
        var xscalable = root.hasClass("xscalable"),
            yscalable = root.hasClass("yscalable");
        var px_per_mm = root.data("px_per_mm");
        var bounds = root.plotbounds();
        if (yscalable) {
            y /= px_per_mm;
            y = Math.max(bounds.y0, y);
            y = Math.min(bounds.y1, y);
        } else {
            y = bounds.y1;
        }
        if (xscalable) {
            x /= px_per_mm;
            x = Math.max(bounds.x0, x);
            x = Math.min(bounds.x1, x);
        } else {
            x = bounds.x1;
        }

        dx = x - zoom_box.attr("x");
        dy = y - zoom_box.attr("y");
        if (xscalable && yscalable) {
            var ratio = zoom_box.data("ratio");
            var width = Math.min(Math.abs(dx), ratio * Math.abs(dy));
            var height = Math.min(Math.abs(dy), Math.abs(dx) / ratio);
            dx = width * dx / Math.abs(dx);
            dy = height * dy / Math.abs(dy);
        }
        var xoffset = 0,
            yoffset = 0;
        if (dx < 0) {
            xoffset = dx;
            dx = -1 * dx;
        }
        if (dy < 0) {
            yoffset = dy;
            dy = -1 * dy;
        }
        if (isNaN(dy)) {
            dy = 0.0;
        }
        if (isNaN(dx)) {
            dx = 0.0;
        }
        zoom_box.transform("T" + xoffset + "," + yoffset);
        zoom_box.attr("width", dx);
        zoom_box.attr("height", dy);
    },
    end: function(root, event) {
        var xscalable = root.hasClass("xscalable"),
            yscalable = root.hasClass("yscalable");
        var zoom_bounds = zoom_box.getBBox();
        if (zoom_bounds.width * zoom_bounds.height <= 0) {
            return;
        }
        var plot_bounds = root.plotbounds();
        var zoom_factor = 1.0;
        if (yscalable) {
            zoom_factor = (plot_bounds.y1 - plot_bounds.y0) / zoom_bounds.height;
        } else {
            zoom_factor = (plot_bounds.x1 - plot_bounds.x0) / zoom_bounds.width;
        }
        var tx = (root.data("tx") - zoom_bounds.x) * zoom_factor + plot_bounds.x0,
            ty = (root.data("ty") - zoom_bounds.y) * zoom_factor + plot_bounds.y0;
        set_plot_pan_zoom(root, tx, ty, root.data("scale") * zoom_factor);
        zoom_box.remove();
    },
    cancel: function(root) {
        zoom_box.remove();
    }
};


Gadfly.guide_background_drag_onstart = function(x, y, event) {
    var root = this.plotroot();
    var scalable = root.hasClass("xscalable") || root.hasClass("yscalable");
    var zoomable = !event.altKey && !event.ctrlKey && event.shiftKey && scalable;
    var panable = !event.altKey && !event.ctrlKey && !event.shiftKey && scalable;
    var drag_action = zoomable ? zoom_action :
                      panable  ? pan_action :
                                 undefined;
    root.data("drag_action", drag_action);
    if (drag_action) {
        var cancel_drag_action = function(event) {
            if (event.which == 27) { // esc key
                drag_action.cancel(root);
                root.data("drag_action", undefined);
            }
        };
        window.addEventListener("keyup", cancel_drag_action);
        root.data("cancel_drag_action", cancel_drag_action);
        drag_action.start(root, x, y, event);
    }
};


Gadfly.guide_background_drag_onmove = function(dx, dy, x, y, event) {
    var root = this.plotroot();
    var drag_action = root.data("drag_action");
    if (drag_action) {
        drag_action.update(root, dx, dy, x, y, event);
    }
};


Gadfly.guide_background_drag_onend = function(event) {
    var root = this.plotroot();
    window.removeEventListener("keyup", root.data("cancel_drag_action"));
    root.data("cancel_drag_action", undefined);
    var drag_action = root.data("drag_action");
    if (drag_action) {
        drag_action.end(root, event);
    }
    root.data("drag_action", undefined);
};


Gadfly.guide_background_scroll = function(event) {
    if (event.shiftKey) {
        increase_zoom_by_position(this.plotroot(), 0.001 * event.wheelDelta);
        event.preventDefault();
    }
};


Gadfly.zoomslider_button_mouseover = function(event) {
    this.select(".button_logo")
         .animate({fill: this.data("mouseover_color")}, 100);
};


Gadfly.zoomslider_button_mouseout = function(event) {
     this.select(".button_logo")
         .animate({fill: this.data("mouseout_color")}, 100);
};


Gadfly.zoomslider_zoomout_click = function(event) {
    increase_zoom_by_position(this.plotroot(), -0.1, true);
};


Gadfly.zoomslider_zoomin_click = function(event) {
    increase_zoom_by_position(this.plotroot(), 0.1, true);
};


Gadfly.zoomslider_track_click = function(event) {
    // TODO
};


// Map slider position x to scale y using the function y = a*exp(b*x)+c.
// The constants a, b, and c are solved using the constraint that the function
// should go through the points (0; min_scale), (0.5; 1), and (1; max_scale).
var scale_from_slider_position = function(position, min_scale, max_scale) {
    var a = (1 - 2 * min_scale + min_scale * min_scale) / (min_scale + max_scale - 2),
        b = 2 * Math.log((max_scale - 1) / (1 - min_scale)),
        c = (min_scale * max_scale - 1) / (min_scale + max_scale - 2);
    return a * Math.exp(b * position) + c;
}

// inverse of scale_from_slider_position
var slider_position_from_scale = function(scale, min_scale, max_scale) {
    var a = (1 - 2 * min_scale + min_scale * min_scale) / (min_scale + max_scale - 2),
        b = 2 * Math.log((max_scale - 1) / (1 - min_scale)),
        c = (min_scale * max_scale - 1) / (min_scale + max_scale - 2);
    return 1 / b * Math.log((scale - c) / a);
}

var increase_zoom_by_position = function(root, delta_position, animate) {
    var scale = root.data("scale"),
        min_scale = root.data("min_scale"),
        max_scale = root.data("max_scale");
    var position = slider_position_from_scale(scale, min_scale, max_scale);
    position += delta_position;
    scale = scale_from_slider_position(position, min_scale, max_scale);
    set_zoom(root, scale, animate);
}

var set_zoom = function(root, scale, animate) {
    var min_scale = root.data("min_scale"),
        max_scale = root.data("max_scale"),
        old_scale = root.data("scale");
    var new_scale = Math.max(min_scale, Math.min(scale, max_scale));
    if (animate) {
        Snap.animate(
            old_scale,
            new_scale,
            function (new_scale) {
                update_plot_scale(root, new_scale);
            },
            200);
    } else {
        update_plot_scale(root, new_scale);
    }
}


var update_plot_scale = function(root, new_scale) {
    var trans = scale_centered_translation(root, new_scale);
    set_plot_pan_zoom(root, trans.x, trans.y, new_scale);

    root.selectAll(".zoomslider_thumb")
        .forEach(function (element, i) {
            var min_pos = element.data("min_pos"),
                max_pos = element.data("max_pos"),
                min_scale = root.data("min_scale"),
                max_scale = root.data("max_scale");
            var xmid = (min_pos + max_pos) / 2;
            var xpos = slider_position_from_scale(new_scale, min_scale, max_scale);
            element.transform(new Snap.Matrix().translate(
                Math.max(min_pos, Math.min(
                         max_pos, min_pos + (max_pos - min_pos) * xpos)) - xmid, 0));
    });
};


Gadfly.zoomslider_thumb_dragmove = function(dx, dy, x, y, event) {
    var root = this.plotroot();
    var min_pos = this.data("min_pos"),
        max_pos = this.data("max_pos"),
        min_scale = root.data("min_scale"),
        max_scale = root.data("max_scale"),
        old_scale = root.data("old_scale");

    var px_per_mm = root.data("px_per_mm");
    dx /= px_per_mm;
    dy /= px_per_mm;

    var xmid = (min_pos + max_pos) / 2;
    var xpos = slider_position_from_scale(old_scale, min_scale, max_scale) +
                   dx / (max_pos - min_pos);

    // compute the new scale
    var new_scale = scale_from_slider_position(xpos, min_scale, max_scale);
    new_scale = Math.min(max_scale, Math.max(min_scale, new_scale));

    update_plot_scale(root, new_scale);
    event.stopPropagation();
};


Gadfly.zoomslider_thumb_dragstart = function(x, y, event) {
    this.animate({fill: this.data("mouseover_color")}, 100);
    var root = this.plotroot();

    // keep track of what the scale was when we started dragging
    root.data("old_scale", root.data("scale"));
    event.stopPropagation();
};


Gadfly.zoomslider_thumb_dragend = function(event) {
    this.animate({fill: this.data("mouseout_color")}, 100);
    event.stopPropagation();
};


var toggle_color_class = function(root, color_class, ison) {
    var guides = root.selectAll(".guide." + color_class + ",.guide ." + color_class);
    var geoms = root.selectAll(".geometry." + color_class + ",.geometry ." + color_class);
    if (ison) {
        guides.animate({opacity: 0.5}, 250);
        geoms.animate({opacity: 0.0}, 250);
    } else {
        guides.animate({opacity: 1.0}, 250);
        geoms.animate({opacity: 1.0}, 250);
    }
};


Gadfly.colorkey_swatch_click = function(event) {
    var root = this.plotroot();
    var color_class = this.data("color_class");

    if (event.shiftKey) {
        root.selectAll(".colorkey text")
            .forEach(function (element) {
                var other_color_class = element.data("color_class");
                if (other_color_class != color_class) {
                    toggle_color_class(root, other_color_class,
                                       element.attr("opacity") == 1.0);
                }
            });
    } else {
        toggle_color_class(root, color_class, this.attr("opacity") == 1.0);
    }
};


return Gadfly;

}));


//@ sourceURL=gadfly.js

(function (glob, factory) {
    // AMD support
      if (typeof require === "function" && typeof define === "function" && define.amd) {
        require(["Snap.svg", "Gadfly"], function (Snap, Gadfly) {
            factory(Snap, Gadfly);
        });
      } else {
          factory(glob.Snap, glob.Gadfly);
      }
})(window, function (Snap, Gadfly) {
    var fig = Snap("#fig-f679eb34e3304a2b9eea5b9025b9d353");
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-4")
   .drag(function() {}, function() {}, function() {});
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-8")
   .init_gadfly();
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-11")
   .plotroot().data("unfocused_ygrid_color", "#D0D0E0")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-11")
   .plotroot().data("focused_ygrid_color", "#A0A0A0")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-12")
   .plotroot().data("unfocused_xgrid_color", "#D0D0E0")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-12")
   .plotroot().data("focused_xgrid_color", "#A0A0A0")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-19")
   .data("mouseover_color", "#CD5C5C")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-19")
   .data("mouseout_color", "#6A6A6A")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-19")
   .click(Gadfly.zoomslider_zoomin_click)
.mouseenter(Gadfly.zoomslider_button_mouseover)
.mouseleave(Gadfly.zoomslider_button_mouseout)
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-21")
   .data("max_pos", 96.01)
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-21")
   .data("min_pos", 79.01)
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-21")
   .click(Gadfly.zoomslider_track_click);
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-22")
   .data("max_pos", 96.01)
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-22")
   .data("min_pos", 79.01)
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-22")
   .data("mouseover_color", "#CD5C5C")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-22")
   .data("mouseout_color", "#6A6A6A")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-22")
   .drag(Gadfly.zoomslider_thumb_dragmove,
     Gadfly.zoomslider_thumb_dragstart,
     Gadfly.zoomslider_thumb_dragend)
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-23")
   .data("mouseover_color", "#CD5C5C")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-23")
   .data("mouseout_color", "#6A6A6A")
;
fig.select("#fig-f679eb34e3304a2b9eea5b9025b9d353-element-23")
   .click(Gadfly.zoomslider_zoomout_click)
.mouseenter(Gadfly.zoomslider_button_mouseover)
.mouseleave(Gadfly.zoomslider_button_mouseout)
;
    });
]]> </script>
</svg>



