% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/moduleCoverage.R
\docType{methods}
\name{moduleCoverage}
\alias{moduleCoverage}
\alias{moduleCoverage,character,character-method}
\alias{moduleCoverage,character,missing-method}
\title{Calculate module coverage of unit tests}
\usage{
moduleCoverage(name, path)

\S4method{moduleCoverage}{character,character}(name, path)

\S4method{moduleCoverage}{character,missing}(name)
}
\arguments{
\item{name}{Character string. The module's name.}

\item{path}{Character string. The path to the module directory
(default is the current working directory).}
}
\value{
Return a list of two coverage objects and two data.table objects.
The two coverage objects are named `moduleCoverage` and `functionCoverage`.
The `moduleCoverage` object contains the percent value of unit test coverage
for the module.
The `functionCoverage` object contains percentage values for unit test
coverage for each function defined in the module.
Please use \code{\link[covr]{report}} to view the coverage information.
Two data.tables give the information of all the tested and untested functions
in the module.
}
\description{
Calculate the test coverage by unit tests for the module and its functions.
}
\note{
When running this function, the test files must be strictly placed in
the \file{tests/testthat/} directory under module path.
To automatically generate this folder, please set \code{unitTests = TRUE}
when creating a new module using \code{\link{newModule}}.
To accurately test your module, the test filename must follow the format
\code{test-functionName.R}.
}
\examples{
\dontrun{
 library(igraph) # for \%>\%
 library(SpaDES.core)
 tmpdir <- file.path(tempdir(), "coverage")
 modulePath <- file.path(tmpdir, "Modules") \%>\% checkPath(create = TRUE)
 moduleName <- "forestAge" # sample module to test
 downloadModule(name = moduleName, path = modulePath) # download sample module
 testResults <- moduleCoverage(name = moduleName, path = modulePath)
 report(testResults$moduleCoverage)
 report(testResults$functionCoverage)
 unlink(tmpdir, recursive = TRUE)
}
}
\seealso{
\code{\link{newModule}}.
}
\author{
Yong Luo
}
