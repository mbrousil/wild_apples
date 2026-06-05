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
                  max_tokens = 512,
                  num_ctx = 4096),
    system_prompt = "You are an expert botanical assistant. Analyze the plant material in the image carefully and extract structured data.")
  
  # Define structure of the returned info
  pheno_check <- type_object(
    explanation = type_string(
      description = "First, scan the image closely. Describe the plant material. Note if you see open flowers, closed flower buds, green leaf buds, or fruit. WARNING: Apple flower buds are often dark pink or red before opening; do not confuse these red flower buds with berries or fruit."
    ),
    has_fruit = type_boolean(
      description = "TRUE only if actual mature or developing fruit (like apples) are clearly visible. FALSE if the red/pink objects are just closed flower buds. FALSE if there is no fruit."
    ),
    has_flower = type_boolean(
      description = "TRUE if there are open flowers OR closed flower buds. FALSE if the buds are strictly green leaf buds. FALSE if there are no flowers/buds."
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
