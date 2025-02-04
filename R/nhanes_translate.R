transform_translation_with_range = function(tabletrans) {
  # do you have range of values in the value description?
  if (any(grepl("Range", tabletrans$Value.Description))) {
    # grab the range and missing vars
    range_vars = grepl("Range", tabletrans$Value.Description)
    missing_vars = grepl("Missing", tabletrans$Value.Description)
    
    # this is missing and non-range variables
    tt = tabletrans[!range_vars,]
    # if the table is *just* range variables (or missing), skip
    if (!all(range_vars | missing_vars)) {
      # grab the values
      ranges = tabletrans$Code.or.Value[range_vars]
      ranges = trimws(ranges)
      ranges = gsub("\\s+", " ", ranges)
      # split 1 to 6 to 1 2 3 4 5 6
      ranges = strsplit(ranges, " to ")
      ranges = lapply(ranges, function(x) {
        if (length(x) != 2) {
          # warning
          return(NULL)
        }
        x = as.numeric(x)
        x = seq(x[1], x[2], by = 1)
        data.frame(
          Code.or.Value = as.character(x),
          Value.Description = as.character(x)
        )
      })
      any_null = any(sapply(ranges, is.null))
      if (!any_null) {
        ranges = do.call("rbind", ranges)
        tabletrans = rbind(ranges, tt)
      }
    }
  }
  tabletrans
}

# FUNCTION nhanesTranslate
#
#------------------------------------------------------------------------------
#' Display code translation information.
#' 
#' Returns code translations for categorical variables, 
#' which appear in most NHANES tables.
#' 
#' @importFrom stringr str_c str_locate str_sub 
#' @importFrom rvest html_elements html_table
#' @importFrom xml2 read_html
#' @importFrom plyr mapvalues
#' @param nh_table The name of the NHANES table to retrieve.
#' @param colnames The names of the columns to translate.
#' @param data If a data frame is passed, then code translation will be applied directly to the data frame. \cr
#' In that case the return argument is the code-translated data frame.
#' @param nchar Applies only when data is defined. Code translations can be very long. \cr
#' Truncate the length by setting nchar (default = 32).
#' @param mincategories The minimum number of categories needed for code translations to be applied to the data (default=2).
#' @param details If TRUE then all available table translation information is displayed (default=FALSE).
#' @param dxa If TRUE then the 2005-2006 DXA translation table will be used (default=FALSE).
#' @return The code translation table (or translated data frame when data is defined). Returns NULL upon error.
#' @details Most NHANES data tables have encoded values. E.g. 1 = 'Male', 2 = 'Female'.
#' Thus it is often helpful to view the code translations and perhaps insert the translated values
#' in a data frame. Only a single table may be specified, but multiple variables within that table
#' can be selected. Code translations are retrieved for each variable. 
#' @examples
#' \donttest{nhanesTranslate('DEMO_B', c('DMDBORN','DMDCITZN'))}
#' \donttest{nhanesTranslate('BPX_F', 'BPACSZ', details=TRUE)}
#' \donttest{nhanesTranslate('BPX_F', 'BPACSZ', data=nhanes('BPX_F'))}
#' @export
#' 
nhanesTranslate <- function(nh_table, colnames=NULL, data = NULL, nchar = 32, 
                            mincategories = 2, details=FALSE, dxa=FALSE) {
  if(is.null(colnames)) {
    message('Column name is required')
    return(NULL)
  }
  
  if(!is.null(data) & details == TRUE) {
    details = FALSE
    warning("When a data table is passed to nhanesTranslate, the details variable is ignored")
  }
  
  get_translation_table <- function(colname, hurl, details) {
    xpt <- str_c('//*[h3[a[@name="', colname, '"]]]', sep='')
    
    tabletree <- hurl %>% html_elements(xpath=xpt)
    #    tabletree <- url %>% read_html() %>% html_elements(xpath=xpt)
    if(length(tabletree)==0) { # If not found then try 'id' instead of 'name'
      xpt <- str_c('//*[h3[@id="', colname, '"]]', sep='')
      
      tabletree <- hurl %>% html_elements(xpath=xpt)
      #      tabletree <- url %>% read_html() %>% html_elements(xpath=xpt)
    }
    if(length(tabletree)>0) {
      tabletrans <- as.data.frame(html_elements(tabletree, 'table') %>% html_table())
    } else { # Code table not found so let's see if last letter should be lowercase
      nc <- nchar(colname)
      if(length(grep("[[:upper:]]", stringr::str_sub(colname, start=nc, end=nc)))>0){
        lcnm <- colname
        stringr::str_sub(lcnm, start=nc, end=nc) <- tolower(stringr::str_sub(lcnm, start=nc, end=nc))
        xpt <- str_c('//*[h3[a[@name="', lcnm, '"]]]', sep='')
        
        tabletree <- hurl %>% html_elements(xpath=xpt)
        
        if(length(tabletree)==0) { # If not found then try 'id' instead of 'name'
          xpt <- str_c('//*[h3[@id="', lcnm, '"]]', sep='')
          
          tabletree <- hurl %>% html_elements(xpath=xpt)
          #          tabletree <- url %>% read_html() %>% html_elements(xpath=xpt)
        }
        
        if(length(tabletree)>0) {
          tabletrans <- as.data.frame(html_elements(tabletree, 'table') %>% html_table())
        } else { # Still not found even after converting to lowercase
          warning(c('Column "', colname, '" not found'), collapse='')
          return(NULL)
        }
      } else { #Last character is not an uppercase letter, thus can't convert to lowercase
        warning(c('Column "', colname, '" not found'), collapse='')
        return(NULL)
      }
    }
    
    if(length(tabletrans) > 0) {
      if(details == FALSE) {
        tabletrans <- tabletrans[,c('Code.or.Value', 'Value.Description')]
      }
      return(tabletrans)
    } else { 
      if(!(colname=='SEQN')) {
        message(paste(c('No translation table is available for ', colname), collapse=''))
      }
      return(NULL)
    }
  }
  
  if(dxa) {
    code_translation_url <- "https://wwwn.cdc.gov/nchs/data/nhanes/dxa/dxx_d.htm"
  } else {
    nh_year <- .get_year_from_nh_table(nh_table)
    if(is.null(nh_year)) {
      return(NULL)
    }
    if(nh_year == "Nnyfs"){
      code_translation_url <- str_c("https://wwwn.cdc.gov/Nchs/", nh_year, '/', nh_table, '.htm', sep='')
    } else {
      code_translation_url <- str_c(nhanesURL, nh_year, '/', nh_table, '.htm', sep='')
    }
  }
  hurl <- .checkHtml(code_translation_url)
  translations <- lapply(colnames, get_translation_table, hurl, details)
  names(translations) <- colnames
  
  #nchar_max <- 128
  if(nchar > nchar_max) {
    nchar <- nchar_max
  }
  
  translations <- lapply(translations, transform_translation_with_range)
  if(is.null(data)) { ## If no data to translate then just return the translation table
    return(Filter(Negate(function(x) is.null(unlist(x))), translations))
  } else {
    #    message("Need to decide what to do when data are passed in")
    translations <- Filter(Negate(function(x) is.null(unlist(x))), translations)
    colnames     <- as.list(names(translations))
    
    translated <- c() ## Let's keep track of columns that were translated
    notfound   <- c() ## Keep track of columns that were not found
    nskip <- grep('Range', translations) ## 'Range' of values indicates the column is not coded
    for( i in 1:length(colnames) ) {
      if(!(i %in% nskip)) {
        cname <- unlist(colnames[i])
        sstr <- str_c('^', cname, '$') # Construct the search string
        idx <- grep(sstr, names(data)) 
        if(length(idx)>0) { ## The column is present. Next we need to decide if it should be translated.
          if(length(levels(as.factor(data[[idx]]))) >= mincategories) {
            # If we reached this point then yes we are translating
            # Check for SAS label attribute
            idx_label <- attr(data[[idx]],"label")
            data[[idx]] <- as.factor(data[[idx]])
            data[[idx]] <- suppressMessages(plyr::mapvalues(data[[idx]], from = translations[[cname]][['Code.or.Value']], 
                                                            to = str_sub(translations[[cname]][['Value.Description']], 1, nchar)))
            if(!is.null(idx_label)) {
              attr(data[[idx]],"label") <- idx_label
            }
            translated <- c(translated, cname) }
        } else {
          notfound <- c(notfound, cname)
        }
      }
    }
    
    if(length(translated) > 0) {
      message(paste(c("Translated columns:", translated), collapse = ' '))
      if(length(notfound) > 0)
        message(paste(c("Columns not found:", notfound), collapse = ' '))
    } else {
      warning("No columns were translated")
    }
    return(data)
  }
}

