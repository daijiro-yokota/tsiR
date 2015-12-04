#' mcmctsir function
#' 
#' This function runs the TSIR model using MCMC estimation.
#' @param data, the data frame containing cases and interpolated births and populations.
#' @param nsim, the number of simulations to do. Defaults to 100.
#' @param xreg, the x-axis for the regression. Options are 'cumcases' and 'cumbirths'. Defaults to 'cumcases'.
#' @param IP, the infectious period in weeks. Defaults to 2 weeks.
#' @param regtype, the type of regression used in susceptible reconstruction. 
#' Options are 'gaussian', 'lm' (linear model), 'spline' (smooth.spline with 2.5 degrees freedom),
#' 'lowess' (with f = 2/3, iter = 1), 'loess' (degree 1), and 'user' which is just a user inputed vector.
#' Defaults to 'gaussian' and if that fails then defaults to loess.
#' @param sigmamax, the inverse kernal width for the gaussian regression. Default is 3. 
#' Smaller, stochastic outbreaks tend to need a lower sigma.
#' @param userYhat, the inputed regression vector if regtype='user'. Defaults to NULL.
#' @param fittype, the type of fit used. Options are 'all' which fits beta, sbar, and alpha, 
#' 'fixalpha', which fixes alpha at 0.97 and estimates beta and sbar, and
#' 'less' which fits only beta and fixes alpha at 0.97.
#' @param n.chains, number of MCMC chains to use. Default is 3.
#' @param update.iter, number of MCMC iterations to use in the update aspect. Default is 10000.
#' @param n.iter, number of MCMC iterations to use. Default is 30000.
#' @param n.adapt, adaptive number for MCMC. Default is 1000.
#' @param burn.in, burn in number. Default is 100.
#' @param sbar, the mean number of susceptibles. Only used if fittype='less'. Defaults to 0.05*mean(pop).
#' @param method, the type of next step prediction used. Options are 'negbin' for negative binomial,
#' 'pois' for poisson distribution, and 'deterministic'. Defaults to 'deterministic'.
#' @param epidemics, the type of data splitting. Options are 'cont' which doesn't split the data up at all,
#' and 'break' which breaks the epidemics up if there are a lot of zeros. Defaults to 'cont'.
#' @param pred, the type of prediction used. Options are 'forward' and 'step-ahead'. Defaults to 'forward'.
#' @param threshold, the cut off for a new epidemic if epidemics = 'break'. Defaults to 1.
#' @param add.noise.sd, the sd for additive noise, defaults to zero.
#' @param mul.noise.sd, the sd for multiplicative noise, defaults to zero.
#' @param printon, whether to show diagnostic prints or not, defaults to FALSE.
mcmctsir <- function(data, xreg = 'cumcases',
                     IP = 2,nsim = 100,
                     regtype = 'gaussian',sigmamax = 3,
                     userYhat = numeric(),
                     fittype = 'all',
                     update.iter=10000,
                     n.iter=30000, n.chains=3, 
                     n.adapt=1000,burn.in=100,
                     method='deterministic',epidemics='cont', pred ='forward',
                     threshold=1,sbar=0.05,
                     add.noise.sd = 0, mul.noise.sd = 0,
                     printon=F){
  
  nzeros <- length(which(data$cases==0))
  ltot <- length(data$cases)
  if(nzeros > 0.3 * ltot && epidemics == 'cont'){
    print(sprintf('time series is %.0f%% zeros, consider using break method',100*nzeros/ltot))
  }
  
  if(n.iter < 5000){
    
    print('number of MCMC iterations less than 5000 -- increase')
    
  }
  
  print('MCMC may take a while')
  
  cumbirths <- cumsum(data$births)
  cumcases <- cumsum(data$cases)
  
  if(xreg == 'cumcases'){
    X <- cumcases
    Y <- cumbirths
  }
  
  if(xreg == 'cumbirths'){
    X <- cumbirths
    Y <- cumcases
  }
  
  x = linspace(X[1], X[length(X)], length(X))
  y = approxfun(X, Y)(x)
  y[1] = y[2] - (y[3]-y[2])
  
  if(regtype == 'lm'){
    Yhat <- predict(lm(Y~X))
  }
  
  if(regtype == 'lowess'){
    Yhat <- lowess(X,Y,f = 2/3, iter = 1)$y
  }
  
  if(regtype == 'loess'){
    Yhat <- predict(loess(y~x,se=T,family='gaussian',degree=1,model=T),X)
  }
  
  if(regtype == 'spline'){
    Yhat <- predict(smooth.spline(x,y,df=2.5),X)$y
  }
  
  if(regtype == 'gaussian'){
    
    sigvec <- seq(sigmamax,0,-0.1)
    for(it in 1:length(sigvec)){
      
      if(printon == T){
        print(sprintf('gaussian regression attempt number %d',it))
      }
      
      Yhat <- predict(gausspr(x,y,variance.model=T,fit=T,tol=1e-7,
                              var=9.999999999999999999e-3,
                              kernel="rbfdot",
                              kpar=list(sigma=sigvec[it])),X)
      
      
      if(sigvec[it] <= min(sigvec)){
        ## use the loess then
        print('guassian regressian failed -- switching to loess regression')
        Yhat <- predict(loess(y~x,se=T,family='gaussian',degree=1,model=T),X)
      }
      
      
      if(xreg == 'cumcases'){
        Z <- residual.cases(Yhat,Y)
        rho <- derivative(X,Yhat)
        if(length(which(rho<=1))==0){
          break()
        }
      }
      if(xreg == 'cumbirths'){
        Z <- residual.births(Yhat,Y)
        rho <- derivative(X,Yhat)
        if(length(which(rho>=1))==0 && length(which(rho<0)) == 0){
          break()
        }
      }
    }
  }
  
  
  if(regtype == 'user'){
    Yhat <- userYhat
    if(length(Yhat)==0){
      stop('Yhat returns numeric(0) -- make sure to input a userYhat under regtype=user')
    }
  }
  
  rho <- derivative(X,Yhat)
  
  if(xreg == 'cumcases'){
    Z <- residual.cases(Yhat,Y)
  }
  
  if(xreg == 'cumbirths'){
    Z <- residual.births(Yhat,Y)
  }
  
  if(xreg == 'cumcases'){
    adj.rho <- rho
  }
  if(xreg == 'cumbirths'){
    adj.rho <- 1/rho
  }
  
  if(regtype == 'lm'){
    adj.rho <- signif(adj.rho,3)
    
  }
  
  Iadjusted <- data$cases * adj.rho
  
  datacopy <- data
  data$cases[data$cases ==0] <- 1
  
  period <- rep(1:(52/IP), round(nrow(data)+1))[1:(nrow(data)-1)]
  
  if(IP == 1){
    
    period <- rep(1:(52/2),each=2, round(nrow(data)+1))[1:(nrow(data)-1)]
    
  }
  
  Inew <- tail(Iadjusted,-1)+1
  lIold <- log(head(Iadjusted,-1)+1)
  Zold <- head(Z,-1)
  
  pop <- data$pop
  
  Smean <- seq(0.001, 0.4, by=0.001)*mean(pop)
  
  alphalow <- NA
  alphahigh <- NA
  
  llik <- rep(NA, length(Smean))
  if(fittype == 'all'){
    
    
    for(i in 1:length(Smean)){
      lSold <- log(Smean[i] + Zold)
      
      glmfit <- glm(Inew ~ -1 +as.factor(period) + (lIold) + offset(lSold),
                    family=poisson(link='log'))
      
      
      llik[i] <- glmfit$deviance
      
    }
    
    sbar <- Smean[which.min(llik)]
    
    lSold <- log(sbar + Zold)
    
    lSold[is.nan(lSold)] <- 0
    lSold[lSold < 0] <- 0
    
    
    factorperiod <- as.factor(period)
    mod <- model.matrix(~-1+factorperiod)
    
    numseas <- length(unique(period))
    mymodel <- textConnection('model{
                                alpha ~ dunif(0.5,0.99)
                                for(season in 1:numseas){
                                beta[season] ~ dunif(-12,-3)
                                }
                                
                                sigma ~ dunif(0,10)
                                
                                for (t in 1:N){
                                
                                ## no intercept
                                regsum[t] <- mod[t,] %*%beta + alpha*lIold[t] + lSold[t] + e[t]
                                rate[t] <- exp(regsum[t])
                                Inew[t] ~ dpois(rate[t])
                                e[t] ~ dnorm(0, (1/sigma^2))
                                }
                                
  }')
    
    jags_data_list=list(
      "mod" = mod,
      "Inew"=round(Inew),
      "lIold"=as.numeric(lIold),
      "lSold"=as.numeric(lSold),
      "numseas" = numseas,
      "N" = length(lIold)
    )
    
    theModel <- jags.model(mymodel,data=jags_data_list,n.chains=n.chains)
    update(theModel,update.iter)
    inits = list("alpha" = 0.97)
    mcmcsamples <- coda.samples(theModel,c("alpha","beta",'sigma'),
                                inits=inits,n.iter=n.iter, n.adapt=n.adapt,burn.in=burn.in)
    
    results <-  as.data.frame(mcmcsamples[[1]])
    
    mcmctruncated <- tail(mcmcsamples,5000)
    
    jagsres <- jagsresults(x=mcmctruncated, param=names(results))
    jagsres <- jagsres[,c('mean', '2.5%', '97.5%')]
    
    beta <- exp(jagsres[2:(length(unique(period))+1),1])
    betalow <- exp(jagsres[2:(length(unique(period))+1),2])
    betahigh <- exp(jagsres[2:(length(unique(period))+1),3])
    
    alpha <- jagsres[1,1]
    alphalow <- jagsres[1,2]
    alphahigh <- jagsres[1,3]
  }
  
  
  
  
  if(fittype == 'fixalpha'){
    
    alpha <- 0.97
    
    
    for(i in 1:length(Smean)){
      lSold <- log(Smean[i] + Zold)
      
      
      glmfit <- glm(Inew ~ -1 +as.factor(period) + offset(alpha*lIold) + offset(lSold),
                    family=poisson(link='log'))
      
      
      llik[i] <- glmfit$deviance
      
    }
    
    
    
    sbar <- Smean[which.min(llik)]
    
    lSold <- log(sbar + Zold)
    
    
    lSold[is.nan(lSold)] <- 0
    lSold[lSold < 0] <- 0
    
    
    factorperiod <- as.factor(period)
    mod <- model.matrix(~-1+factorperiod)
    
    numseas <- length(unique(period))
    mymodel <- textConnection('model{
                              for(season in 1:numseas){
                              beta[season] ~ dunif(-12,-3)
                              }
                              
                              sigma ~ dunif(0,10)
                              
                              for (t in 1:N){
                              
                              ## no intercept
                              regsum[t] <- mod[t,] %*%beta + alpha*lIold[t] + lSold[t] + e[t]
                              rate[t] <- exp(regsum[t])
                              Inew[t] ~ dpois(rate[t])
                              e[t] ~ dnorm(0, (1/sigma^2))
                              }
                              
  }')
    
    jags_data_list=list(
      "mod" = mod,
      "alpha" = alpha,
      "Inew"=round(Inew),
      "lIold"=as.numeric(lIold),
      "lSold"=as.numeric(lSold),
      "numseas" = numseas,
      "N" = length(lIold)
    )
    
    theModel <- jags.model(mymodel,data=jags_data_list,n.chains=n.chains)
    update(theModel,update.iter)
    mcmcsamples <- coda.samples(theModel,c("beta",'sigma'),
                                n.iter=n.iter, n.adapt=n.adapt,burn.in=burn.in)
    
    results <-  as.data.frame(mcmcsamples[[1]])
    
    mcmctruncated <- tail(mcmcsamples,5000)
    
    jagsres <- jagsresults(x=mcmctruncated, param=names(results))
    jagsres <- jagsres[,c('mean', '2.5%', '97.5%')]
    
    beta <- exp(jagsres[1:length(unique(period)),1])
    betalow <- exp(jagsres[1:length(unique(period)),2])
    betahigh <- exp(jagsres[1:length(unique(period)),3])
    
    
  }
  
  
  
  if(fittype == 'less'){
    sbar <- sbar * mean(pop)
    alpha <- 0.97
    lSold <- log(sbar + Zold)
    
    
    
    lSold[is.nan(lSold)] <- 0
    lSold[lSold < 0] <- 0
    
    
    factorperiod <- as.factor(period)
    mod <- model.matrix(~-1+factorperiod)
    
    numseas <- length(unique(period))
    mymodel <- textConnection('model{
                              for(season in 1:numseas){
                              beta[season] ~ dunif(-12,-3)
                              }
                              
                              sigma ~ dunif(0,10)
                              
                              for (t in 1:N){
                              
                              ## no intercept
                              regsum[t] <- mod[t,] %*%beta + alpha*lIold[t] + lSold[t] + e[t]
                              rate[t] <- exp(regsum[t])
                              Inew[t] ~ dpois(rate[t])
                              e[t] ~ dnorm(0, (1/sigma^2))
                              }
                              
  }')
    
    jags_data_list=list(
      "mod" = mod,
      "alpha" = alpha,
      "Inew"=round(Inew),
      "lIold"=as.numeric(lIold),
      "lSold"=as.numeric(lSold),
      "numseas" = numseas,
      "N" = length(lIold)
    )
    
    theModel <- jags.model(mymodel,data=jags_data_list,n.chains=n.chains)
    update(theModel,update.iter)
    mcmcsamples <- coda.samples(theModel,c("beta",'sigma'),
                                n.iter=n.iter, n.adapt=n.adapt,burn.in=burn.in)
    
    results <-  as.data.frame(mcmcsamples[[1]])
    
    mcmctruncated <- tail(mcmcsamples,5000)
    
    jagsres <- jagsresults(x=mcmctruncated, param=names(results))
    jagsres <- jagsres[,c('mean', '2.5%', '97.5%')]
    
    beta <- exp(jagsres[1:length(unique(period)),1])
    betalow <- exp(jagsres[1:length(unique(period)),2])
    betahigh <- exp(jagsres[1:length(unique(period)),3])
    
    
  }
  
  contact <- as.data.frame(cbind('time'=seq(1,length(beta),1),betalow,beta,betahigh))
  
  print(c('alpha'=unname(signif(alpha,2)),
          'mean beta'=unname(signif(mean(beta),3)),
          'mean rho' =unname(signif(mean(1/adj.rho),3)),
          'mean sus' =unname(signif(sbar,3)),
          'est R0'=unname(signif(mean(beta)*mean(pop)^alpha),2)))
  
  
  nsim <- nsim
  res <- matrix(0,length(data$cases),nsim)
  for(ct in 1:nsim){
    
    S <- rep(0,length(data$cases))
    I <- rep(0,length(data$cases))
    S[1] <- sbar+Z[1]
    I[1] <- datacopy$cases[1] * adj.rho[1]
    
    for (t in 2:(nrow(data))){
      
      if(pred == 'step-ahead'){
        I <- (adj.rho*data$cases)^alpha
      }
      if(pred == 'forward'){
        I <- I
      }
      
      lambda <- unname(beta[period[t-1]] * S[t-1] * (I[t-1])^alpha)
      
      if(lambda < 1 || is.nan(lambda) == T){lambda <- 0}
      
      if(method == 'deterministic'){
        I[t] <- lambda * rnorm( n = 1, mean = 1, sd=mul.noise.sd)
        if(I[t] < 0 && lambda >= 0 ){
          warning('infected overflow  -- reduce multiplicative noise sd')
        }
      }
      if(method == 'negbin'){
        I[t] <- rnbinom(n=1,mu=lambda,size=I[t-1])
      }
      if(method == 'pois'){
        I[t] <- rpois(n=1,lambda=lambda)
      }
      if(epidemics == 'cont'){
        I[t] <- I[t]
      }
      if(epidemics == 'break'){
        
        t0s <- epitimes(data,threshold)
        if(t %in% t0s){
          I[t] <- adj.rho[t]*data$cases[t]
        }
      }
      S[t] <- Z[t]+sbar + rnorm(n = 1, mean = 0, sd=add.noise.sd)
      if(S[t] < 0 && (Z[t] + sbar) >0){
        warning('susceptible overflow  -- reduce additive noise sd')
      }
    }
    res[,ct] <- I / adj.rho
    
  }
  
  res[is.nan(res)] <- 1
  res[res < 1] <- 1
  
  res <- as.data.frame(res)
  res$mean <- apply(res, 1, function(row) mean(row[-1],na.rm=T))
  res$sd   <- apply(res, 1, function(row) sd(row[-1],na.rm=T))
  res$time <- data$time
  res$cases <- data$cases
  
  
  return(list('X'=X,'Y'=Y,'Yhat' =Yhat,'mcmcsamples'=mcmcsamples,
              'beta'=beta,'contact'=contact,'rho'=adj.rho,'pop'=pop,
              'Z'=Z,'sbar'=sbar,'alpha'=alpha,
              'alphalow'=alphalow,'alphahigh'=alphahigh,
              'res'=res,'loglik'=llik))
  
  
}
