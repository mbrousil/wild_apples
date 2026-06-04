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
run_vlm_analysis <- function(photo_path, vlm = "llama3.2-vision") {
  
  # Initialize chat with instructions
  pheno_chat <- chat_ollama(
    model = vlm,
    api_args = list(temperature = 0),
    system_prompt = "You are a data extraction assistant. Please analyze the image and extract the structured data accurately."
  )
  
  # Define structure of the returned info
  pheno_check <- type_object(
    has_fruit = type_boolean(description = "True if the image contains a tree with fruit. False otherwise."),
    has_flower = type_boolean(description = "True if the image contains a tree with flowers. False otherwise."),
    explanation = type_string(description = "A brief explanation of the visual evidence. No longer than one sentence.")
  )
  
  # Call model and return structured results
  pheno_result <- tryCatch({
    result <- pheno_chat$chat_structured(
      "Please analyze this image. Does it contain a tree with fruit or flowers on it?",
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
  
  pheno_result
}
