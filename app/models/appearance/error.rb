# A provider call that can't go on. reason is one of Appearance::REASONS; about says which photo it concerns
# (:photo or :reference) when the provider tells us.
class Appearance::Error < StandardError
  attr_reader :reason, :about

  def initialize(reason, about: nil, message: nil)
    raise ArgumentError, "unknown reason #{reason.inspect}" unless reason.in?(Appearance::REASONS)

    @reason = reason
    @about = about
    super(message || reason.to_s)
  end
end
