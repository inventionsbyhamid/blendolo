module PhotosHelper
  # MediaPipe Tasks Vision for the capture checks, from exactly the package and model the content security policy
  # allows (config.x.mediapipe). Blank when capture checks are switched off (tests run without the network).
  def mediapipe_urls
    return { package_url: "", model_url: "" } if Rails.application.config.x.capture_checks == false

    config = Rails.application.config.x.mediapipe
    { package_url: config.package_url, model_url: config.model_url }
  end
end
