module Billing
  # One paid plan from config/blendolo/plans.yml: a one-time pack or a monthly subscription, its price in US cents and
  # the credits it adds (each time, for a subscription).
  class Plan < Data.define(:key, :name, :kind, :price_cents, :credits)
    def self.all
      config.fetch(:plans).map do |key, plan|
        new(key: key.to_s, name: plan.fetch(:name), kind: plan.fetch(:kind), price_cents: plan.fetch(:price_cents),
          credits: plan.fetch(:credits))
      end
    end

    def self.find(key)
      all.find { |plan| plan.key == key.to_s }
    end

    def self.fetch(key)
      find(key) or raise KeyError, "No plan #{key.inspect}"
    end

    def self.config
      Rails.application.config_for(:"blendolo/plans")
    end

    def subscription?
      kind == "monthly"
    end

    # "$7.99", "$19".
    def price
      dollars, cents = price_cents.divmod(100)
      cents.zero? ? "$#{dollars}" : format("$%d.%02d", dollars, cents)
    end
  end
end
