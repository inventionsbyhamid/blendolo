require "test_helper"

# Production answers only its own host, over https (config/environments/production.rb), but container health checks
# ask for http://localhost/up. These tests put the app behind host authorization and SSL set up the way production
# sets them up, so /up has to get through both while other paths don't.
class HealthTest < ActionDispatch::IntegrationTest
  HOST = Rails.configuration.x.canonical_host

  def app
    config = Rails.application.config
    ssl = ActionDispatch::SSL.new(Rails.application, **config.ssl_options)
    ActionDispatch::HostAuthorization.new(ssl, [ HOST ], **config.host_authorization)
  end

  test "up returns 200 for any host" do
    get "/up", headers: { "Host" => "evil.test" }

    assert_response :success
  end

  test "other paths refuse unknown hosts" do
    get "/", headers: { "Host" => "evil.test" }

    assert_response :forbidden
  end

  test "up answers plain http without redirecting" do
    get "http://#{HOST}/up"

    assert_response :success
  end

  test "other paths redirect plain http to https" do
    get "http://#{HOST}/"

    assert_response :moved_permanently
    assert_equal "https://#{HOST}/", response.location
  end
end
