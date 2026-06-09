l3_chill_targets <- list(
  # Chill hour calcs
  tar_target(
    name = chill_hour_calculations,
    packages = c("lubridate", "cli", "terra"),
    command = calc_chill_hours(
      chill_date = chill_dates,
      cropped_rasters = prism_cropped
    ),
    pattern = map(chill_dates),
    format = "file"
  ),
  
  # Accumulate seasonal chill into single raster
  tar_file(
    name = cumulative_chill,
    packages = c("cli", "terra"),
    command = accumulate_rasters(
      file_paths = chill_hour_calculations,
      out_name = "cumulative_chill_hours"
    )
  )
  
)