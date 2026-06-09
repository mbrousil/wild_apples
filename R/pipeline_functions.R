
# Photo functions ---------------------------------------------------------

#' Download a single photo from an iNaturalist url
#'
#' Grabs a photo from the iNaturalist url and saves it locally. Intended for
#' dynamic branching within a targets pipeline.
#'
#' @param url Character. URL from inat_photo_matchups that directs to an iNaturalist
#' photo
#'
#' @return File path character string
#'
download_single_photo <- function(url){
  # Confirm storage location
  dir.create("data/photos", showWarnings = FALSE, recursive = TRUE)
  
  # Get photo ID from url
  photo_id <- basename(dirname(url))
  # Extension
  ext <- tools::file_ext(url)
  # Name for photo
  out_file <- file.path("data/photos", paste0(photo_id, ".", ext))
  
  tryCatch({
    utils::download.file(url, destfile = out_file, mode = "wb", quiet = TRUE)
    Sys.sleep(0.1)
  }, error = function(e) {
    warning(paste("Failed to download:", url))
  })
  
  # Return file path for tracking
  out_file
}

#' Run local visual language model on iNaturalist image
#' 
#' Runs a single downloaded image from iNaturalist through a local visual language
#' model (VLM) to check for phenology characteristics. Intended for dynamic 
#' branching within a targets pipeline.
#'
#' @param photo_path Character. The file path to a locally stored image.
#' 
#' @param vlm Character. The vlm (installed locally via Ollama) to use for analysis.
#'
#' @return A data frame with columns has_fruit, has_flower, explanation, and
#' photo_path.
#' @export
run_vlm_analysis <- function(photo_path, vlm = "qwen2.5vl:7b") {
  
  # Initialize chat with instructions
  pheno_chat <- chat_ollama(
    model = vlm,
    params = list(temperature = 0,
                  max_tokens = 512),
    api_args = list(
      options = list(
        num_ctx = 8192 
      )
    ),
    system_prompt = "You are an expert botanical assistant. Analyze the plant material in the image carefully and extract structured data.")
  
  # Define structure of the returned info
  pheno_check <- type_object(
    explanation = type_string(
      description = "Scan the image closely. 1. Identify any branches, leaves, flowers, or fruit that belong to an apple tree (or similar woody plant). Ignore unrelated background vegetation, grass, or ground-level wildflowers. 2. Look carefully for fruit. Note that unripe green apples can be heavily camouflaged against leaves, while mature apples may be red or yellow. 3. Look for open flowers or closed flower buds on the tree branches. WARNING: Apple flower buds are often dark pink or red before opening; do not confuse these with fruit or berries. Describe exactly what you see on the relevant tree or trees."
    ),
    has_fruit = type_boolean(
      description = "TRUE only if actual mature or developing fruit (of any color) are clearly visible on the tree. FALSE if the red/pink objects are just closed flower buds. MUST strictly match your explanation."
    ),
    has_flower = type_boolean(
      description = "TRUE if there are open flowers OR closed flower buds on the tree. FALSE if the buds are strictly green leaf buds. FALSE if your explanation does not mention flowers or buds. MUST strictly match your explanation."
    )
  )
  
  # Call model and return structured results
  pheno_result <- tryCatch({
    result <- pheno_chat$chat_structured(
      "Extract the botanical data from this image according to the schema.",
      content_image_file(photo_path),
      type = pheno_check
    ) 
    # Convert
    as.data.frame(result)
    
    # In the event of an error:
  }, error = function(e) {
    warning(paste("Ollama failed on:", photo_path, "-", e$message))
    
    # Start fresh if an error happens
    if (requireNamespace("curl", quietly = TRUE)) {
      curl::handle_reset()
    }
    # Return empty row
    data.frame(
      has_fruit = NA,
      has_flower = NA,
      explanation = "FAILED_ANALYSIS",
      photo_path = photo_path
    )
  })
  
  # Tag with photo_path for back joining
  pheno_result$photo_path <- photo_path
  
  # Garbage collection pause for VLM
  Sys.sleep(3)
  
  # Return
  pheno_result
}


# Weather data functions --------------------------------------------------

format_date_vector <- function(start_date, end_date){
  date_sequence <- seq.Date(
    from = as_date(start_date),
    to = as_date(end_date),
    by = 1
  )
  
  # Remove hyphens because dates will be used to identify filenames
  format(date_sequence, "%Y%m%d")
}

download_prism <- function(weather_variables, min_date, max_date){
  
  # normalizePath ensures targets doesn't get lost in relative directories
  dl_dir <- normalizePath("data/prism_temp", mustWork = FALSE)
  prism_set_dl_dir(dl_dir)
  
  # Prep path list
  all_paths <- list()
  
  cli::cli_h2("Downloading PRISM dailys")
  
  # Loop through the variables and report on progress
  for (var in weather_variables) {
    
    cli::cli_alert_info("Downloading variable: {.var {var}}")
    
    get_prism_dailys(
      type = var,
      minDate = min_date,
      maxDate = max_date,
      keepZip = FALSE
    )
    
    downloaded_prism <- prism_archive_subset(
      type = var, 
      temp_period = "daily",
      minDate = min_date,
      maxDate = max_date,
      resolution = "4km"
    )
    
    # Extract the paths
    files <- pd_to_file(downloaded_prism)
    
    cli::cli_alert_success("Found {.val {length(files)}} files for {.var {var}}")
    
    all_paths[[var]] <- files
  }
  
  # Flatten the list
  final_paths <- unlist(all_paths, use.names = FALSE)
  
  final_paths
}

crop_prism <- function(file_path, out_dir = "data/prism_pnw/", crop_area){
  
  # Name conversion for tif outputs
  orig_name <- basename(file_path)
  new_name <- gsub(pattern = "\\.bil$", replacement = "_pnw.tif", orig_name)
  out_path <- file.path(out_dir, new_name)
  
  # Pull in raster
  raw_raster <- rast(file_path)
  # Transform CRS of crop_area
  crop_area_proj <- sf::st_transform(crop_area, crs = terra::crs(raw_raster))
  # Now crop raster
  cropped_raster <- raw_raster %>%
    # Crop to same bbox
    terra::crop(terra::vect(crop_area_proj)) %>%
    # Mask so cells not in shape but still in bbox are NA
    terra::mask(terra::vect(crop_area_proj))
  
  # Export
  terra::writeRaster(
    x = cropped_raster, 
    filename = out_path, 
    overwrite = TRUE,
    datatype = "FLT4S"
  )
  
  out_path
}

# Calculate chill hours from rasters
calc_chill_hours <- function(chill_date, cropped_files, chill_thresh_c = 7.2){
  # Filepath to chill hour raster output
  out_dir <- "data/prism_chill"
  
  # Identify files for target date's temperature inputs
  tmax_file_string <- sprintf("tmax.*%s.*\\.tif$", chill_date)
  tmax_file <- grep(tmax_file_string, cropped_files, value = TRUE)
  
  tmin_file_string <- sprintf("tmin.*%s.*\\.tif$", chill_date)
  tmin_file <- grep(tmin_file_string, cropped_files, value = TRUE)
  
  cli_alert_info("Calculating chill hours for: {.val {chill_date}}")
  
  out_path <- file.path(out_dir, paste0("chill_hours_", chill_date, ".tif"))
  
  if (file.exists(out_path)) return(out_path)
  
  # Load temperature rasters
  tmax <- rast(tmax_file)
  tmin <- rast(tmin_file)
  
  # Vertical center of the sine wave for daily temperature variation
  M <- (tmax + tmin) / 2
  # Sine distance from the midpoint to the absolute maximum
  W <- (tmax - tmin) / 2
  
  # Percent of 24hrs that falls below threshold
  chill_fraction <- 0.5 + (asin((chill_thresh_c - M) / W) / pi)
  # Convert to hours
  hours_interpolated <- 24 * chill_fraction
  
  chill_hours <- terra::ifel(
    # Stayed cold all day
    tmax <= chill_thresh_c, 24,                  
    terra::ifel(
      # Stayed warm all day
      tmin >= chill_thresh_c, 0,                 
      # Crossed the threshold
      hours_interpolated                       
    )
  )
  # Export chill hour raster
  terra::writeRaster(chill_hours, filename = out_path, overwrite = TRUE, datatype = "FLT4S")
  out_path
}

# Calculate degree days from rasters
calc_gdds <- function(gdd_date, out_dir = "data/prism_gdd/", cropped_rasters,
                      base_temp_c = 6.1, max_temp_c = 30){
  
  # Filepath to degree day raster output
  out_path <- file.path(out_dir, paste0("pnw_gdd_", gdd_date, ".tif"))
  
  # Identify files for target date's temperature inputs
  tmax_file_string <- sprintf("tmax.*%s.*\\.tif$", target_date)
  tmax_file <- grep(tmax_file_string, cropped_files, value = TRUE)
  
  tmin_file_string <- sprintf("tmin.*%s.*\\.tif$", target_date)
  tmin_file <- grep(tmin_file_string, cropped_files, value = TRUE)
  
  # Confirm files are real
  if (!file.exists(tmax_file) || !file.exists(tmin_file)) {
    cli_abort("Missing tmin or tmax file for date {.val {target_date}}")
  }
  
  cli_alert_info("Calculating GDD for: {.val {target_date}}")
  
  # Load temperature rasters and limit to max temperature
  tmax <- clamp(rast(tmax_file), upper = max_cap)
  tmin <- rast(tmin_file)
  
  M <- (tmax + tmin) / 2
  W <- (tmax - tmin) / 2
  
  gdd_simple <- M - base_temp
  
  # Sine wave for partial days
  alpha <- asin((base_temp - M) / W)
  gdd_sine <- (W * cos(alpha) - (base_temp - M) * ((pi/2) - alpha)) / pi
  
  gdd_final <- terra::ifel(
    # Never got warm enough
    tmax <= base_temp, 0,                   
    terra::ifel(
      # Stayed warm all day
      tmin >= base_temp, gdd_simple,        
      # Crossed the threshold
      gdd_sine                              
    )
  )
  
  writeRaster(gdd_final, filename = out_path, overwrite = TRUE, datatype = "FLT4S")
  out_path
  
}
