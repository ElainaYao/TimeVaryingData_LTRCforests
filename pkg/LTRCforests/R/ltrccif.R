.logrank_trafo2 <- function(x2){
  if (sum(x2[, 3] == 1) == 0) {
    result <- x2[,3]
  } else {
    unique.times <- unique(x2[,2][which(x2[, 3] == 1)])
    D <- rep(NA, length(unique.times))
    R <- rep(NA, length(unique.times))

    for(j in 1:length(unique.times)){
      D[j] = sum(unique.times[j] == x2[, 2])
    }

    for(k in 1:length(unique.times) ){
      value <- unique.times[k]
      R[k] <- sum(apply(x2[, 1:2], 1, function(interval){interval[1] < value & value <= interval[2]}))
    }

    Ratio <- D / R

    Ratio <- Ratio[order(unique.times)]
    Nelson.Aalen <- cumsum(Ratio)
    Event.time <- unique.times[order(unique.times)]
    Left <- sapply(x2[, 1], function(t){if(t < min(Event.time)) return(0) else return(Nelson.Aalen[max(which(Event.time <= t))])})
    Right <- sapply(x2[, 2], function(t){if(t < min(Event.time)) return(0) else return(Nelson.Aalen[max(which(Event.time <= t))])})

    result<- x2[, 3] - (Right - Left)
  }
  return(as.double(result))
}

#' Fit a LTRC conditional inference forest
#'
#' An implementation of the random forest and bagging ensemble algorithms utilizing
#' LTRC conditional inference trees \code{\link[LTRCtrees]{LTRCIT}} as base learners for
#' left-truncated right-censored survival data with time-invariant covariates.
#' It also allows for (left-truncated) right-censored survival data with
#' time-varying covariates.
#'
#'
#' This function extends the conditional inference survival forest algorithm in
#' \code{\link[partykit]{cforest}} to fit left-truncated and right-censored data,
#' which allow for time-varying covariates.
#'
#' @param formula a formula object, with the response being a \code{\link[survival]{Surv}}
#' object, with form
#'
#'
#' \code{Surv(tleft, tright, event)}.
#' @param data a data frame containing \code{n} rows of
#' left-truncated right-censored observations.
#' For time-varying data, this should be
#' a data frame containing pseudo-subject observations based on the Andersen-Gill
#' reformulation.
#' @param id variable name of subject identifiers. If this is present, it will be
#' searched for in the \code{data} data frame. Each group of rows in \code{data}
#' with the same subject \code{id} represents the covariate path through time of
#' a single subject. If not specified, the algorithm then assumes \code{data}
#' contains left-truncated and right-censored survival data with time-invariant
#' covariates.
#' @param bootstrap bootstrap protocol.
#' (1) If \code{id} is present,
#' the choices are: \code{"by.sub"} (by default) which bootstraps subjects,
#' \code{"by.root"} which bootstraps pseudo-subjects.
#' Both can be with or without replacement (by default sampling is without
#' replacement; see the option \code{perturb} below);
#' (2) If \code{id} is not specified, it
#' bootstraps the \code{data} by sampling with or without replacement.
#' Regardless of the presence of \code{id}, if \code{"none"} is chosen,
#' \code{data} is not bootstrapped at all, and is used in
#' every individual tree. If \code{"by.user"} is choosen,
#' the bootstrap specified by \code{samp} is used.
#' @param samp Bootstrap specification when \code{bootstype = "by.user"}.
#' Array of dim \code{n x ntree} specifying how many times each record appears
#' in each bootstrap sample.
#' @param na.action action taken if the data contains \code{NA}’s. The default
#' \code{"na.omit"} removes the entire record if any of its entries is
#' \code{NA} (for x-variables this applies only to those specifically listed
#' in \code{formula}). See function \code{\link[partykit]{cforest}} for
#' other available options.
#' @param mtry number of input variables randomly sampled as candidates at each node for
#' random forest algorithms. The default \code{mtry} is tuned by \code{\link{tune.ltrccif}}.
#' @param ntree an integer, the number of the trees to grow for the forest.
#' \code{ntree = 100L} is set by default.
#' @param samptype choices are \code{swor} (sampling without replacement) and
#' \code{swr} (sampling with replacement). The default action here is sampling
#' without replacement.
#' @param sampfrac a fraction, determining the proportion of subjects to draw
#' without replacement when \code{samptype = "swor"}. The default value is \code{0.632}.
#' To be more specific, if \code{id} is present, \code{0.632 * N} of subjects with their
#' pseudo-subject observations are drawn without replacement (\code{N} denotes the
#' number of subjects); otherwise, \code{0.632 * n} is the requested size
#' of the sample.
#' @param applyfun an optional \code{lapply}-style function with arguments
#' \code{function(X, FUN, ...)}.
#' It is used for computing the variable selection criterion. The default is to use the
#' basic \code{lapply} function unless the \code{cores} argument is specified (see below).
#' See \code{\link[partykit]{ctree_control}}.
#' @param cores numeric. See \code{\link[partykit]{ctree_control}}.
#' @param trace whether to print the progress of the search of the optimal value of
#' \code{mtry}, when \code{mtry} is not specified (see \code{\link{tune.ltrccif}}).
#' \code{trace = TRUE} is set by default.
#' @param stepFactor at each iteration, \code{mtry} is inflated (or deflated)
#' by this value, used when \code{mtry} is not specified (see \code{\link{tune.ltrccif}}).
#' The default value is \code{2}.
#' @param control a list of control parameters, see \code{\link[partykit]{ctree_control}}.
#' \code{control} parameters \code{minsplit}, \code{minbucket} have been adjusted from the
#' \code{\link[partykit]{cforest}} defaults. Other default values correspond to those of the
#' default values used by \code{\link[partykit]{ctree_control}}.
#' @return An object belongs to the class \code{ltrccif}, as a subclass of
#' \code{\link[partykit]{cforest}}.
#' @import partykit
#' @import survival
#' @seealso \code{\link{predictProb}} for prediction and \code{\link{tune.ltrccif}}
#' for \code{mtry} tuning.
#' @references Andersen, P. and Gill, R. (1982). Cox's regression model for counting
#' processes, a large sample study. \emph{Annals of Statistics}, \strong{10}:1100-1120.
#' @references Fu, W. and Simonoff, J.S. (2016). Survival trees for left-truncated and 
#' right-censored data, with application to time-varying covariate data. 
#' \emph{Biostatistics}, \strong{18}(2):352–369.
#' @examples
#' #### Example with time-varying data pbcsample
#' library(survival)
#' Formula = Surv(Start, Stop, Event) ~ age + alk.phos + ast + chol + edema
#' ## Fit an LTRCCIF on the time-invariant data, with mtry tuned with stepFactor = 3.
#' LTRCCIFobj = ltrccif(formula = Formula, data = pbcsample, ntree = 20L, stepFactor = 3)
#' @export

ltrccif <- function(formula, data, id,
                    mtry = NULL, ntree = 100L,
                    bootstrap = c("by.sub","by.root","by.user","none"),
                    samptype = c("swor","swr"),
                    sampfrac = 0.632,
                    samp = NULL,
                    na.action = "na.omit",
                    stepFactor = 2,
                    trace = TRUE,
                    applyfun = NULL, cores = NULL,
                    control = partykit::ctree_control(teststat = "quad", testtype = "Univ",
                                                      minsplit = max(ceiling(sqrt(nrow(data))), 20),
                                                      minbucket = max(ceiling(sqrt(nrow(data))), 7),
                                                      minprob = 0.01,
                                                      mincriterion = 0, saveinfo = FALSE)){

  #requireNamespace("inum")

  Call <- match.call()
  Call[[1]] <- as.name('ltrccif')  #make nicer printout for the user
  # create a copy of the call that has only the arguments we want,
  #  and use it to call model.frame()
  indx <- match(c('formula', 'data', 'id'),
                names(Call), nomatch = 0L)
  if (indx[1] == 0) stop("a formula argument is required")
  Call$formula <- eval(formula)

  temp <- Call[c(1, indx)]
  temp[[1L]] <- quote(stats::model.frame)

  mf <- eval.parent(temp)
  y <- model.extract(mf, 'response')
  if (!is.Surv(y)) stop("Response must be a survival object")
  if (!attr(y, "type") == "counting") stop("The Surv object must be of type 'counting'.")
  rm(y)

  # pull y-variable names
  yvar.names <- all.vars(formula(paste(as.character(formula)[2], "~ .")), max.names = 1e7)
  yvar.names <- yvar.names[-length(yvar.names)]

  if (length(yvar.names) == 4){
    yvar.names = yvar.names[2:4]
  }

  Status <- data[, yvar.names[3]]
  # Times <- data[, yvar.names[2]]
  if (sum(Status) == 0) stop("All observations are right-censored with event = 0!")

  n <- nrow(data)

  ## if not specified, the first one will be used as default
  bootstrap <- match.arg(bootstrap)
  samptype <- match.arg(samptype)

  ## The following code to define id does not work since it could not handle missing values
  # id <- model.extract(mf, 'id')

  # this is a must, otherwise id cannot be passed to the next level in tune.ltrccif
  if (indx[3] == 0){
    ## If id is not present, then we add one more variable
    # mf$id <- 1:nrow(mf) ## Relabel
    data$id <- 1:n
  } else {
    ## If id is present, then we rename the column to be id
    # names(mf)[names(mf) == "(id)"] <- "id"
    names(data)[names(data) == deparse(substitute(id))] <- "id"
  }

  # extract the x-variable names
  xvar.names <- attr(terms(formula), 'term.labels')
  rm(temp)
  data <- data[, c("id", yvar.names, xvar.names)]

  ## bootstrap case
  if (length(data$id) == length(unique(data$id))){ # time-invariant LTRC data
    # it includes the case 1) when id = NULL, which is that id is not specified
    #                      2) when id is specified, but indeed LTRC time-invariant
    if (bootstrap == "by.sub") bootstrap <- "by.root"
  } else { # time-varying subject data
    id.sub <- unique(data$id)
    ## number of subjects
    n.sub <- length(id.sub)
  }

  if (samptype == "swor"){
    perturb = list(replace = FALSE, fraction = sampfrac)
  } else if (samptype == "swr"){
    perturb = list(replace = TRUE)
  } else {
    stop("samptype must set to be either 'swor' or 'swr'\n")
  }

  if (bootstrap == "by.sub"){
    size <- n.sub
    if (!perturb$replace) size <- floor(n.sub * perturb$fraction)
    samp <- replicate(ntree,
                      sample(id.sub, size = size,
                             replace = perturb$replace),
                      simplify = FALSE) # a list of length ntree
    samp <- lapply(samp, function(y) unlist(sapply(y, function(x) which(data$id %in% x), simplify = FALSE)))
    samp <- sapply(samp, function(x) as.integer(tabulate(x, nbins = n))) # n x ntree
  } else if (bootstrap == "none"){
    samp <- matrix(1, nrow = n, ncol = ntree)
  } else if (bootstrap == "by.user") {
    if (is.null(samp)) {
      stop("samp must not be NULL when bootstrapping by user\n")
    }
    if (is.matrix(samp)){
      if (!is.matrix(samp)) stop("samp must be a matrx\n")
      if (any(!is.finite(samp))) stop("samp must be finite\n")
      if (any(samp < 0)) stop("samp must be non-negative\n")
      if (all(dim(samp) != c(n, ntree))) stop("dimension of samp must be n x ntree\n")
      samp <- as.matrix(samp)  # transform into matrix
    }
  } else if (bootstrap == "by.root"){
    samp <- rep(1, n)
  } else {
    stop("Wrong bootstrap is given!\n ")
  }

  if (is.null(mtry)){
    mtry <- tune.ltrccif(formula = formula, data = data, id = id,
                         control = control, ntreeTry = ntree,
                         bootstrap = "by.user",
                         samptype = samptype,
                         sampfrac = sampfrac,
                         samp = samp,
                         na.action = na.action,
                         stepFactor = stepFactor,
                         applyfun = applyfun,
                         cores = cores,
                         trace = trace)
    print(sprintf("mtry is tuned to be %1.0f", mtry))
  }

  h2 <- function(y, x, start = NULL, weights, offset, estfun = TRUE, object = FALSE, ...) {
    if (all(is.na(weights)) == 1) weights <- rep(1, NROW(y))
    s <- .logrank_trafo2(y[weights > 0, , drop = FALSE])
    r <- rep(0, length(weights))
    r[weights > 0] <- s
    list(estfun = matrix(as.double(r), ncol = 1), converged = TRUE)
  }

  ret <- partykit::cforest(formula, data,
                           weights = samp,
                           perturb = perturb,
                           ytrafo = h2,
                           control = control,
                           na.action = na.action,
                           mtry = mtry,
                           ntree = ntree,
                           applyfun = applyfun,
                           cores = cores)
  ret$formulaLTRC <- formula
  ret$info$call <- Call
  ret$info$bootstrap <- bootstrap
  ret$info$samptype <- samptype
  ret$info$sampfrac <- sampfrac
  if (na.action == "na.omit"){
    ret$data$id <- data$id[complete.cases(data) == 1]
  } else {
    ret$data$id <- data$id
  }
  class(ret) <- "ltrccif"
  ret
}

