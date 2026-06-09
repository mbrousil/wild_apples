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
  )
)
