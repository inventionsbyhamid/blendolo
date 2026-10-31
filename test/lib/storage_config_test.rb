require "test_helper"

# Production keeps uploads in Cloudflare R2 through Active Storage's S3 service. Building the service makes no request.
class StorageConfigTest < ActiveSupport::TestCase
  R2_ENV = { "R2_ACCOUNT_ID" => "account123", "R2_ACCESS_KEY_ID" => "key-id", "R2_SECRET_ACCESS_KEY" => "secret",
             "R2_BUCKET" => "uploads-bucket" }.freeze

  test "the r2 service points at the account's R2 endpoint and skips the checksums R2 rejects" do
    service = with_env(R2_ENV) { ActiveStorage::Service.configure(:r2, storage_configs) }
    config = service.client.client.config

    assert_kind_of ActiveStorage::Service::S3Service, service
    assert_equal "uploads-bucket", service.bucket.name
    assert_equal "https://account123.r2.cloudflarestorage.com", config.endpoint.to_s
    assert_equal "auto", config.region
    assert_equal "when_required", config.request_checksum_calculation
    assert_equal "when_required", config.response_checksum_validation
  end

  test "production stores files in r2" do
    production = Rails.root.join("config/environments/production.rb").read

    assert_match(/^\s*config\.active_storage\.service = :r2$/, production)
  end

  private
    def storage_configs
      ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml")).deep_symbolize_keys
    end

    def with_env(values)
      saved = values.keys.index_with { |name| ENV[name] }
      values.each { |name, value| ENV[name] = value }
      yield
    ensure
      saved.each { |name, value| ENV[name] = value }
    end
end
