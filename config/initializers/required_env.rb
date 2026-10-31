# Initializers run before autoloading is set up, so this file is required here and kept out of the autoloader
# (config/application.rb).
require_relative "../../lib/required_env"

# Production stops at boot, naming the first missing variable. The image build precompiles assets in production with
# only SECRET_KEY_BASE_DUMMY set, so that boot is let through.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  RequiredEnv.check!(RequiredEnv.production)
  RequiredEnv.check_values!
end
