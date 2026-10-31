# Sets up Dodo Payments for Blendolo in test mode: the two products and the webhook endpoint, from an env file that
# holds DODO_API_KEY. Writes DODO_PRODUCT_LOOK_PACK, DODO_PRODUCT_CLINIC, DODO_WEBHOOK_SECRET and DODO_ENVIRONMENT back
# into that same file (mode 600). Prints names and steps, never a key, id or secret.
#
#   bundle exec ruby script/billing/dodo_setup.rb <env file> [--webhook-url https://<host>/webhooks/dodo]
#
# Before it creates anything it checks the key belongs to a business with a brand named Blendolo (a business's name
# is its primary brand's name): each app gets its own business, so a key for another business stops here. Safe to run
# again: it reuses products and the webhook it made before (by our metadata and the URL).
require "bundler/setup"
require "dodopayments"
require "yaml"

module DodoSetup
  BUSINESS_NAME = "Blendolo".freeze
  DEFAULT_WEBHOOK_URL = "https://blendolo.dijmo.com/webhooks/dodo".freeze
  # The events Billing::Dodo acts on.
  EVENTS = %w[payment.succeeded subscription.active subscription.renewed subscription.cancelled subscription.expired
    refund.succeeded].freeze
  DESCRIPTIONS = {
    "look_pack" => "%{credits} credits for previews of makeup looks on your own face. One credit is one preview.",
    "clinic" => "%{credits} credits every month and a client list, for clinics and care teams. One credit is one preview."
  }.freeze

  module_function

  def run(env_file, webhook_url)
    env = read_env(env_file)
    key = env["DODO_API_KEY"].to_s.strip
    abort "Stopped: DODO_API_KEY is not in #{File.basename(env_file)}." if key.empty?

    client = Dodopayments::Client.new(bearer_token: key, environment: :test_mode, timeout: 30)
    check_business!(client)

    plans = YAML.load_file(File.expand_path("../../config/blendolo/plans.yml", __dir__)).fetch("shared").fetch("plans")
    ids = plans.to_h { |key_name, plan| [ key_name, product_for(client, key_name, plan) ] }
    secret = webhook_secret(client, webhook_url)

    write_env(env_file, "DODO_ENVIRONMENT" => "test_mode", "DODO_PRODUCT_LOOK_PACK" => ids.fetch("look_pack"),
      "DODO_PRODUCT_CLINIC" => ids.fetch("clinic"), "DODO_WEBHOOK_SECRET" => secret)
    puts "Wrote DODO_ENVIRONMENT, DODO_PRODUCT_LOOK_PACK, DODO_PRODUCT_CLINIC and DODO_WEBHOOK_SECRET to #{File.basename(env_file)}."
  rescue Dodopayments::Errors::Error => e
    status = e.respond_to?(:status) ? " #{e.status}" : ""
    abort "Stopped: Dodo answered #{e.class.name.split('::').last}#{status}. Nothing more was changed."
  end

  # The business behind the key: every brand it lists belongs to it, and one of them must be named Blendolo.
  def check_business!(client)
    brands = client.brands.list.items
    names = brands.map { |brand| brand.name.to_s.strip }
    businesses = brands.map(&:business_id).uniq
    unless businesses.size == 1 && names.any? { |name| name.casecmp?(BUSINESS_NAME) }
      abort "Stopped before creating anything: this key's business has brands #{names.inspect}, not #{BUSINESS_NAME}. " \
        "Use a test mode key from the #{BUSINESS_NAME} business (one business per app)."
    end
    puts "Business checked: it has a brand named #{BUSINESS_NAME}."

    others = products(client).reject { |product| product.metadata.to_h.transform_keys(&:to_s)["app"] == "blendolo" }
    puts "Note: the business already has #{others.size} other product(s): #{others.map(&:name).inspect}." if others.any?
  end

  def products(client)
    found = []
    client.products.list(page_size: 100).auto_paging_each { |product| found << product }
    found
  end

  def product_for(client, key, plan)
    existing = products(client).find do |product|
      metadata = product.metadata.to_h.transform_keys(&:to_s)
      metadata["app"] == "blendolo" && metadata["plan"] == key
    end
    if existing
      puts "Product #{plan.fetch('name')}: already there."
      return existing.product_id
    end

    product = client.products.create(name: "Blendolo #{plan.fetch('name')}",
      description: format(DESCRIPTIONS.fetch(key), credits: plan.fetch("credits")),
      price: price(plan), tax_category: :saas, metadata: { app: "blendolo", plan: key })
    puts "Product #{plan.fetch('name')}: created."
    product.product_id
  end

  def price(plan)
    if plan.fetch("kind") == "monthly"
      { type: :recurring_price, currency: :USD, price: plan.fetch("price_cents"), tax_inclusive: false,
        payment_frequency_count: 1, payment_frequency_interval: :Month, subscription_period_count: 10,
        subscription_period_interval: :Year }
    else
      { type: :one_time_price, currency: :USD, price: plan.fetch("price_cents"), tax_inclusive: false }
    end
  end

  def webhook_secret(client, url)
    webhooks = []
    client.webhooks.list.auto_paging_each { |webhook| webhooks << webhook }
    webhook = webhooks.find { |existing| existing.url == url }
    if webhook
      puts "Webhook endpoint: already there."
    else
      webhook = client.webhooks.create(url:, description: "Blendolo: credits and the Clinic plan", filter_types: EVENTS)
      puts "Webhook endpoint: created for #{EVENTS.size} event types."
    end
    client.webhooks.retrieve_secret(webhook.id).secret
  end

  def read_env(file)
    File.readlines(file, chomp: true).each_with_object({}) do |line, env|
      name, value = line.split("=", 2)
      env[name.strip] = value.to_s.strip.delete_prefix('"').delete_suffix('"') if value && name.match?(/\A\s*[A-Z_]+\s*\z/)
    end
  end

  # Replaces each name's line, or adds it, keeping every other line as it was.
  def write_env(file, values)
    lines = File.readlines(file, chomp: true)
    values.each do |name, value|
      index = lines.index { |line| line.start_with?("#{name}=") }
      index ? lines[index] = "#{name}=#{value}" : lines << "#{name}=#{value}"
    end
    File.write(file, lines.join("\n") + "\n")
    File.chmod(0o600, file)
  end
end

if $PROGRAM_NAME == __FILE__
  file = ARGV[0] or abort "Usage: bundle exec ruby script/billing/dodo_setup.rb <env file> [--webhook-url URL]"
  url_flag = ARGV.index("--webhook-url")
  DodoSetup.run(File.expand_path(file), url_flag ? ARGV.fetch(url_flag + 1) : DodoSetup::DEFAULT_WEBHOOK_URL)
end
