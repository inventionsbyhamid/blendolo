# A signature look rebuilt for one kit: the classic steps from colours sampled on the old photo and two answers
# (liner, lips), the easy version for these hands, how easy each is, and the effects that render the easy version.
class SignatureLook
  LINERS = { "winged" => "Winged", "thin" => "Thin line", "smudged" => "Smudged", "none" => "None" }.freeze
  LIPS = { "matte" => "Matte", "shiny" => "Shiny", "sheer" => "Sheer" }.freeze

  attr_reader :kit, :reference, :liner, :lips

  # nil unless both answers are ones we offer.
  def self.build(kit, reference, liner:, lips:)
    new(kit, reference, liner.to_s, lips.to_s) if reference && LINERS.key?(liner.to_s) && LIPS.key?(lips.to_s)
  end

  def initialize(kit, reference, liner, lips)
    @kit = kit
    @reference = reference
    @liner = liner
    @lips = lips
  end

  def steps
    @steps ||= Looks::EffectsBuilder.signature(sampled: reference.sampled, liner:, lips:)
  end

  def profile = kit.hand_profile

  def plan
    @plan ||= Looks::Look.plan(steps, profile)
  end

  def swaps = plan[:swaps]

  def unswappable = plan[:unswappable]

  def easy_steps
    @easy_steps ||= Looks::Look.easy_steps(steps, profile)
  end

  def classic_ease = Ease::Scorer.look(steps.map(&:step), profile)

  def easy_ease = Ease::Scorer.look(easy_steps.map(&:step), profile)

  def easy_effects(photo)
    Looks::EffectsBuilder.build(easy_steps, skin: photo.sampled["skin"])
  end

  # The old photo gave no colours (the browser couldn't read the face): only the liner can be rebuilt.
  def colours_missing?
    reference.sampled.slice("lips", "lids", "cheeks").empty?
  end
end
