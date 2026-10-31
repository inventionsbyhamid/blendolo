module PhotosHelper
  # MediaPipe Tasks Vision for the capture checks, pinned to the package and model the content security policy allows
  # (config.x.mediapipe). The defaults are the same pins, for branches without that config.
  MEDIAPIPE_PACKAGE_URL = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.1.1/".freeze
  MEDIAPIPE_MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task".freeze

  # { package_url:, model_url: }, or blank ones when capture checks are switched off (tests run without the network).
  def mediapipe_urls
    return { package_url: "", model_url: "" } if Rails.application.config.x.capture_checks == false

    config = Rails.application.config.x.mediapipe
    { package_url: config.package_url || MEDIAPIPE_PACKAGE_URL, model_url: config.model_url || MEDIAPIPE_MODEL_URL }
  end
end
