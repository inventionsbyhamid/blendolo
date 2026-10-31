# The interface every appearance provider implements. Operations:
#   :makeup   inputs photo: Appearance::Image, effects: Array of neutral effect Hashes (Looks::EffectsBuilder)
#   :transfer inputs photo: Appearance::Image (today's face), reference: Appearance::Image (the look to copy)
class Appearance::Provider
  # Starts a task. Returns an Appearance::Job; raises Appearance::Error when the provider refuses it.
  def start(operation, inputs) = raise(NotImplementedError)

  # Returns an Appearance::Outcome for a started job.
  def fetch(job) = raise(NotImplementedError)

  # Downloads a done outcome's image. operation: the job's (:makeup or :transfer), for a provider whose results of
  # one kind need cleaning up. Returns an Appearance::Image.
  def download(outcome, operation: nil) = raise(NotImplementedError)

  # Units left to spend.
  def balance = raise(NotImplementedError)

  # Units one task of the operation costs.
  def feature_cost(operation) = raise(NotImplementedError)

  # The pattern names an effect category accepts: [{name:, colours:, tags:}]. Free; cached.
  def patterns(category) = raise(NotImplementedError)

  private
    def validate!(operation, inputs)
      required = { makeup: %i[photo effects], transfer: %i[photo reference] }.fetch(operation) do
        raise ArgumentError, "unknown operation #{operation.inspect}"
      end
      missing = required.reject { |name| inputs[name].present? }
      raise ArgumentError, "#{operation} needs #{missing.join(', ')}" if missing.any?
    end
end
