if (getRversion() >= "3.1.0") {
  utils::globalVariables(".")
}

################################################################################
#' Determine which modules in a list are unparsed
#'
#' Internal function, used during \code{\link{simInit}}.
#'
#' @param modules A character vector specifying the modules to parse.
#'
#' @return The ids of the unparsed list elements.
#'
#' @author Alex Chubaty
#' @keywords internal
#' @rdname unparsed
#'
setGeneric(".unparsed",
           function(modules) {
             standardGeneric(".unparsed")
})

#' @rdname unparsed
setMethod(
  ".unparsed",
  signature(modules = "list"),
  definition = function(modules) {
    ids <- lapply(modules, function(x) {
      (attr(x, "parsed") == FALSE)
    }) %>% `==`(., TRUE) %>% which()
    return(ids)
})

################################################################################
#' @return \code{.parseModulePartial} extracts just the individual element
#' requested from the module. This can be useful if parsing the whole module
#' would cause an error.
#'
#' @param filename The filename of the module to be parsed.
#'
#' @inheritParams spades
#'
#' @param defineModuleElement Character string indicating which of the list
#'                            elements in defineModule should be extracted
#' @param envir Optional environment in which to store parsed code. This may be
#'              useful if the same file is being parsed multiple times. This
#'              function will check in that envir for the parsed file before
#'              parsing again. If the \code{envir} is transient, then this will
#'              have no effect.
#'
#' @author Eliot McIntire
#' @export
#' @include module-dependencies-class.R
#' @include simList-class.R
#' @include environment.R
#' @rdname parseModule
#'
setGeneric(".parseModulePartial",
           function(sim, modules, filename, defineModuleElement, envir = NULL) {
             standardGeneric(".parseModulePartial")
})

#' @rdname parseModule
setMethod(
  ".parseModulePartial",
  signature(
    sim = "missing",
    modules = "missing",
    filename = "character",
    defineModuleElement = "character",
    envir = "ANY"
  ),
  definition = function(filename, defineModuleElement, envir) {

    if (file.exists(filename)) {
      # parse file, conditioned on it not already been done
      tmp <- .parseConditional(envir = envir, filename = filename)
      namesParsedList <- names(tmp[["parsedFile"]][tmp[["defineModuleItem"]]][[1]][[3]])

      element <- (namesParsedList == defineModuleElement)
      if (any(element)) {
        out <- tmp[["pf"]][[1]][[3]][element][[1]]
      } else {
        out <- list()
      }
      out <- tryCatch(
        eval(out),
        error = function(x) out
      )
    } else {
      out <- NULL
    }
    return(out)
})

#' @rdname parseModule
setMethod(
  ".parseModulePartial",
  signature(
    sim = "simList",
    modules = "list",
    filename = "missing",
    defineModuleElement = "character",
    envir = "ANY"
  ),
  definition = function(sim, modules, defineModuleElement, envir = NULL) {
    out <- list()

    simMods <- modules(sim)

    for (j in seq_along(modules)) {
      m <- modules[[j]][1]
      mBase <- basename(m)

      whModule <- simMods %in% m
      filePath <- names(simMods)[whModule]

      # the module may not have absolute path, i.e., including the correct modulePath
      #  Check first if it is there for speed, then if not, try file.exists (slow)
      filename <- if (length(filePath) == 0) {
        # the module may not have absolute path, i.e., including the correct modulePath
        #  Check first if it is there for speed, then if not, try file.exists (slow)
        file.path(m, paste0(mBase, ".R"))
      } else {
        file.path(filePath, paste0(mBase, ".R"))
      }
      if (length(sim@paths$modulePath) > 1) {
        hasFullModulePath <- unlist(lapply(sim@paths$modulePath,
                                           function(mp) startsWith(prefix = mp, m)))
        if (!isTRUE(any(hasFullModulePath))) {
          possFiles <- file.path(modulePath(sim), mBase, paste(mBase, ".R", sep = ""))
          ids <- which(file.exists(possFiles))
          filename <- possFiles[ids[1]] # override filename if it wasn't already there
        }
      }
      out[[m]] <- .parseModulePartial(filename = filename,
                                      defineModuleElement = defineModuleElement,
                                      envir = envir)
    }
    return(out)
})

#' Parse and initialize a module
#'
#' Internal function, used during \code{\link{simInit}}.
#'
#' @param sim     A \code{simList} simulation object.
#'
#' @param modules A list of modules with a logical attribute "parsed".
#'
#' @param userSuppliedObjNames Character string (or \code{NULL}, the default)
#'                             indicating the names of objects that user has passed
#'                             into simInit via objects or inputs.
#'                             If all module inputObject dependencies are provided by user,
#'                             then the \code{.inputObjects} code will be skipped.
#'
#' @param notOlderThan Passed to \code{Cache} that may be used for .inputObjects function call.
#' @inheritParams .parseModulePartial
#'
#' @param ... All \code{simInit} parameters.
#'
#' @return A \code{simList} simulation object.
#'
#' @author Alex Chubaty and Eliot McIntire
#' @keywords internal
#' @importFrom reproducible Cache
#' @importFrom codetools findGlobals checkUsageEnv
#' @include environment.R
#' @include module-dependencies-class.R
#' @include simList-class.R
#' @rdname parseModule
#'
setGeneric(".parseModule",
           function(sim, modules, userSuppliedObjNames = NULL, envir = NULL,
                    notOlderThan, ...) {
             standardGeneric(".parseModule")
})

#' @rdname parseModule
setMethod(
  ".parseModule",
  signature(sim = "simList", modules = "list", envir = "ANY"),
  definition = function(sim, modules, userSuppliedObjNames, envir, notOlderThan, ...) {
    all_children <- list()
    codeCheckMsgs <- character()
    children <- list()
    parent_ids <- integer()
    dots <- list(...)
    if (!is.null(dots[["objects"]])) objs <- dots[["objects"]]

    for (j in .unparsed(modules)) {
      m <- names(modules)[[j]][1]
      mBase <- basename(m)

      ## temporarily assign current module
      sim@current <- list(
        eventTime = start(sim),
        moduleName = mBase,
        eventType = ".inputObjects",
        eventPriority = .normal()
      )

      prevNamedModules <- if (!is.null(unlist(sim@depends@dependencies))) {
        unlist(lapply(sim@depends@dependencies, function(x) slot(x, "name")))
      } else {
        NULL
      }

      # This is about duplicate named modules
      if (!(mBase %in% prevNamedModules)) {
        #if (length(sim@paths[["modulePath"]]) > 1) {
        #  for (pathPoss in sim@paths[["modulePath"]]) {
        filename <- paste(m, "/", mBase, ".R", sep = "")

        tmp <- .parseConditional(envir = envir, filename = filename)

        # duplicate -- put in namespaces location
        # If caching is being used, it is possible that exists
        if (!is.null(sim@.xData[[mBase]])) {
          rm(list = mBase, envir = sim@.xData)
        }

        #sim@.xData[[mBase]] <- new.env(parent = sim@.xData)
        sim@.xData[[mBase]] <- new.env(parent = asNamespace("SpaDES.core"))
        attr(sim@.xData[[mBase]], "name") <- mBase

        # load all code into simList@.xData[[moduleName]]
        # The simpler line commented below will not allow actual code to be put into module,
        #  e.g., startSim <- start(sim)
        #  The more complex one following will allow that.
        # eval(tmp[["parsedFile"]][!tmp[["defineModuleItem"]]], envir = sim@.xData[[mBase]])
        activeCode <- list()
        activeCode[["main"]] <- evalWithActiveCode(tmp[["parsedFile"]][!tmp[["defineModuleItem"]]],
                                                   sim@.xData[[mBase]])

        doesntUseNamespacing <- !.isNamespaced(sim, mBase)

        # evaluate the rest of the parsed file
        if (doesntUseNamespacing) {
          #lockBinding(mBase, sim@.envir) ## guard against clobbering from module code (#80)
          eval(tmp[["parsedFile"]][!tmp[["defineModuleItem"]]], envir = sim@.xData)
          #unlockBinding(mBase, sim@.envir) ## will be re-locked later on
        }

        # attach source code to simList in a hidden spot
        opt <- getOption("spades.moduleCodeChecks")

        if (isTRUE(opt) || length(names(opt)) > 1)
          list2env(list(._parsedData = tmp[["._parsedData"]]), sim@.xData[[mBase]])
        sim@.xData[[mBase]][["._sourceFilename"]] <- grep(paste0(mBase,".R"), ls(sim@.xData[[".parsedFiles"]]), value = TRUE)

        # parse any scripts in R subfolder
        RSubFolder <- file.path(dirname(filename), "R")
        RScript <- dir(RSubFolder, pattern = "([.]R$|[.]r$)") ## only R files
        if (length(RScript) > 0) {
          for (Rfiles in RScript) {
            parsedFile1 <- parse(file.path(RSubFolder, Rfiles))
            if (doesntUseNamespacing) {
              #eval(parsedFile1, envir = sim@.xData)
              evalWithActiveCode(parsedFile1, sim@.xData)
            }

            # duplicate -- put in namespaces location
            #eval(parsedFile1, envir = sim@.xData[[mBase]])
            activeCode[[Rfiles]] <- evalWithActiveCode(parsedFile1, sim@.xData[[mBase]])
          }
        }

        # evaluate all but inputObjects and outputObjects part of 'defineModule'
        #  This allow user to use params(sim) in their inputObjects
        namesParsedList <- names(tmp[["parsedFile"]][tmp[["defineModuleItem"]]][[1]][[3]])
        inObjs <- (namesParsedList == "inputObjects")
        outObjs <- (namesParsedList == "outputObjects")
        pf <- tmp$pf # tmp[["parsedFile"]][tmp[["defineModuleItem"]]]

        # because it is parsed, there is an expression (the [[1]]),
        # then a function with defineModule, sim, and then the list (the [[3]])
        pf[[1]][[3]] <- pf[[1]][[3]][!(inObjs | outObjs)]

        # allows active code e.g., `startSim <- start(sim)` to be parsed, then useable
        #  inside of the defineModule.
        #  First, load anything that is active code into an environment whose parent
        #  is here (and thus has access to sim), then move the depends (only) back to main sim
        env <- new.env(parent = parent.frame())
        if (any(unlist(activeCode)))  {
            list2env(as.list(sim@.xData[[mBase]]), env)
        }

        # Evaluate defineModule into the sim environment
        # Capture messages which will be about defineParameter at the moment
        on.exit({
          if (!exists("finishedClean"))
            try(mess)
        })

        mess <- capture.output(type = "message",
                               out <- try(suppressWarnings(eval(pf, envir = env))))
        if (is(out, "try-error")) stop(out)
        opt <- getOption("spades.moduleCodeChecks")
        if (length(mess) && (isTRUE(opt) || length(names(opt)) > 1)) {
          messFile <- capture.output(type = "message",
                                               message(grep(paste0(mBase, ".R"),
                                                            ls(sim@.xData$.parsedFiles), value = TRUE)))
          codeCheckMsgs <- c(
            codeCheckMsgs,
            messFile,
            capture.output(type = "message",
                           hasMessage <- unique(unlist(lapply(mess, function(x)
                             .parseMessage(mBase, "", x))))))
        }

        for (dep in out@depends@dependencies) {
          sim <- .addDepends(sim, dep)
        }

        # check that modulename == filename
        k <- length(sim@depends@dependencies)

        if (sim@depends@dependencies[[k]]@name == mBase) {
          i <- k
        } else {
          stop("Module name metadata (", sim@depends@dependencies[[k]]@name, ") ",
               "does not match filename (", mBase, ".R).")
        }

        # assign default param values
        deps <- sim@depends@dependencies[[i]]@parameters
        sim@params[[mBase]] <- list()
        if (NROW(deps) > 0) {
          for (x in 1:NROW(deps)) {
            sim@params[[mBase]][[deps$paramName[x]]] <- deps$default[[x]]
          }
        }
        # override immediately with user supplied values
        pars <- list(...)[["params"]]
        if (!is.null(pars[[mBase]])) {
          if (length(pars[[mBase]]) > 0) {
            sim@params[[mBase]][names(pars[[mBase]])] <- pars[[mBase]]
          }
        }

        # do inputObjects and outputObjects
        pf <- tmp$pf # tmp[["parsedFile"]][tmp[["defineModuleItem"]]]
        if (any(inObjs)) {
          sim@depends@dependencies[[i]]@inputObjects <- data.frame(
            rbindlist(fill = TRUE,
                      list(sim@depends@dependencies[[i]]@inputObjects,
                           eval(pf[[1]][[3]][inObjs][[1]]))
            )
          )
        }

        if (any(outObjs)) {
          sim@depends@dependencies[[i]]@outputObjects <- data.frame(
            rbindlist(fill = TRUE,
                      list(sim@depends@dependencies[[i]]@outputObjects,
                           eval(pf[[1]][[3]][outObjs][[1]]))
            )
          )
        }

        # add child modules to list of all child modules, to be parsed later
        children <- as.list(sim@depends@dependencies[[i]]@childModules) %>%
          lapply(., `attributes<-`, list(parsed = FALSE))
        all_children <- append_attr(all_children, children)

        # remove parent module from the list
        if (length(children)) {
          parent_ids <- c(parent_ids, j)
        }

        ## SECTION ON CODE SCANNING FOR POTENTIAL PROBLEMS
        opt <- getOption("spades.moduleCodeChecks")
        if (isTRUE(opt) || length(names(opt)) > 1) {
          # the code will always have magenta colour, which has an mBase
          codeCheckMsgsThisMod <- any(grepl(paste0("m", mBase, ":"), codeCheckMsgs))
          mess <- capture.output(type = "message", .runCodeChecks(sim, mBase, k, codeCheckMsgsThisMod))
          if (length(mess) | length(codeCheckMsgsThisMod) == 0) {
            mess <- c(capture.output(type = "message",
                                     message(grep(paste0(mBase, ".R"),
                                                  ls(sim@.xData$.parsedFiles), value = TRUE))),
                      mess)
          }
          codeCheckMsgs <- c(codeCheckMsgs, mess)
        } ## End of code checking

        lockBinding(mBase, sim@.xData)
        names(sim@depends@dependencies)[[k]] <- mBase
      } else {
        alreadyIn <- names(sim@depends@dependencies) %in% mBase
        if (any(alreadyIn)) {
          children <- as.list(sim@depends@dependencies[[which(alreadyIn)]]@childModules) %>%
            lapply(., `attributes<-`, list(parsed = FALSE))
          all_children <- append_attr(all_children, children)
        }
        # remove parent module from the list
        if (length(children)) {
          parent_ids <- c(parent_ids, which(unlist(modules(sim)) == mBase))
        }

        message("Duplicate module, ", mBase, ", specified. Skipping loading it twice.")
      }

      # update parse status of the module
      attributes(modules[[j]]) <- list(parsed = TRUE)
    }

    modulesAppended <- if (length(parent_ids)) {
      append_attr(modules, all_children)[-parent_ids]
    } else {
      append_attr(modules, all_children)
    }
    dups <- duplicated(modulesAppended)
    modules(sim) <- modulesAppended[!dups] # unique removes names

    #  unique()
    sim@current <- list()

    # Messaging at end -- don't print parent module messages (as there should be nothing)
    #  Also, collapse if all are clean
    if (length(codeCheckMsgs)) {
      if (length(parent_ids) < length(modules)) {
        mess <- if (all(grepl(codeCheckMsgs, pattern = allCleanMessage))) {
          mess <- gsub(codeCheckMsgs,
                       pattern = paste(paste0(unlist(modules), ": "), collapse = "|"),
                       replacement = "")
          unique(mess)

        } else {
          paste(unique(unlist(codeCheckMsgs)), collapse = "\n")
        }
        message("###### Module Code Checking - Still experimental - please report problems ######## ")
        message(mess)
        message("###### Module Code Checking ########")
      }
    }

    finishedClean <- TRUE
    return(sim)
})

#' @importFrom utils getParseData
.parseConditional <- function(envir = NULL, filename = character()) {
  if (!is.null(envir)) {
    if (is.null(envir[[filename]])) {
      envir[[filename]] <- new.env(parent = envir)
      needParse <- TRUE
    } else {
      needParse <- FALSE
    }
    tmp <- envir[[filename]]
  } else {
    tmp <- list()
    needParse <- TRUE
  }

  if (needParse) {
    tmp[["parsedFile"]] <- parse(filename)#, keep.source = getOption("spades.moduleCodeChecks"))
    opt <- getOption("spades.moduleCodeChecks")
    if (isTRUE(opt) || length(names(opt)) > 1) {
      tmp[["._parsedData"]] <- getParseData(tmp[["parsedFile"]], TRUE)
    }
    tmp[["defineModuleItem"]] <- grepl(pattern = "defineModule", tmp[["parsedFile"]])
    tmp[["pf"]] <- tmp[["parsedFile"]][tmp[["defineModuleItem"]]]
  }
  return(tmp)
}

#' @keywords internal
evalWithActiveCode <- function(parsedModuleNoDefineModule, envir, parentFrame = parent.frame()) {
  ll <- lapply(parsedModuleNoDefineModule,
               function(x) tryCatch(eval(x, envir = envir), error = function(y) "ERROR"))
  activeCode <- unlist(lapply(ll, function(x) identical("ERROR", x)))

  if (any(activeCode)) {
    env <- new.env(parent = parentFrame);
    aa <- lapply(parsedModuleNoDefineModule[activeCode], function(ac) {
      eval(ac, envir = env)
    })
    list2env(as.list(env), envir)
  }
  activeCode
}

#' Extract the user-defined \code{.inputObjects} function from a module
#'
#' @keywords internal
#' @rdname getModuleInputObjects
.getModuleInputObjects <- function(sim, m) {
  sim@.xData[[basename(m)]][[".inputObjects"]]
}

#' Check is module uses module namespacing
#'
#' Older modules may not have their functions etc. namespaced in the \code{simList}.
#'
#' @keywords internal
#' @rdname isNamespaced
.isNamespaced <- function(sim, m) {
  !isTRUE(any(grepl(paste0("^", basename(m)), ls(sim@.xData[[basename(m)]]))))
}
