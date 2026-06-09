l2_temperature_targets <- list(
  
  # Download PRISM temperatures
  tar_files(
    name = prism_downloads,
    packages = c("prism", "cli"),
    command = download_prism(
      weather_variables = c("tmin", "tmax", "tmean"),
      min_date = "2022-01-01",
      max_date = "2022-12-31"
    )
  ),
  
  # Area of interest
  tar_target(
    name = weather_aoi,
    packages = c("dplyr", "tigris"),
    command = states(cb = TRUE) %>%
      filter(NAME %in% c("Washington", "Oregon", "Idaho"))
  ),
  
  # Crop PRISM rasters to WA/OR/ID
  tar_target(
    name = prism_cropped,
    packages = c("cli", "dplyr", "sf", "terra", "tigris"),
    command = crop_prism(
      file_path = prism_downloads,
      crop_area = weather_aoi
    ),
    pattern = map(prism_downloads),
    format = "file"
  )
)