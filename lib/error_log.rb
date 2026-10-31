# A Rails.error subscriber that writes one log line per reported error: its class, whether it was handled, which job
# or controller reported it and the ids it was reported with. Never the message, which can carry a signed storage
# link or a token.
class ErrorLog
  IDS = %i[render_id example].freeze

  def report(error, handled:, severity:, context:, source: nil)
    owners = context.values_at(:job, :controller).compact.map { |owner| owner.class.name }
    ids = context.slice(*IDS).map { |key, value| "#{key}=#{value}" }
    Rails.logger.error([ "Reported", error.class.name, "handled=#{handled}", "severity=#{severity}", *owners, *ids ].join(" "))
  end
end
