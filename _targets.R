
# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)

# Set target options:
tar_option_set(
  packages = c("tidyverse"),
  format = "qs",
  controller = crew_controller_local(workers = 4)
)

# Confirm that necessary folders exist
dir.create("data/prism_temporary", recursive = TRUE, showWarnings = FALSE)
dir.create("data/prism_pnw", recursive = TRUE, showWarnings = FALSE)

# Run the R scripts in the R/ folder
tar_source(
  files = c("R/",
            "l2_temperature_targets.R",
            "l3_inaturalist_targets.R")
)

# List of config or high-level pipeline targets
l1_high_level_targets <- list(
  
)

# Full targets list (split over multiple files)
c(l1_high_level_targets, l2_temperature_targets, l3_inaturalist_targets)