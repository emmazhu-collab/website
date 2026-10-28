# Blog 8: all statistical computations are performed in R.
# Run from either the Blog 8 project root or the course website root.
library(plotly)
post_dir <- if (dir.exists("blog/posts/post8/code")) "blog/posts/post8" else "."
config_path <- file.path(post_dir, "code", "simulation_config.R")
if (!file.exists(config_path)) stop("Could not find code/simulation_config.R. Run this script from the Blog 8 project or course website folder.")
source(config_path)
levels_ci <- c(.90, .95, .99)
bootstrap_means <- function(x, B) {
  n <- length(x)
  draws <- matrix(x[sample.int(n, n * B, replace = TRUE)], nrow = n)
  colMeans(draws)
}
ci_from <- function(z, level) unname(quantile(z, c((1-level)/2, (1+level)/2)))
boot <- bootstrap_means(x, B)
ci_one <- lapply(levels_ci, function(level) ci_from(boot, level))
# Every outer iteration starts with a NEW independent original sample.
set.seed(seed_coverage)
coverage_intervals <- array(NA_real_, dim = c(M, 2, length(levels_ci)))
for (i in seq_len(M)) {
  fresh <- rnorm(n, mu, sigma)
  fresh_boot <- bootstrap_means(fresh, B)
  for (j in seq_along(levels_ci)) coverage_intervals[i,,j] <- ci_from(fresh_boot, levels_ci[j])
}
covered <- sapply(seq_along(levels_ci), function(j)
  coverage_intervals[,1,j] <= mu & mu <= coverage_intervals[,2,j])
coverage <- colMeans(covered)
mcse <- sqrt(coverage * (1-coverage) / M)
# Studentized statistic: use the sample SD, not the known simulation sigma.
t_stat <- function(y, mu0 = 0) (mean(y)-mu0)/(sd(y)/sqrt(length(y)))
observed_t <- t_stat(x)
set.seed(seed_null)
null_t <- replicate(S, t_stat(rnorm(n, 0, sigma)))
extreme <- sum(abs(null_t) >= abs(observed_t))
p_value <- (extreme+1)/(S+1)
alphas <- c(.10, .05, .01)
critical <- vapply(alphas, function(a) unname(quantile(abs(null_t), 1-a, type=1)), numeric(1))
# Checks of dimensions, quantiles, event counts and analytic benchmarks.
stopifnot(length(x)==n, length(boot)==B, all(is.finite(boot)),
          identical(dim(coverage_intervals), c(M,2L,3L)),
          all(coverage_intervals[,1,] <= coverage_intervals[,2,]),
          all(diff(coverage)>=0), length(null_t)==S,
          abs(mean(null_t))<.05,
          max(abs(critical-qt(1-alphas/2,n-1)))<.12,
          abs(p_value-2*pt(-abs(observed_t),n-1))<.015)
# Ensure replacement and sample size: resamples contain only original values.
set.seed(seed_resample_check)
check_sample <- sample(x, n, replace=TRUE)
stopifnot(length(check_sample)==n, all(check_sample %in% x), anyDuplicated(check_sample)>0)
results <- data.frame(confidence=levels_ci, lower=sapply(ci_one,`[`,1),
 upper=sapply(ci_one,`[`,2), coverage=coverage, mcse=mcse,
 average_width=sapply(seq_along(levels_ci),function(j) mean(coverage_intervals[,2,j]-coverage_intervals[,1,j])))

blue <- '#0072B2'; orange <- '#D55E00'; purple <- '#7B3294'
vline <- function(v,color,dash='dash') list(type='line',x0=v,x1=v,y0=0,y1=1,yref='paper',line=list(color=color,dash=dash,width=2))
base_layout <- function(p,xlab,ylab) layout(p,
 xaxis=list(title=xlab,zeroline=FALSE),yaxis=list(title=ylab,zeroline=FALSE),
 font=list(size=14),margin=list(t=150,b=100,l=65,r=20),
 legend=list(orientation='h',x=0,y=-.2),hovermode='closest')
menu <- function(buttons) list(list(type='buttons',direction='right',active=1,x=0,y=1.34,xanchor='left',buttons=buttons))
note <- function(txt) list(list(text=txt,x=0,y=1.15,xref='paper',yref='paper',xanchor='left',showarrow=FALSE,font=list(size=12)))
boot_shapes <- function(j) list(vline(mean(x),'#222222','solid'),vline(ci_one[[j]][1],orange),vline(ci_one[[j]][2],orange))
boot_note <- function(j) note(sprintf('%d%% CI: [%.3f, %.3f] mm | Mean: %.3f mm',100*levels_ci[j],ci_one[[j]][1],ci_one[[j]][2],mean(x)))
fig_boot <- plot_ly(height=560,x=boot,type='histogram',nbinsx=40,marker=list(color=blue),showlegend=FALSE,
 hovertemplate='Bootstrap mean: %{x:.3f} mm<br>Count: %{y}<extra></extra>')
fig_boot <- base_layout(fig_boot,'Bootstrap sample mean (mm)','Number of bootstrap resamples')
fig_boot <- layout(fig_boot,shapes=boot_shapes(2),annotations=boot_note(2),
 updatemenus=menu(lapply(1:3,function(j) list(label=paste0(100*levels_ci[j],'% confidence'),method='relayout',args=list(list(shapes=boot_shapes(j),annotations=boot_note(j)))))))

# Show the first 50 intervals, never a selected subset of hits/misses.
fig_coverage <- plot_ly(height=560)
for (j in 1:3) for (hit in c(TRUE,FALSE)) {
 idx <- which(covered[1:50,j]==hit)
 xx <- as.vector(rbind(coverage_intervals[idx,1,j],coverage_intervals[idx,2,j],NA_real_))
 yy <- as.vector(rbind(idx,idx,NA_real_))
 fig_coverage <- add_trace(fig_coverage,x=xx,y=yy,type='scatter',mode='lines',
  name=if(hit)'Contains true mean' else 'Misses true mean',
  line=list(color=if(hit)blue else orange,width=if(hit)2 else 3,dash=if(hit)'solid' else 'dash'),
  visible=j==2,hovertemplate='Endpoint: %{x:.3f} mm<br>Sample: %{y}<extra>%{fullData.name}</extra>')
}
coverage_note <- function(j) note(sprintf('%d%% confidence | Coverage: %.2f%% (%s/%s)<br>Average interval width: %.3f mm',100*levels_ci[j],100*coverage[j],format(sum(covered[,j]),big.mark=","),format(M,big.mark=","),results$average_width[j]))
fig_coverage <- base_layout(fig_coverage,'Confidence interval for mean error (mm)','Independent sample number')
fig_coverage <- layout(fig_coverage,xaxis=list(range=range(coverage_intervals[1:50,,])),
 shapes=list(vline(mu,'#222222','solid')),annotations=coverage_note(2),
 updatemenus=menu(lapply(1:3,function(j) list(label=paste0(100*levels_ci[j],'% confidence'),method='update',args=list(list(visible=rep(1:3==j,each=2)),list(annotations=coverage_note(j)))))))

# Histogram counts partition the SAME null simulations into p-value tails and center.
regular_breaks <- seq(floor(min(null_t)*10)/10,ceiling(max(null_t)*10)/10,by=.1)
# Place bin edges at the observed-statistic cutoffs so no bin mixes tail and center values.
breaks <- sort(unique(c(regular_breaks, -abs(observed_t), abs(observed_t))))
bin_widths <- diff(breaks)
fig_test <- plot_ly(height=560)
for (tail in c(FALSE,TRUE)) {
 z <- null_t[(abs(null_t)>=abs(observed_t))==tail]
 h <- hist(z,breaks=breaks,plot=FALSE)
 fig_test <- add_bars(fig_test,x=h$mids,y=h$counts,width=bin_widths,
  name=if(tail)'At least as extreme as observed' else 'Less extreme',
  marker=list(color=if(tail)orange else '#A8B7C4'),
  hovertemplate='Null t bin: %{x:.2f}<br>Count: %{y}<extra>%{fullData.name}</extra>')
}
test_shapes <- function(j) list(
 list(type='rect',x0=min(breaks),x1=-critical[j],y0=0,y1=1,yref='paper',fillcolor=purple,opacity=.12,line=list(width=0),layer='below'),
 list(type='rect',x0=critical[j],x1=max(breaks),y0=0,y1=1,yref='paper',fillcolor=purple,opacity=.12,line=list(width=0),layer='below'),
 vline(-critical[j],purple),vline(critical[j],purple),
 vline(observed_t,'#222222','solid'),vline(-observed_t,'#222222','dot'))
test_note <- function(j) note(sprintf('α = %.2f | Reject if |t| > %.3f <br>p = %.4f | %s',alphas[j],critical[j],p_value,if(abs(observed_t)>critical[j])'Reject H₀' else 'Do not reject H₀'))
fig_test <- base_layout(fig_test,'t = (sample mean - 0) / (sample SD / sqrt(100))','Number of null simulations')
fig_test <- layout(fig_test,barmode='stack',bargap=0,shapes=test_shapes(2),annotations=test_note(2),
 updatemenus=menu(lapply(1:3,function(j) list(label=paste0('α = ',alphas[j]),method='relayout',args=list(list(shapes=test_shapes(j),annotations=test_note(j)))))))
fig_boot <- config(fig_boot,displayModeBar=FALSE,responsive=TRUE)
fig_coverage <- config(fig_coverage,displayModeBar=FALSE,responsive=TRUE)
fig_test <- config(fig_test,displayModeBar=FALSE,responsive=TRUE)

# Save each interactive figure as a standalone HTML output for the project.
results_dir <- file.path(post_dir, "results")
dir.create(results_dir, showWarnings = FALSE)
htmlwidgets::saveWidget(fig_boot, file.path(results_dir, "bootstrap_distribution.html"), selfcontained = FALSE)
htmlwidgets::saveWidget(fig_coverage, file.path(results_dir, "coverage_simulation.html"), selfcontained = FALSE)
htmlwidgets::saveWidget(fig_test, file.path(results_dir, "null_distribution_test.html"), selfcontained = FALSE)
