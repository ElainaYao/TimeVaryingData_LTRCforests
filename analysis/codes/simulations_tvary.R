##########################################################################
## load the LTRCforests package
library(LTRCforests)

## load the modified transformation packages 
setwd("./TimeVaryingData_LTRCforests/analysis/utils/transformation/mlt_mod")
devtools::load_all()

setwd("./TimeVaryingData_LTRCforests/analysis/utils/transformation/tram_mod")
devtools::load_all()

setwd("./TimeVaryingData_LTRCforests/analysis/utils/transformation/trtf_mod")
devtools::load_all()

# sessionInfo()
##########################################################################
library(ipred)
library(partykit)
library(survival)
library(prodlim)
library(truncdist)
library(pec)
setwd("./TimeVaryingData_LTRCforests/analysis/data/")
source("Timevarying_nonPH_gnrt.R")
source("Timevarying_PH_itct_gnrt.R")
source("Timevarying_PH_nonlinear_gnrt.R")
source("Timevarying_PH_linear_gnrt.R")
setwd("../utils/")
source("Loss_funct_tvary.R")
source("Surv_funct.R")
source("tsf_tvary_funct.R")

#####################################################################################################################
Pred_funct <- function(N = 1000, 
                       model = c("linear", "nonlinear", "interaction"), 
                       censor.rate = 1, 
                       ll, 
                       setting = c("PH","nonPH"),
                       Nfold = 10,
                       snrhigh = FALSE,
                       variation = FALSE){

  L2mtry <- data.frame(matrix(0, nrow = 7, ncol = 3))
  names(L2mtry) <- c("cf", "rrf", "tsf")
  rownames(L2mtry) = c("20", "10", "5", "3", "2", "1", "opt")


  OOBmtry <- data.frame(matrix(0, nrow = 6, ncol = 3))
  names(OOBmtry) <- c("cf", "rrf", "tsf")
  rownames(OOBmtry) = c("20", "10", "5", "3", "2", "1")

  L2 <- data.frame(matrix(0, nrow = 1, ncol = 8))
  names(L2) <- c("KM", "cx", "cfD", "cfP", "rrfD", "rrfP", "tsfD", "tsfP")
  
  mtryall = data.frame(matrix(0, nrow = 1, ncol = 3))
  names(mtryall) <- c("cf", "rrf", "tsf")
  
  L2seu = data.frame(matrix(0, nrow = 1, ncol = 3))
  names(L2seu) <- c("cf", "rrf", "tsf")
  
  ibsCVerr = data.frame(matrix(0, nrow = Nfold, ncol = 4))
  names(ibsCVerr) = c("cx", "cf", "rrf", "tsf")
  
  RES = list(caseI = list(L2mtry = L2mtry, OOBmtry = OOBmtry, L2 = L2, L2seu = L2seu,
                          mtryall = mtryall, ibsCVerr = ibsCVerr),
             caseII = list(L2mtry = L2mtry, OOBmtry = OOBmtry, L2 = L2,
                           mtryall = mtryall, ibsCVerr = ibsCVerr))


  ###################### ---------------- Time-varying ----------------- ###############################
  if (setting == "PH"){
    set.seed(101)
    sampleID = sample(10000000, 500)
    set.seed(sampleID[ll])
    if (model == "linear"){
      RET <- Timevarying_PH_linear_gnrt(N = N, censor.rate = censor.rate, 
                                        variation = variation,
                                        snrhigh = snrhigh)
    } else if (model == "nonlinear") {
      RET <- Timevarying_PH_nonlinear_gnrt(N = N, censor.rate = censor.rate, 
                                           variation = variation,
                                           snrhigh = snrhigh)
    } else if (model == "interaction") {
      RET <- Timevarying_PH_itct_gnrt(N = N, censor.rate = censor.rate, 
                                      variation = variation,
                                      snrhigh = snrhigh)
    } else {
      stop("Wrong model type is used.")
    }
  } else {
    set.seed(101)
    sampleID = sample(10000000,500)
    set.seed(sampleID[ll])
    
    RET = Timevarying_nonPH_gnrt(N = N, model = model, censor.rate = censor.rate, 
                                 variation = variation,
                                 snrhigh = snrhigh)
  }
  ptlDATA <- RET$partialData
  fullDATA <- RET$fullData
  Info = RET$Info
  
  rm(RET)
  gc()

  #### Time points to be evaluated
  Tpnt = c(0,sort(unique(fullDATA$Stop)), seq(max(fullDATA$Stop) + 5, 1.5*max(fullDATA$Stop), by = 5))
  TauI = sapply(1:N, function(i){ 1.5 * max(fullDATA[fullDATA$ID == i, ]$Stop) })
  TauII = sapply(1:N, function(i){ 1.5 * max(ptlDATA[ptlDATA$ID == i, ]$Stop) })
  ###################### ---------------- 20 noise variables ----------------- ###############################
  Formula = Surv(Start,Stop,Event) ~ X1+X2+X3+X4+X5+X6+X7+X8+X9+X10+X11+X12+X13+X14+X15+X16+X17+X18+X19+X20
  Formula_TD = Surv(Start,Stop,Event, type = "counting") ~ X1+X2+X3+X4+X5+X6+X7+X8+X9+X10+X11+X12+X13+X14+X15+X16+X17+X18+X19+X20
  Formula_TD0 = Surv(Start,Stop,Event, type = "counting") ~ 1
  ntree = 100L
  
  print("Dataset has been created ...")

  ## The pool of mtry searched by the tuning procedure
  mtrypool <- c(20, 10, 5, 3, 2, 1)
  mtryD <- ceiling(sqrt(20))
  ################## ============== L2 -- LTRCTSF =================== #####################
  leftzero = which(RES$caseI$L2mtry$tsf[1:6] == 0)
  if (length(leftzero) > 0){
    for (jj in leftzero){
      #### Different mtry for TSF
      modelT <- tsf_wy(formula = Formula_TD, data = fullDATA, 
                       mtry = mtrypool[jj], ntree = ntree)
      predT <- predict_tsf_wy(object = modelT)
      
      RES$caseI$L2mtry$tsf[jj] = l2(data = fullDATA, info = Info, 
                                    pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
      rm(predT)
      predOOB <- predict_tsf_wy(object = modelT, OOB = TRUE)
      
      Shat = shat(fullDATA, pred = predOOB, tpnt = Tpnt)
      predOOBnew = list(survival.probs = Shat, survival.times = Tpnt, survival.tau = TauI)
      rm(Shat)
      RES$caseI$OOBmtry$tsf[jj] = sbrier_ltrc(obj = Surv(fullDATA$Start, fullDATA$Stop, fullDATA$Event), 
                                              id = fullDATA$ID, pred = predOOBnew)
      # RES$caseI$OOBmtry$tsf[jj] = bs(data = fullDATA, pred = predOOB, tpnt = Tpnt)
      print(sprintf("CASEI: TSF -- mtry = %1.0f is done", mtrypool[jj]))
      rm(predOOB)
      rm(predOOBnew)
      rm(modelT)
      gc()
    }
  }
  
  if (RES$caseI$L2$tsfP[1] == 0){
    idxmin = which.min(RES$caseI$OOBmtry$tsf)
    ## L2 errors of the forests with mtry chosen by OOB
    RES$caseI$L2$tsfP = RES$caseI$L2mtry$tsf[idxmin]
    ## L2 errors of the forests with the best mtry 
    RES$caseI$L2mtry$tsf[7] = min(RES$caseI$L2mtry$tsf[1:6])
    RES$caseI$mtryall$tsf = mtrypool[idxmin]
  }
  print("Case I -- tsfP is done ...")
  
  if (RES$caseI$L2$tsfD[1] == 0){
    ## Training
    modelT <- tsf_wy(formula = Formula_TD, data = fullDATA, mtry = mtryD, ntree = ntree,
                     control = partykit::ctree_control(teststat = "quad", testtype = "Univ",
                                                       mincriterion = 0, saveinfo = FALSE,
                                                       minsplit = 20,
                                                       minbucket = 7,
                                                       minprob = 0.01))
    predT <- predict_tsf_wy(object = modelT)
    
    RES$caseI$L2$tsfD <- l2(data = fullDATA, info = Info, 
                            pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case I -- tsfD is done ...")
  
  if (RES$caseI$L2seu$tsf[1] == 0){
    ## Training
    modelT <- tsf_wy(formula = Formula_TD, data = fullDATA, mtry = mtryD, ntree = ntree,
                     bootstrap = "by.root")
    predT <- predict_tsf_wy(object = modelT)
    
    RES$caseI$L2seu$tsf <- l2(data = fullDATA, info = Info, 
                              pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case I -- tsf with bootstrapping pseudo-subject is done ...")
  
  leftzero = which(RES$caseII$L2mtry$tsf[1:6] == 0)
  if (length(leftzero) > 0){
    for (jj in leftzero){
      #### Different mtry for TSF
      modelT <- tsf_wy(formula = Formula_TD, data = ptlDATA, 
                       mtry = mtrypool[jj], ntree = ntree)
      predT <- predict_tsf_wy(object = modelT)
      
      RES$caseII$L2mtry$tsf[jj] = l2(data = ptlDATA, fulldata = fullDATA, info = Info, 
                                     pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
      rm(predT)
      predOOB <- predict_tsf_wy(object = modelT, OOB = TRUE)
      
      Shat = shat(ptlDATA, pred = predOOB, tpnt = Tpnt)
      predOOBnew = list(survival.probs = Shat, survival.times = Tpnt, survival.tau = TauII)
      rm(Shat)
      RES$caseII$OOBmtry$tsf[jj] = sbrier_ltrc(obj = Surv(ptlDATA$Start, ptlDATA$Stop, ptlDATA$Event), 
                                               id = ptlDATA$ID, pred = predOOBnew)
      # RES$caseII$OOBmtry$tsf[jj] = bs(data = ptlDATA, pred = predOOB, tpnt = Tpnt)
      print(sprintf("CASEII: TSF -- mtry = %1.0f is done", mtrypool[jj]))
      rm(predOOB)
      rm(predOOBnew)
      rm(modelT)
      gc()
    }
  }

  if (RES$caseII$L2$tsfP[1] == 0){
    idxmin = which.min(RES$caseII$OOBmtry$tsf)
    ## L2 errors of the forests with mtry chosen by OOB
    RES$caseII$L2$tsfP = RES$caseII$L2mtry$tsf[idxmin]
    ## L2 errors of the forests with the best mtry 
    RES$caseII$L2mtry$tsf[7] = min(RES$caseII$L2mtry$tsf[1:6])
    RES$caseII$mtryall$tsf = mtrypool[idxmin]
  }
  
  print("Case II -- tsfP is done ...")
  
  if (RES$caseII$L2$tsfD[1] == 0){
    ## Training
    modelT <- tsf_wy(formula = Formula_TD, data = ptlDATA, mtry = mtryD, ntree = ntree,
                     control = partykit::ctree_control(teststat = "quad", testtype = "Univ",
                                                       mincriterion = 0, saveinfo = FALSE,
                                                       minsplit = 20,
                                                       minbucket = 7,
                                                       minprob = 0.01))
    predT <- predict_tsf_wy(object = modelT)
    
    RES$caseII$L2$tsfD <- l2(data = ptlDATA, fulldata = fullDATA, info = Info, 
                             pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case II -- tsfD is done ...")
  
  ################## ============== L2 -- LTRCCIF =================== #####################
  leftzero = which(RES$caseI$L2mtry$cf[1:6] == 0)
  if (length(leftzero) > 0){
    for (jj in leftzero){
      #### Different mtry for CF
      modelT <- ltrccif(formula = Formula, data = fullDATA, id = ID, 
                       mtry = mtrypool[jj], ntree = ntree)
      predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
      RES$caseI$L2mtry$cf[jj] <- l2(data = fullDATA, info = Info, pred = predT$survival.probs, tpnt = Tpnt)
      rm(predT)
      predOOB <- predictProb(object = modelT, time.eval = Tpnt, time.tau = TauI, OOB = TRUE)
      # RES$caseI$OOBmtry$cf[jj] <- bs(data = fullDATA, pred = predOOB$survival.probs, tpnt = Tpnt)
      RES$caseI$OOBmtry$cf[jj] <- sbrier_ltrc(obj = Surv(fullDATA$Start, fullDATA$Stop, fullDATA$Event), 
                                              id = fullDATA$ID, pred = predOOB, type="IBS")
      # obj = Surv(fullDATA$Start,fullDATA$Stop,fullDATA$Event)
      # RES$caseI$OOBmtry$cf[jj] <- sbrier_ltrc(obj = obj, id = fullDATA$ID, pred = predOOB, type="IBS")
      print(sprintf("CASEI: CF -- mtry = %1.0f is done", mtrypool[jj]))
      rm(predOOB)
      rm(modelT)
      gc()
    }
  }
  
  if (RES$caseI$L2$cfP[1] == 0){
    idxmin = which.min(RES$caseI$OOBmtry$cf)
    ## L2 errors of the forests with mtry chosen by OOB
    RES$caseI$L2$cfP = RES$caseI$L2mtry$cf[idxmin]
    ## L2 errors of the forests with the best mtry 
    RES$caseI$L2mtry$cf[7] = min(RES$caseI$L2mtry$cf[1:6])
    RES$caseI$mtryall$cf = mtrypool[idxmin]
  }
  
  print("Case I -- cfP is done ...")
  
  if (RES$caseI$L2$cfD[1] == 0){
    ## Training
    modelT = ltrccif(formula = Formula, data = fullDATA, id = ID, 
                    control = partykit::ctree_control(teststat = "quad", testtype = "Univ",
                                                      mincriterion = 0, saveinfo = FALSE,
                                                      minsplit = 20,
                                                      minbucket = 7,
                                                      minprob = 0.01),
                    mtry = mtryD, ntree = ntree)
    predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
    RES$caseI$L2$cfD <- l2(data = fullDATA, fulldata = fullDATA, 
                           info = Info, pred = predT$survival.probs, tpnt = Tpnt)
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case I -- cfD is done ...")
  
  leftzero = which(RES$caseII$L2mtry$cf[1:6] == 0)
  if (length(leftzero) > 0){
    for (jj in leftzero){
      #### Different mtry for LTRCCIF
      modelT <- ltrccif(formula = Formula, data = ptlDATA, id = ID, 
                       mtry = mtrypool[jj], ntree = ntree)
      predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
      RES$caseII$L2mtry$cf[jj] <- l2(data = ptlDATA, fulldata = fullDATA, info = Info, pred = predT$survival.probs, tpnt = Tpnt)
      rm(predT)
      predOOB <- predictProb(object = modelT, time.eval = Tpnt, time.tau = TauII, OOB = TRUE)
      # RES$caseII$OOBmtry$cf[jj] <- bs(data = ptlDATA, pred = predOOB$survival.probs, tpnt = Tpnt)
      RES$caseII$OOBmtry$cf[jj] <- sbrier_ltrc(obj = Surv(ptlDATA$Start, ptlDATA$Stop, ptlDATA$Event), 
                                               id = ptlDATA$ID, pred = predOOB, type="IBS")
      print(sprintf("CASEII: CF -- mtry = %1.0f is done", mtrypool[jj]))
      rm(predOOB)
      rm(modelT)
      gc()
    }
  }

  if (RES$caseI$L2seu$cf[1] == 0){
    ## Training
    modelT <- ltrccif(formula = Formula, data = fullDATA, id = ID, 
                     bootstrap = "by.root",
                     mtry = mtryD, ntree = ntree)
    predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
    
    RES$caseI$L2seu$cf <- l2(data = fullDATA, info = Info, 
                             pred = predT$survival.probs, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case I -- cf with bootstrapping pseudo-subject is done ...")
  
  if (RES$caseII$L2$cfP[1] == 0){
    idxmin = which.min(RES$caseII$OOBmtry$cf)
    ## L2 errors of the forests with mtry chosen by OOB
    RES$caseII$L2$cfP = RES$caseII$L2mtry$cf[idxmin]
    ## L2 errors of the forests with the best mtry 
    RES$caseII$L2mtry$cf[7] = min(RES$caseII$L2mtry$cf[1:6])
    RES$caseII$mtryall$cf = mtrypool[idxmin]
  }
  print("Case II -- cfP is done ...")
  
  if (RES$caseII$L2$cfD[1] == 0){
    ## Training
    modelT = ltrccif(formula = Formula, data = ptlDATA, id = ID, 
                    control = partykit::ctree_control(teststat = "quad", testtype = "Univ",
                                                      mincriterion = 0, saveinfo = FALSE,
                                                      minsplit = 20,
                                                      minbucket = 7,
                                                      minprob = 0.01),
                    mtry = mtryD, ntree = ntree)
    predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
    RES$caseII$L2$cfD <- l2(data = ptlDATA, fulldata = fullDATA, 
                            info = Info, pred = predT$survival.probs, tpnt = Tpnt)
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case II -- cfD is done ...")
  
  ################## ============== L2 -- LTRCRRF =================== #####################
  leftzero = which(RES$caseI$L2mtry$rrf[1:6] == 0)
  if (length(leftzero) > 0){
    for (jj in leftzero){
      #### Different mtry for RRF
      modelT = ltrcrrf(formula = Formula, data = fullDATA, id = ID, 
                       mtry = mtrypool[jj], ntree = ntree)
      predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
      RES$caseI$L2mtry$rrf[jj] = l2(data = fullDATA, info = Info, pred = predT$survival.probs, tpnt = Tpnt)
      predOOB <- predictProb(object = modelT, time.eval = Tpnt, time.tau = TauI, OOB = TRUE)
      # RES$caseI$OOBmtry$rrf[jj] = bs(data = fullDATA, pred = predOOB$survival.probs, tpnt = Tpnt)
      RES$caseI$OOBmtry$rrf[jj] = sbrier_ltrc(obj = Surv(fullDATA$Start, fullDATA$Stop, fullDATA$Event), 
                                              id = fullDATA$ID, pred = predOOB, type = "IBS")
      print(sprintf("CASEI: RRF -- mtry = %1.0f is done",mtrypool[jj]))
      rm(predOOB)
      rm(modelT)
      gc()
    }
  }

  if (RES$caseI$L2$rrfP[1] == 0){
    idxmin = which.min(RES$caseI$OOBmtry$rrf)
    ## L2 errors of the forests with mtry chosen by OOB
    RES$caseI$L2$rrfP = RES$caseI$L2mtry$rrf[idxmin]
    ## L2 errors of the forests with the best mtry 
    RES$caseI$L2mtry$rrf[7] = min(RES$caseI$L2mtry$rrf[1:6])
    RES$caseI$mtryall$rrf = mtrypool[idxmin]
  }
  print("Case I -- rrfP is done ...")
  
  if (RES$caseI$L2$rrfD[1] == 0){
    ## Training
    modelT = ltrcrrf(formula = Formula, data = fullDATA, id = ID, 
                     nodesize = 15,
                     mtry = mtryD, ntree = ntree)
    predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
    RES$caseI$L2$rrfD <- l2(data = fullDATA, fulldata = fullDATA, 
                            info = Info, pred = predT$survival.probs, tpnt = Tpnt)
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case I -- rrfD is done ...")
  
  if (RES$caseI$L2seu$rrf[1] == 0){
    ## Training
    modelT <- ltrcrrf(formula = Formula, data = fullDATA, id = ID, 
                      bootstrap = "by.root",
                      mtry = mtryD, ntree = ntree)
    predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
    
    RES$caseI$L2seu$rrf <- l2(data = fullDATA, info = Info, 
                             pred = predT$survival.probs, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case I -- rrf with bootstrapping pseudo-subject is done ...")
  
  
  leftzero = which(RES$caseII$L2mtry$rrf[1:6] == 0)
  if (length(leftzero) > 0){
    for (jj in leftzero){
      #### Different mtry for RRF
      modelT = ltrcrrf(formula = Formula, data = ptlDATA, id = ID, 
                       mtry = mtrypool[jj], ntree = ntree)
      predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
      RES$caseII$L2mtry$rrf[jj] = l2(data = ptlDATA, fulldata = fullDATA, info = Info, pred = predT$survival.probs, tpnt = Tpnt)
      predOOB <- predictProb(object = modelT, time.eval = Tpnt, time.tau = TauII, OOB = TRUE)
      # RES$caseII$OOBmtry$rrf[jj] = bs(data = ptlDATA, pred = predOOB$survival.probs, tpnt = Tpnt)
      RES$caseII$OOBmtry$rrf[jj] = sbrier_ltrc(obj = Surv(ptlDATA$Start, ptlDATA$Stop, ptlDATA$Event), 
                                               id = ptlDATA$ID, pred = predOOB, type = "IBS")
      print(sprintf("CASEII: RRF -- mtry = %1.0f is done",mtrypool[jj]))
      rm(predOOB)
      rm(modelT)
      gc()
    }
  }
  
  if (RES$caseII$L2$rrfP[1] == 0){
    idxmin = which.min(RES$caseII$OOBmtry$rrf)
    ## L2 errors of the forests with mtry chosen by OOB
    RES$caseII$L2$rrfP <- RES$caseII$L2mtry$rrf[idxmin]
    ## L2 errors of the forests with the best mtry 
    RES$caseII$L2mtry$rrf[7] = min(RES$caseII$L2mtry$rrf[1:6])
    RES$caseII$mtryall$rrf = mtrypool[idxmin]
  }
  print("Case II -- rrfP is done ...")
  
  if (RES$caseII$L2$rrfD[1] == 0){
    ## Training
    modelT = ltrcrrf(formula = Formula, data = ptlDATA, id = ID, 
                     nodesize = 15,
                     mtry = mtryD, ntree = ntree)
    predT <- predictProb(object = modelT, time.eval = Tpnt[Tpnt <= max(fullDATA$Stop)])
    RES$caseII$L2$rrfD <- l2(data = ptlDATA, fulldata = fullDATA, 
                             info = Info, pred = predT$survival.probs, tpnt = Tpnt)
    rm(modelT)
    rm(predT)
    gc()
  }
  print("Case II -- rrfD is done ...")
  
  ################## ============== L2 -- Cox =================== #####################
  Coxfit <- coxph(formula = Formula, fullDATA)
  #### Prediction
  predT <- survfit(Coxfit, newdata = fullDATA)
  rm(Coxfit)
  gc()
  RES$caseI$L2$cx = l2(data = fullDATA, fulldata = fullDATA, info = Info, 
                       pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
  print("Case I -- Cox is done ...")
  
  Coxfit <- coxph(formula = Formula, ptlDATA)
  #### Prediction
  predT <- survfit(Coxfit, newdata = ptlDATA)
  rm(Coxfit)
  gc()
  RES$caseII$L2$cx = l2(data = ptlDATA, fulldata = fullDATA, info = Info, 
                       pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
  print("Case II -- Cox is done ...")
  
  ################## ============== L2 -- KM =================== #####################
  KMfit = survfit(Surv(Start, Stop, Event) ~ 1, data = ptlDATA)
  predT = rep(list(KMfit), nrow(ptlDATA))
  RES$caseI$L2$KM = l2(data = ptlDATA, fulldata = fullDATA, info = Info, 
                       pred = predT, tpnt = Tpnt[Tpnt <= max(fullDATA$Stop)])
  
  RES$caseII$L2$KM = RES$caseI$L2$KM
  print("KM is done ...")
  
  ################## ============== IBS-based CV =================== #####################
  #### Case I
  if (RES$caseI$ibsCVerr[Nfold, 4]==0){
    id_uniq = unique(fullDATA$ID)
    set.seed(sampleID[ll])
    kfold = kfoldcv(k = Nfold, N = N)
    
    dataCV = rep(list(0), Nfold)
    id_uniq_spd = sample(id_uniq, N)
    for (kk in 1:Nfold){
      dataCV[[kk]] = id_uniq_spd[((kk - 1) * kfold[kk] + 1):(kk * kfold[kk])]
    }
    
    foldleft = which(RES$caseI$ibsCVerr[, 4] == 0)
    for (jj in foldleft){
      idxCV = which(fullDATA$ID %in% dataCV[[jj]])
      data_b = fullDATA[-idxCV, ]
      newdata_b = fullDATA[idxCV, ]
      Sobj_b = Surv(newdata_b$Start, newdata_b$Stop, newdata_b$Event)
      
      id_uniq_new = unique(newdata_b$ID)
      n_uniq_new = length(id_uniq_new)
      tau_b = sapply(1:n_uniq_new, function(i){ 1.5 * max(newdata_b[newdata_b$ID == id_uniq_new[i], ]$Stop)})
      ## Cox
      if (RES$caseI$ibsCVerr[jj, 1]==0){
        #### Training
        Coxfit <- coxph(formula = Formula, data_b)
        #### Prediction
        predT <- survfit(Coxfit, newdata = newdata_b)
        rm(Coxfit)
        gc()
        Shat = shat(newdata_b, pred = predT, tpnt = Tpnt)
        predTnew = list(survival.probs = Shat, survival.times = Tpnt, survival.tau = tau_b)
        rm(Shat)
        RES$caseI$ibsCVerr[jj, 1] = sbrier_ltrc(obj = Sobj_b, id = newdata_b$ID, pred = predTnew)
        # RES$caseI$ibsCVerr[jj, 1] = bs(data = newdata_b, pred = predT, tpnt = Tpnt)
        rm(predTnew)
        rm(Coxfit)
        rm(predT)
      }
      ## cif
      if (RES$caseI$ibsCVerr[jj, 2]==0){
        mtryT = RES$caseI$mtryall$cf
        
        modelT <- ltrccif(formula = Formula, data = data_b, id = ID, 
                         mtry = mtryT, ntree = ntree)
        predT <- predictProb(object = modelT, newdata = newdata_b, newdata.id = ID, 
                                time.eval = Tpnt[Tpnt <= max(newdata_b$Stop) * 1.5],
                                time.tau = tau_b)
      
        RES$caseI$ibsCVerr[jj, 2] <- sbrier_ltrc(obj = Sobj_b, pred = predT, id = newdata_b$ID)
        # RES$caseI$ibsCVerr[jj, 2] <- bs(data = newdata_b, pred = predT$survival.probs, tpnt = Tpnt)
        rm(modelT)
        rm(predT)
        gc()
      }
      ## rrf
      if (RES$caseI$ibsCVerr[jj,3]==0){
        mtryT = RES$caseI$mtryall$rrf
        modelT <- ltrcrrf(formula = Formula, data = data_b, id = ID, 
                          mtry = mtryT, ntree = ntree)
        predT <- predictProb(object = modelT, newdata = newdata_b, newdata.id = ID, 
                             time.eval = Tpnt[Tpnt <= max(newdata_b$Stop) * 1.5],
                             time.tau = tau_b)
        
        RES$caseI$ibsCVerr[jj, 3] <- sbrier_ltrc(obj = Sobj_b, pred = predT, id = newdata_b$ID)
        # RES$caseI$ibsCVerr[jj, 3] <- bs(data = newdata_b, pred = predT$survival.probs, tpnt = Tpnt)
        rm(modelT)
        rm(predT)
        gc()
      }
      ## tsf
      if (RES$caseI$ibsCVerr[jj,4]==0){
        mtryT = RES$caseI$mtryall$tsf
        modelT <- tsf_wy(formula = Formula_TD, data = data_b, 
                         mtry = mtryT, ntree = ntree)
        predT <- predict_tsf_wy(object = modelT, newdata = newdata_b)
        rm(modelT)
        
        Shat = shat(newdata_b, pred = predT, tpnt = Tpnt)
        predTnew = list(survival.probs = Shat, survival.times = Tpnt, survival.tau = tau_b)
        rm(Shat)
        RES$caseI$ibsCVerr[jj, 4] = sbrier_ltrc(obj = Sobj_b, id = newdata_b$ID, pred = predTnew)
        # RES$caseI$ibsCVerr[jj, 4] = bs(data = newdata_b, pred = predT, tpnt = Tpnt)
        rm(predTnew)
        rm(predT)
        gc()
      }
      print(sprintf("CaseI -- IBSCV Round %1.0f is done",jj))
    }
    
  }
  #### Case II
  if (RES$caseII$ibsCVerr[Nfold, 4]==0){
    id_uniq = unique(ptlDATA$ID)
    set.seed(sampleID[ll])
    kfold = kfoldcv(k = Nfold, N = N)
    
    dataCV = rep(list(0), Nfold)
    id_uniq_spd = sample(id_uniq, N)
    for (kk in 1:Nfold){
      dataCV[[kk]] = id_uniq_spd[((kk - 1) * kfold[kk] + 1):(kk * kfold[kk])]
    }
    
    foldleft = which(RES$caseII$ibsCVerr[, 4] == 0)
    for (jj in foldleft){
      idxCV = which(ptlDATA$ID %in% dataCV[[jj]])
      data_b = ptlDATA[-idxCV, ]
      newdata_b = ptlDATA[idxCV, ]
      Sobj_b = Surv(newdata_b$Start, newdata_b$Stop, newdata_b$Event)
      
      id_uniq_new = unique(newdata_b$ID)
      n_uniq_new = length(id_uniq_new)
      tau_b = sapply(1:n_uniq_new, function(i){ 1.5 * max(newdata_b[newdata_b$ID == id_uniq_new[i], ]$Stop) })
      ## Cox
      if (RES$caseII$ibsCVerr[jj, 1]==0){
        #### Training
        Coxfit <- coxph(formula = Formula, data_b)
        #### Prediction
        predT <- survfit(Coxfit, newdata = newdata_b)
        rm(Coxfit)
        gc()
        Shat = shat(newdata_b, pred = predT, tpnt = Tpnt)
        predTnew = list(survival.probs = Shat, survival.times = Tpnt, survival.tau = tau_b)
        rm(Shat)
        RES$caseII$ibsCVerr[jj, 1] = sbrier_ltrc(obj = Sobj_b, id = newdata_b$ID, pred = predTnew)
        # RES$caseII$ibsCVerr[jj, 1] = bs(data = newdata_b, pred = predT, tpnt = Tpnt)
        rm(predTnew)
        rm(Coxfit)
        rm(predT)
      }
      ## cfT
      if (RES$caseII$ibsCVerr[jj, 2]==0){
        mtryT = RES$caseII$mtryall$cf
        
        modelT <- ltrccif(formula = Formula, data = data_b, id = ID, 
                         mtry = mtryT, ntree = ntree)
        predT <- predictProb(object = modelT, newdata = newdata_b, newdata.id = ID, 
                                time.eval = Tpnt[Tpnt <= max(newdata_b$Stop) * 1.5],
                                time.tau = tau_b)
        
        RES$caseII$ibsCVerr[jj, 2] <- sbrier_ltrc(obj = Sobj_b,
                                                  pred = predT,
                                                  id = newdata_b$ID)
        # RES$caseII$ibsCVerr[jj, 2] <- bs(data = newdata_b, pred = predT$survival.probs, tpnt = Tpnt)
        rm(modelT)
        rm(predT)
        gc()
      }
      ## rrf
      if (RES$caseII$ibsCVerr[jj, 3]==0){
        mtryT = RES$caseII$mtryall$rrf
        modelT <- ltrcrrf(formula = Formula, data = data_b, id = ID, 
                          mtry = mtryT, ntree = ntree)
        predT <- predictProb(object = modelT, newdata = newdata_b, newdata.id = ID, 
                             time.eval = Tpnt[Tpnt <= max(newdata_b$Stop) * 1.5],
                             time.tau = tau_b)
        
        RES$caseII$ibsCVerr[jj, 3] <- sbrier_ltrc(obj = Sobj_b,
                                                  pred = predT,
                                                  id = newdata_b$ID)
        # RES$caseII$ibsCVerr[jj, 3] <- bs(data = newdata_b, pred = predT$survival.probs, tpnt = Tpnt)
        rm(predT)
        rm(modelT)
        gc()
      }
      ## tsf
      if (RES$caseII$ibsCVerr[jj, 4] == 0){
        mtryT = RES$caseII$mtryall$tsf
        modelT <- tsf_wy(formula = Formula_TD, data = data_b, 
                         mtry = mtryT, ntree = ntree)
        predT <- predict_tsf_wy(object = modelT, newdata = newdata_b)
        rm(modelT)
        
        Shat = shat(newdata_b, pred = predT, tpnt = Tpnt)
        predTnew = list(survival.probs = Shat, survival.times = Tpnt, survival.tau = tau_b)
        rm(Shat)
        RES$caseII$ibsCVerr[jj, 4] = sbrier_ltrc(obj = Sobj_b, id = newdata_b$ID, 
                                                 pred = predTnew)
        # RES$caseII$ibsCVerr[jj, 4] = bs(data = newdata_b, pred = predT, tpnt = Tpnt)
        rm(predTnew)
        rm(predT)
        gc()
      }
      print(sprintf("CaseII -- IBSCV Round %1.0f is done",jj))
    }
    
  }
  return(RES)
}

############################################################################################
nndata = c(100,300,500) 
Nfold = 10 # 10-fold IBS-based CV

setting = "nonPH" # or "PH"
model = "linear" # or "nonlinear", "interaction"
nn = 1 # nndata = c(100, 300, 500) 
censor.rate = 1 # 1-10%, 2-50%
variation = FALSE # FALSE -- "2TI + 4TV"; TRUE -- "2TI + 1TV"
snrhigh = FALSE # FALSE -- signal-to-noise ratio LOW; signal-to-noise ratio HIGH

# ll-th iteration
ll = 1
RES <- Pred_funct(N = 20, 
                  model = model, 
                  ll = ll, setting = setting, Nfold = Nfold, 
                  censor.rate = censor.rate, 
                  variation = variation,
                  snrhigh = snrhigh)
############################################################################################
