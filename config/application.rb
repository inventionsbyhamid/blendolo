require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Blendolo
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # required_env.rb is required by its initializer, which runs before autoloading.
    config.autoload_lib(ignore: %w[assets tasks required_env.rb])

    # The health check answers any host and plain http: container health checks ask for http://localhost/up.
    # Production limits hosts and forces SSL (config/environments/production.rb); these keep /up out of both. They're
    # set here, for every environment, so test/integration/health_test.rb exercises the same rules.
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
    config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

    # The one host production answers (config/environments/production.rb), also read by the health test.
    config.x.canonical_host = "blendolo.dijmo.com"

    # MediaPipe Tasks Vision for hands-free capture: the pinned package (script and wasm) and the face model file.
    # The content security policy allows exactly these; the capture code should load from the same values.
    config.x.mediapipe = ActiveSupport::OrderedOptions.new.merge!(
      package_url: "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.1.1/",
      model_url: "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
    )

    # Only the camera, and only for us. Rails' permissions_policy still sends the older Feature-Policy header.
    config.action_dispatch.default_headers["Permissions-Policy"] =
      "camera=(self), microphone=(), geolocation=(), payment=(), usb=(), display-capture=()"

    # Storage URLs (never sent to browsers in proxy mode) work for 5 minutes. Our proxy links, the only image links
    # pages carry, last an hour: a page left open still shows its pictures, and a revoked share's stop within the hour.
    config.active_storage.urls_expire_in = 1.hour
    config.active_storage.service_urls_expire_in = 5.minutes

    # Photos and previews are served through our own origin (Active Storage proxy mode), never as redirects to the
    # storage bucket: the content security policy allows images from 'self' only, and bucket links never reach the
    # browser.
    config.active_storage.resolve_model_to_route = :rails_storage_proxy

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
