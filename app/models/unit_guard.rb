# Decides whether a live provider call may go ahead, cheapest check first:
#   :example   example kits only show stored results
#   :kit_cap   this kit has used its live calls for the operation (config/blendolo/caps.yml). Only for kits in no
#              account: a kit in an account pays for every call with credits, which are its limit instead
#   :daily_cap the app has spent YOUCAM_DAILY_UNIT_CAP units today (UTC), counting calls still in flight
#   :floor     the call would take the provider balance below YOUCAM_UNIT_FLOOR (or the balance can't be read)
#   :ok
module UnitGuard
  DEFAULT_DAILY_CAP = 60
  DEFAULT_FLOOR = 150

  module_function

  def check(kit:, operation:, provider: Appearance.provider, env: ENV)
    return :example if kit.example?
    return :kit_cap if kit.user_id.nil? && live_calls(kit, operation) >= per_kit.fetch(operation)

    cost = provider.feature_cost(operation)
    return :daily_cap if ProviderCall.units_spent_on(Date.current) + cost > daily_cap(env)
    return :floor if provider.balance - cost < floor(env)

    :ok
  rescue Appearance::Error => error
    Rails.logger.warn("Provider balance unavailable, holding calls: #{error.message}")
    :floor
  end

  def live_calls(kit, operation)
    kit.provider_calls.counted.where(operation: operation.to_s).count
  end

  def per_kit
    Rails.application.config_for(:"blendolo/caps").fetch(:per_kit).transform_keys(&:to_sym)
  end

  def daily_cap(env = ENV) = env.fetch("YOUCAM_DAILY_UNIT_CAP", DEFAULT_DAILY_CAP).to_i
  def floor(env = ENV) = env.fetch("YOUCAM_UNIT_FLOOR", DEFAULT_FLOOR).to_i
end
