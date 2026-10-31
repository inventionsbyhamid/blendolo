# Decides whether a live provider call may go ahead, cheapest check first:
#   :example   example kits only show stored results
#   :daily_cap the app has spent YOUCAM_DAILY_UNIT_CAP units today (UTC), counting calls still in flight
#   :floor     the call would take the provider balance below YOUCAM_UNIT_FLOOR (or the balance can't be read)
#   :ok
module UnitGuard
  DEFAULT_DAILY_CAP = 60
  DEFAULT_FLOOR = 150

  module_function

  def check(kit:, operation:, provider: Appearance.provider, env: ENV)
    return :example if kit.example?

    cost = provider.feature_cost(operation)
    return :daily_cap if ProviderCall.units_spent_on(Date.current) + cost > daily_cap(env)
    return :floor if provider.balance - cost < floor(env)

    :ok
  rescue Appearance::Error => error
    Rails.logger.warn("Provider balance unavailable, holding calls: #{error.message}")
    :floor
  end

  def daily_cap(env = ENV) = env.fetch("YOUCAM_DAILY_UNIT_CAP", DEFAULT_DAILY_CAP).to_i
  def floor(env = ENV) = env.fetch("YOUCAM_UNIT_FLOOR", DEFAULT_FLOOR).to_i
end
