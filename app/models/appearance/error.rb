# A provider call that can't go on. reason is one of Appearance::REASONS; about says which photo it concerns
# (:photo or :reference) when the provider tells us. maybe_charged is true when the provider may have started, and
# charged, a task anyway (a server or network error while creating it); a definite refusal is never charged.
class Appearance::Error < StandardError
  attr_reader :reason, :about

  def initialize(reason, about: nil, message: nil, maybe_charged: false)
    raise ArgumentError, "unknown reason #{reason.inspect}" unless reason.in?(Appearance::REASONS)

    @reason = reason
    @about = about
    @maybe_charged = maybe_charged
    super(message || reason.to_s)
  end

  def maybe_charged? = @maybe_charged
end
