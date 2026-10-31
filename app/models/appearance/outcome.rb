# Where a provider task stands. state is :running, :done or :failed. A done task has an image_url to download from
# (short-lived; never stored or shown); a failed one has a reason from Appearance::REASONS and, when known, which photo
# it's about (:photo or :reference). data is any provider-neutral result data.
class Appearance::Outcome < Data.define(:state, :image_url, :data, :reason, :about, :units)
  def initialize(state:, image_url: nil, data: {}, reason: nil, about: nil, units: nil)
    super
  end

  def running? = state == :running
  def done? = state == :done
  def failed? = state == :failed
end
