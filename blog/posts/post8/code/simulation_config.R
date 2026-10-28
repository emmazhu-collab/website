# Shared simulation settings and the seeded original sample.
mu <- 0.4
sigma <- 2
n <- 100L
B <- 2000L
M <- 2000L
S <- 20000L

seed_sample <- 6408L
seed_coverage <- 6409L
seed_null <- 6410L
seed_resample_check <- 6411L

set.seed(seed_sample)
x <- rnorm(n, mean = mu, sd = sigma)
