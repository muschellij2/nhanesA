#nhanesA - retrieve data from the CDC NHANES repository
# Christopher J. Endres 06/25/2023
# FUNCTIONS:
#   nhanes
#   nhanesDXA
#   nhanesAttr
#   browseNHANES

#------------------------------------------------------------------------------
#' Download an NHANES table and return as a data frame.
#' 
#' Use to download NHANES data tables that are in SAS format.
#' 
#' @importFrom foreign read.xport lookup.xport
#' @importFrom stringr str_c
#' @param nh_table The name of the specific table to retrieve.
#' @param includelabels If TRUE, then include SAS labels as variable attribute (default = FALSE).
#' @return The table is returned as a data frame.
#' @details Downloads a table from the NHANES website as is, i.e. in its entirety
#' with no modification or cleansing. NHANES tables 
#' are stored in SAS '.XPT' format but are imported as a data frame.
#' Function nhanes cannot be used to import limited 
#' access data.
#' @examples 
#' \donttest{nhanes('BPX_E')}
#' \donttest{nhanes('FOLATE_F', includelabels = TRUE)}
#' @export
#' 
nhanes <- function(nh_table, includelabels = FALSE) {
  nht <- tryCatch({    
    nh_year <- .get_year_from_nh_table(nh_table)
    
    if(length(grep('^Y_', nh_table)) > 0) {
      url <- str_c('https://wwwn.cdc.gov/Nchs/', nh_year, '/', nh_table, '.XPT', collapse='')
    } else {
      url <- str_c(nhanesURL, nh_year, '/', nh_table, '.XPT', collapse='')
    }
    
    tf <- tempfile()
    download.file(url, tf, mode = "wb", quiet = TRUE)
    
    if(includelabels) {
      xport_struct <- lookup.xport(tf)
      column_names  <- xport_struct[[1]]$name
      column_labels <- xport_struct[[1]]$label
      names(column_labels) <- column_names
      nh_df <- read.xport(tf)
      
      # Ideal case where rows and labels are identical
      if(identical(names(nh_df), column_names)) {
        for( name in column_names) {
          attr(nh_df[[name]],"label") = column_labels[which(names(column_labels)==name)]
        }
      } else {
        message(paste0("Column names and labels are not consistent for table ", nh_table, ". No labels added"))
      }
      
      return(nh_df)
    } else {
      return(read.xport(tf))
    }
  },
  error = function(cond) {
    message(paste("Data set ", nh_table,  " is not available"), collapse='')
    #    message(url)
    return(NULL)
  },
  warning = function(cond) {
    message(cond, '\n')    
  }  
  )
  return(nht)
}

## #------------------------------------------------------------------------------
#' Import Dual Energy X-ray Absorptiometry (DXA) data.
#' 
#' DXA data were acquired from 1999-2006. 
#' 
#' @importFrom stringr str_c
#' @importFrom foreign read.xport
#' @importFrom utils download.file
#' @param year The year of the data to import, where 1999<=year<=2006. 
#' @param suppl If TRUE then retrieve the supplemental data (default=FALSE).
#' @param destfile The name of a destination file. If NULL then the data are imported 
#' into the R environment but no file is created.
#' @return By default the table is returned as a data frame. When downloading to file, the return argument
#' is the integer code from download.file where 0 means success and non-zero indicates failure to download.
#' @details  Provide destfile in order to write the data to file. If destfile is not provided then
#' the data will be imported into the R environment.
#' @examples
#' \donttest{dxa_b <- nhanesDXA(2001)}
#' \donttest{dxa_c_s <- nhanesDXA(2003, suppl=TRUE)}
#' \dontrun{nhanesDXA(1999, destfile="dxx.xpt")}
#' @export
nhanesDXA <- function(year, suppl=FALSE, destfile=NULL) {

  dxa_fname <- function(year, suppl) {
    if(year == 1999 | year == 2000) {fname = 'dxx'}
    else if(year == 2001 | year == 2002) {fname = 'dxx_b'}
    else if(year == 2003 | year == 2004) {fname = 'dxx_c'}
    else if(year == 2005 | year == 2006) {fname = 'DXX_D'}
    if(suppl == TRUE) {
      if(year == 2005 | year == 2006) {
        fname <- str_c(fname, '_S', collapse='')
      } else {fname <- str_c(fname, '_s', collapse='')}
    }
    return(fname)
  }
  
  if(year) {
    if(!(as.character(year) %in% c('1999', '2000', '2001', '2002', '2003', '2004', '2005', '2006'))) {
      stop("Invalid survey year for DXA data")
    } else {
      fname <- dxa_fname(year, suppl)
      url <- stringr::str_c(dxaURL, fname, '.xpt', collapse='')
      if(!is.null(destfile)) {
        ok <- suppressWarnings(tryCatch({download.file(url, destfile, mode="wb", quiet=TRUE)},
                                        error=function(cond){message(cond); return(NULL)}))         
        return(ok)
      } else {
        tf <- tempfile()
        ok <- suppressWarnings(tryCatch({download.file(url, tf, mode="wb", quiet=TRUE)},
                                        error=function(cond){message(cond); return(NULL)}))
        if(!is.null(ok)) {
          return(read.xport(tf))
        } else { return(NULL) }
      }
    }
  } else { # Year not provided - no data will be returned
    stop("Year is required")
  }
}

#------------------------------------------------------------------------------
#' Returns the attributes of an NHANES data table.
#' 
#' Returns attributes such as number of rows, columns, and memory size,
#' but does not return the table itself.
#' 
#' @importFrom foreign read.xport
#' @importFrom stringr str_c
#' @importFrom utils object.size
#' @param nh_table The name of the specific table to retrieve
#' @return The following attributes are returned as a list \cr
#' nrow = number of rows \cr
#' ncol = number of columns \cr
#' names = name of each column \cr
#' unique = true if all SEQN values are unique \cr
#' na = number of 'NA' cells in the table \cr
#' size = total size of table in bytes \cr
#' types = data types of each column
#' @details nhanesAttr allows one to check the size and other charactersistics of a data table 
#' before importing into R. To retrieve these characteristics, the specified table is downloaded,
#' characteristics are determined, then the table is deleted.
#' @examples 
#' nhanesAttr('BPX_E')
#' nhanesAttr('FOLATE_F')
#' @export
#' 
nhanesAttr <- function(nh_table) {
  nht <- tryCatch({    
    nh_year <- .get_year_from_nh_table(nh_table)
    url <- str_c(nhanesURL, nh_year, '/', nh_table, '.XPT', collapse='')
    tmp <- read.xport(url)
    nhtatt <- attributes(tmp)
    nhtatt$row.names <- NULL
    nhtatt$nrow <- nrow(tmp)
    nhtatt$ncol <- ncol(tmp)
    nhtatt$unique <- (length(unique(tmp$SEQN)) == nhtatt$nrow)
    nhtatt$na <- sum(is.na(tmp))
    nhtatt$size <- object.size(tmp)
    nhtatt$types <- sapply(tmp,class)
    rm(tmp)
    return(nhtatt)
  },
  error = function(cond) {
    message(paste("Data from ", nh_table, " are not available"))
    return(NA)
  },
  warning = function(cond) {
    message(cond, '\n')    
  }  
  )
  return(nht)  
}

#------------------------------------------------------------------------------
#' Open a browser to NHANES.
#' 
#' The browser may be directed to a specific year, survey, or table.
#' 
#' @importFrom stringr str_c str_to_title str_split str_sub str_extract_all
#' @importFrom utils browseURL
#' @param year The year in yyyy format where 1999 <= yyyy.
#' @param data_group The type of survey (DEMOGRAPHICS, DIETARY, EXAMINATION, LABORATORY, QUESTIONNAIRE).
#' Abbreviated terms may also be used: (DEMO, DIET, EXAM, LAB, Q).
#' @param nh_table The name of an NHANES table.
#' @return No return value
#' @details browseNHANES will open a web browser to the specified NHANES site.
#' @examples
#' browseNHANES()                     # Defaults to the main data sets page
#' browseNHANES(2005)                 # The main page for the specified survey year
#' browseNHANES(2009, 'EXAM')         # Page for the specified year and survey group
#' browseNHANES(nh_table = 'VIX_D')   # Page for a specific table
#' browseNHANES(nh_table = 'DXA')     # DXA main page
#' @export
#' 

browseNHANES <- function(year=NULL, data_group=NULL, nh_table=NULL) {
  if(!is.null(nh_table)){ # Specific table name was given
    if('DXA'==toupper(nh_table)) { # Special case for DXA
      browseURL("https://wwwn.cdc.gov/nchs/nhanes/dxa/dxa.aspx")
    } else {
      nh_year <- .get_year_from_nh_table(nh_table)
      url <- str_c(nhanesURL, nh_year, '/', nh_table, '.htm', sep='')
      browseURL(url)
    }
  } else if(!is.null(year)) {
    if(!is.null(data_group)) {
      nh_year <- .get_nh_survey_years(year)
      url <- str_c(nhanesURL, 'Search/DataPage.aspx?Component=', 
                   str_to_title(as.character(nhanes_group[data_group])), 
                   '&CycleBeginYear=', unlist(str_split(as.character(nh_year), '-'))[[1]] , sep='')
      browseURL(url)
    } else { # Go to the two year survey page 
      nh_year <- .get_nh_survey_years(year)
#      nh_year <- str_c(str_sub(unlist(str_extract_all(nh_year,"[[:digit:]]{4}")),3,4),collapse='_')
      nh_year <- unlist(str_extract_all(nh_year,"[[:digit:]]{4}"))[1]
      url <- str_c(nhanesURL, 'continuousnhanes/default.aspx?BeginYear=', nh_year, sep='')
      browseURL(url)
    }
  } else {
    browseURL("https://wwwn.cdc.gov/nchs/nhanes/Default.aspx")
  }
}
#------------------------------------------------------------------------------
