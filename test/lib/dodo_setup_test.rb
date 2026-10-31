require "test_helper"
require Rails.root.join("script/billing/dodo_setup").to_s

# The Dodo setup script, against a stubbed API: it stops before creating anything unless the key's business is
# Blendolo, and it never prints a key, id or secret.
class DodoSetupTest < ActiveSupport::TestCase
  API = "https://test.dodopayments.com".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    @file = Rails.root.join("tmp/dodo-setup-test-#{SecureRandom.hex(4)}.env").to_s
    File.write(@file, "# Dodo\nDODO_API_KEY=dodo_test_key_value\n")
  end

  teardown { FileUtils.rm_f(@file) }

  test "stops before creating anything when the key belongs to another business" do
    stub_brands("Midway Shop")
    create = stub_request(:post, /#{API}/)

    output = run_setup(expect_exit: true)

    assert_match "Stopped before creating anything", output
    assert_not_requested create
    assert_equal "# Dodo\nDODO_API_KEY=dodo_test_key_value\n", File.read(@file)
  end

  test "creates both products and the webhook, and writes their ids and secret without printing them" do
    stub_brands("Blendolo")
    stub_request(:get, "#{API}/products").with(query: hash_including({})).to_return(status: 200, headers: JSON_HEADERS, body: { items: [] }.to_json)
    look_pack = stub_request(:post, "#{API}/products").with { |request| JSON.parse(request.body)["metadata"] == { "app" => "blendolo", "plan" => "look_pack" } }
      .to_return(status: 200, headers: JSON_HEADERS, body: product("pdt_new_pack").to_json)
    clinic = stub_request(:post, "#{API}/products").with { |request| JSON.parse(request.body).dig("price", "type") == "recurring_price" }
      .to_return(status: 200, headers: JSON_HEADERS, body: product("pdt_new_clinic").to_json)
    stub_request(:get, "#{API}/webhooks").with(query: hash_including({})).to_return(status: 200, headers: JSON_HEADERS, body: { data: [], done: true }.to_json)
    webhook = stub_request(:post, "#{API}/webhooks").with { |request| JSON.parse(request.body)["url"] == "https://blendolo.dijmo.com/webhooks/dodo" }
      .to_return(status: 200, headers: JSON_HEADERS, body: { id: "wh_1", url: "https://blendolo.dijmo.com/webhooks/dodo", description: "", metadata: {}, created_at: "2026-10-31T00:00:00Z", updated_at: "2026-10-31T00:00:00Z" }.to_json)
    stub_request(:get, "#{API}/webhooks/wh_1/secret").to_return(status: 200, headers: JSON_HEADERS, body: { secret: "whsec_secret_value" }.to_json)

    output = run_setup

    assert_requested look_pack
    assert_requested clinic
    assert_requested webhook
    env = File.read(@file)
    assert_includes env, "DODO_API_KEY=dodo_test_key_value\n"
    assert_includes env, "DODO_PRODUCT_LOOK_PACK=pdt_new_pack\n"
    assert_includes env, "DODO_PRODUCT_CLINIC=pdt_new_clinic\n"
    assert_includes env, "DODO_WEBHOOK_SECRET=whsec_secret_value\n"
    assert_includes env, "DODO_ENVIRONMENT=test_mode\n"
    assert_equal 0o600, File.stat(@file).mode & 0o777
    %w[dodo_test_key_value pdt_new_pack pdt_new_clinic whsec_secret_value wh_1].each { |value| assert_not_includes output, value }
  end

  test "asks Dodo for every event the app acts on" do
    assert_equal Billing::Dodo::SUBSCRIBED.sort, DodoSetup::EVENTS.sort
  end

  private
    def stub_brands(name)
      brand = { brand_id: "bnd_1", business_id: "bus_1", enabled: true, statement_descriptor: "X", verification_enabled: false,
        verification_status: "Success", name: }
      stub_request(:get, "#{API}/brands").to_return(status: 200, headers: JSON_HEADERS, body: { items: [ brand ] }.to_json)
    end

    def product(id)
      { product_id: id, business_id: "bus_1", brand_id: "bnd_1", created_at: "2026-10-31T00:00:00Z", updated_at: "2026-10-31T00:00:00Z",
        is_recurring: false, tax_category: "saas", metadata: {}, entitlements: [], name: "x",
        price: { type: "one_time_price", currency: "USD", price: 799, discount: 0, purchasing_power_parity: false } }
    end

    def run_setup(expect_exit: false)
      out, err = capture_io do
        DodoSetup.run(@file, DodoSetup::DEFAULT_WEBHOOK_URL)
      rescue SystemExit
        flunk "the script stopped" unless expect_exit
      end
      out + err
    end
end
