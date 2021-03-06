## Load packages
library(MASS)
library(tidyverse)
library(invgamma)

#################### Hyperparameters to be tuned during the DP Mixture ##################
## Total number of iteraitons
T = 200
## Hyperparameter for DP
M = c(1)
## Initialial number of clusters
n = 5

## The probability of the sample belongs to each cluster
prob = c(0.2, 0.3, 0.5)

## The mean and variance for each cluster
mu1 = c(6, 2)
mu2 = c(8, 12)
mu3 = c(3, 14)
mu = rbind(mu1, mu2, mu3)

sigma = diag(c(1, 1))

## The total number of data points
N = 100

## Hyperparameter for G_0
mu0 = list()
mu0[[1]] = c(0,0)
sigma0 = list()
sigma0[[1]] = diag(c(1, 1))

## prior for M
c = 1
d = 1

## Hyperparameter for mu0 and sigma0
m0 = c(0,0)
D = diag(c(10, 10))

## Hyperparameter for a1 and b1
a1 = 1
b1 = 1

## Number of clusters
Cluster_num = 10

#########################################################################################


######################Function to compute bivariate normal density######################
bivariate_normal <- function(y_temp, mu_temp, sigma_temp){
  return(1 / (2 * pi * det(sigma_temp)^0.5) * exp( - 1 / 2 * (y_temp - mu_temp) %*% solve(sigma_temp) %*% (y_temp - mu_temp) ))
}
#########################################################################################





############################ Generate the Gaussian Mixture Model############################ 
data_store = c()
index_store = c()
## Generate the data points from the model
for(i in 1 : N){
  index = sample(3, 1, prob = prob)
  data_store = rbind(data_store, mvrnorm(1, mu[index, ], sigma))
  index_store = c(index_store, index)
}
###########################################################################################


## Start of the MCMC

s = list()
s[[1]] = sample(Cluster_num, N, replace = TRUE)
theta = list()
theta[[1]] = matrix(runif(n * 2, -10, 10), nrow = n)


for(t in 1 : T){
  
  ## Frequency table for all the n's
  frequency_table = table(c(1 : max(s[[t]]), s[[t]])) - 1
  theta_num = max(s[[t]])
  s[[t + 1]] = s[[t]]
  
  ## Sample si for each sample
  for(i in 1 : N){
    #theta_num = max(s[[t + 1]])
    frequency_table_i = frequency_table
    frequency_table_i[s[[t]][i]] = frequency_table[s[[t]][i]] - 1
    
    ## Collapsed V and m for the sample
    V = list()
    m = list()
    
    prob_i = rep(0, theta_num + 1)
    
    for(j in 1 : theta_num){
      ## The probability to sample from each cluster
      if(sum(s[[t + 1]][-i] == j) > 0){
        V[[j]] = solve(solve(sigma0[[t]]) + frequency_table_i[j] * solve(sigma))
        m[[j]] = V[[j]] %*% (solve(sigma0[[t]]) %*% mu0[[t]] + sigma %*% apply(matrix((data_store[-i, ])[which(s[[t]][-i] == j), ], ncol = 2), 2, sum))
        prob_i[j] = frequency_table_i[j] * bivariate_normal(data_store[i, ], as.vector(m[[j]]), V[[j]] + sigma)
      }else{
        prob_i[j] = 0
      }
      
    }
    prob_i[theta_num + 1] = M[t] * bivariate_normal(data_store[i, ], mu0[[t]], sigma0[[t]] + sigma)
    prob_i = prob_i / sum(prob_i)
    s[[t + 1]][[i]] = sample(length(prob_i), 1, prob = prob_i)
  }
  
  theta[[t + 1]] = list()
  
  ## Sample theta_j for each group
  for(j in 1 : max(s[[t + 1]])){
    sum_y = apply(matrix(data_store[which(s[[t + 1]] == j), ], ncol = 2), 2, sum)
    n_y = nrow(matrix(data_store[which(s[[t + 1]] == j), ], ncol = 2))
    
    if(sum(s[[t + 1]] == j) > 0){
      ## The sigma and theta for the multivariate normal
      sigma_theta = solve(solve(sigma0[[t]]) + n_y * solve(sigma))
      mu_theta = sigma_theta %*% (solve(sigma0[[t]]) %*% mu0[[t]] + solve(sigma)  %*% sum_y)
      theta[[t + 1]][[j]] = mvrnorm(1, mu_theta, sigma_theta)
    }else{
      theta[[t + 1]][[j]] = NULL
    }
  }
  print(table(s[[t]]))
  #print(theta[[t]][[1]])
  
  ## Update M 
  ## Latent variable used to generate M
  eta = rbeta(1, M[t] + 1, n)
  ## k is used in the update
  k = 0
  for(j in length(theta[[t + 1]])){
    if(!is.null(theta[[t + 1]][j])){
      k = k + 1
    }
  }
  p.est = rbernoulli(1, p = (c + k - 1) / (c + k - 1 + nrow(data_store) * (d - log(eta))))
  if(p.est == 1){
    M[t + 1] = rgamma(1, c + k, d - log(eta))
  }else{
    M[t + 1] = rgamma(1, c + k - 1, d - log(eta))
  }
  #print(M[t + 1])
  
  
  ## Update mu0 for the prior
  theta_k = 0
  for(j in 1 : length(theta[[t + 1]])){
    if(!is.null(theta[[t + 1]][[j]])){
      theta_k = theta_k + theta[[t + 1]][[j]]
    }
  }
  
  D1 = solve(solve(D) + solve(sigma0[[t]]) * k)
  m1 = D1 %*% (solve(D) %*% m0 + solve(sigma0[[t]]) %*% theta_k)
  mu0[[t + 1]] = mvrnorm(1, m1, D1)
  
  
  
  ## Update sigma0 for the prior
  alpha1 = k + a1 + 1
  beta1 = b1
  for(j in 1 : length(theta[[t + 1]])){
    if(!is.null(theta[[t + 1]][j])){
      beta1 = beta1 + 1 / 2 * sum((theta[[t + 1]][[j]]- mu0[[t + 1]])^2)
    }
  }
  sigma0[[t + 1]] = diag(2) * rinvgamma(1, alpha1, beta1)
  
  
}

par(mfrow = c(2,2))
acf(M)
plot(M, type = "l", main = "Time Series Plot of the estimated M")
plot(data_store, col = s[[t]], main = "Clustering result")
plot(data_store, col = index_store, main = "Data Generateing Result")

