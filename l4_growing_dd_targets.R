l4_growing_dd_targets <- list(
  
  # Degree day calcs
  tar_target(
    name = degree_day_calculations,
    packages = c("lubridate", "cli", "terra"),
    command = calc_gdds(
      gdd_date = gdd_dates,
      cropped_rasters = prism_cropped
    ),
    pattern = map(gdd_dates),
    format = "file"
  ),
  
  # Accumulate seasonal chill into single raster
  tar_file(
    name = cumulative_gdd,
    packages = c("cli", "terra"),
    command = accumulate_rasters(
      file_paths = degree_day_calculations,
      out_name = "cumulative_gdd"
    )
  )
  
)
