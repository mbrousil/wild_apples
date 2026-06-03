
# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)

# Set target options:
tar_option_set(
  packages = c("tidyverse"),
  format = "qs"
)

# Run the R scripts in the R/ folder
tar_source()

# List of pipeline targets
list(
  
  # Returns a download key that the next target will use as a timer for knowing
  # when the requested data have finished being prepared.
  # This is an iNaturalist dataset that is updated weekly on GBIF:
  # https://www.gbif.org/dataset/50c9509d-22c7-4a22-a47d-8c48425ef4a7
  # Probably a placeholder for now
  tar_target(
    name = inat_training_download_key,
    packages = c("rgbif"),
    command = {
      # Dataset key on GBIF
      inat_ds_key <- "50c9509d-22c7-4a22-a47d-8c48425ef4a7"
      # taxonKey for Malus domestica
      apple_key <- name_backbone("Malus domestica")$usageKey
      
      # Request, with some tips from https://data-blog.gbif.org/post/gbif-filtering-guide/
      occ_download(
        # Dataset to request
        pred("datasetKey", inat_ds_key),
        # Taxon to request
        pred("taxonKey", apple_key),
        # Contains coords
        pred("hasCoordinate", TRUE), 
        # No flagged geospatial problems
        pred("hasGeospatialIssue", FALSE),
        # Darwin Core
        format = "DWCA"
      )
    }
  ),
  
  # Checks the download progress and then downloads when it's done being prepared
  tar_file(
    name = inat_training_download,
    packages = c("rgbif"),
    command = {
      # Waits for request in previous target to finish
      occ_download_wait(inat_training_download_key)
      
      # Get it once complete
      occ_download_get(inat_training_download_key, path = "data/")
    }
  ),
  
  # Open DWCA format and cache occurrence data as qs file in pipeline
  tar_target(
    name = inat_training_data,
    packages = c("rgbif", "finch"),
    command = {
      inat_data <- dwca_read(
        input = inat_training_download,
        read = TRUE
      )
      # Returns
      inat_data$data$occurrence.txt
    },
    format = "qs"
  ),
  
  # Open DWCA format and cache photo data as qs file in pipeline
  tar_target(
    name = inat_photo_metadata,
    packages = c("rgbif", "finch"),
    command = {
      inat_data <- dwca_read(
        input = inat_training_download,
        read = TRUE
      )
      # Returns
      inat_data$data$multimedia.txt
    },
    format = "qs"
  ),
  
  # Grab 100 records that have photos in order to test out local visual LM
  # ability to ID fruit and flowers
  tar_target(
    name = inat_photo_matchups,
    command = {
      # iNat samples grouped by reproductive condition
      set.seed(78)
      inat_subsample <- inat_training_data %>%
        group_by(reproductiveCondition) %>%
        slice_sample(n = 15, .data = .)
      
      # Match to photo metadata
      photo_metadata_join <- inner_join(
        x = inat_subsample,
        y = inat_photo_metadata,
        by = c("gbifID")
      )
      
      # Return
      photo_metadata_join
    }
  )
)
