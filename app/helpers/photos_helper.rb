module PhotosHelper
  # MediaPipe Tasks Vision for the capture checks, from exactly the package and model the content security policy
  # allows (config.x.mediapipe), and the worker that runs it off the page's main thread with the gates module it
  # loads (a worker has no import map). Blank when capture checks are switched off (tests run without the network).
  def mediapipe_urls
    return { package_url: "", model_url: "", worker_url: "", gate_url: "" } if Rails.application.config.x.capture_checks == false

    config = Rails.application.config.x.mediapipe
    { package_url: config.package_url, model_url: config.model_url,
      worker_url: asset_path("workers/face_checks.js"), gate_url: asset_path("capture/gate.js") }
  end
end
