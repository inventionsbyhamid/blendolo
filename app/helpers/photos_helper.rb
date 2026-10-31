module PhotosHelper
  # MediaPipe Tasks Vision for the capture checks, from exactly the package and model the content security policy
  # allows (config.x.mediapipe), and the worker that runs it off the page's main thread with the gates module it
  # loads (a worker has no import map). Blank when capture checks are switched off (tests run without the network);
  # no worker URL when the worker is (config.x.capture_worker), so the page runs the checks itself.
  def mediapipe_urls
    return { package_url: "", model_url: "", worker_url: "", gate_url: "" } if Rails.application.config.x.capture_checks == false

    config = Rails.application.config.x.mediapipe
    worker_url = Rails.application.config.x.capture_worker ? asset_path("workers/face_checks.js") : ""
    { package_url: config.package_url, model_url: config.model_url, worker_url:, gate_url: asset_path("capture/gate.js") }
  end
end
