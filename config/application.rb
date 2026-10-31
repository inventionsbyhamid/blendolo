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

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
