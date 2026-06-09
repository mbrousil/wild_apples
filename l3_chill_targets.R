l3_chill_targets <- list(
  # Chill hour calcs
  tar_target(
    name = chill_hour_calculations,
    packages = c("lubridate", "cli", "terra"),
    command = calc_chill_hours(
      chill_date = chill_dates,
      cropped_files = prism_cropped
    ),
    pattern = map(chill_dates),
    format = "file"
  )
  
)