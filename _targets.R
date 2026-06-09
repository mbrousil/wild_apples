
# Load packages required to define the pipeline:
library(crew)
library(targets)
library(tarchetypes)

# Set target options:
tar_option_set(
  packages = c("tidyverse"),
  format = "qs",
  controller = crew_controller_local(workers = 4)
)

# Confirm that necessary folders exist
dir.create("data/prism_temp", recursive = TRUE, showWarnings = FALSE)
dir.create("data/prism_pnw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/prism_chill", recursive = TRUE, showWarnings = FALSE)
dir.create("data/prism_gdd", recursive = TRUE, showWarnings = FALSE)

# Run the R scripts in the R/ folder
tar_source(
  files = c(
    "R/",
    "l2_temperature_targest.R",
    "l3_chill_targets.R",
    "l4_growing_dd_targets.R",
    "l5_inaturalist_targets.R"
  )
)

# List of config or high-level pipeline targets
l1_high_level_targets <- list(
  
  # Vector of dates to use for calculating chill hours
  tar_target(
    name = chill_dates,
    command = format_date_vector(
      start_date = "2025-11-01",
      end_date = "2026-03-01")
  ),
  
  # Vector of dates to use for calculating degree days
  tar_target(
    name = gdd_dates,
    packages = c("lubridate"),
    command = format_date_vector(
      start_date = "2022-01-01",
      end_date = "2022-12-31"
    )
  )
)

# Full targets list (split over multiple files)
c(
  l1_high_level_targets, l2_temperature_targets, l3_chill_targets,
  l4_growing_dd_targets, l5_inaturalist_targets
)