# One look for one kit: the classic steps, the easy version for these hands (the planner picks, for each hard step,
# the easier candidate that suits these hands best), how easy each version is, and the effects that render each on
# today's photo. A look's optional steps (mascara, lashes, curler, setting spray) never set its grade: they're listed
# apart, each with its own ease in words. Glue between Looks (what a look is) and Ease (how hard it is for these hands).
class LookForKit
  attr_reader :look, :kit

  # The tweak levels on the easy version: "Softer" and "Bolder" move one level, five in all.
  LEVELS = { -2 => "Much softer", -1 => "Softer", 0 => "Medium", 1 => "Bolder", 2 => "Much bolder" }.freeze
  LEVEL_STEP = 0.2

  def self.all(kit)
    Looks::Catalogue.all.map { |look| new(kit, look) }
  end

  # Easiest first, for this kit's hands.
  def self.easiest_first(kit)
    all(kit).sort_by.with_index { |look_for_kit, index| [ -look_for_kit.classic_ease[:ease], index ] }
  end

  def self.find(kit, key)
    new(kit, Looks::Catalogue.fetch(key))
  end

  def initialize(kit, look)
    @kit = kit
    @look = look
  end

  delegate :key, :name, :blurb, :thumbnail, :steps, to: :look

  def profile
    @profile ||= kit.hand_profile
  end

  def plan
    @plan ||= look.plan(profile)
  end

  def swaps = plan[:swaps]

  # Hard steps with no easier version, that do set the grade (optional ones are listed under #optional_steps).
  def unswappable = plan[:unswappable].reject(&:optional?)

  # The easy version's optional steps: [{ step:, ease:, words: }], each with its own ease, never the look's grade.
  def optional_steps = easy_ease[:optional]

  # True when this step stays hard because nothing easier exists (mascara), optional or not.
  def no_easier_swap?(step)
    plan[:unswappable].any? { |hard| hard.id == step.id }
  end

  def easy_steps
    @easy_steps ||= look.easy_steps(profile)
  end

  # { ease: 0..100, hardest_step: Ease::Step, optional: [{ step:, ease:, words: }] } (see Ease::Scorer.look)
  def classic_ease
    @classic_ease ||= Ease::Scorer.look(look.ease_steps, profile)
  end

  def easy_ease
    @easy_ease ||= Ease::Scorer.look(easy_steps.map(&:step), profile)
  end

  def classic_words = Ease::Words.for(classic_ease[:ease])

  def easy_words = Ease::Words.for(easy_ease[:ease])

  def classic_effects(photo)
    Looks::EffectsBuilder.build(look.steps, skin: skin(photo))
  end

  def easy_effects(photo, level: 0)
    effects = Looks::EffectsBuilder.build(easy_steps, skin: skin(photo))
    level.zero? ? effects : scale(effects, level)
  end

  private
    def skin(photo)
      photo&.sampled&.dig("skin")
    end

    # Softer or bolder: every intensity moves by a fifth per level, within 0..100.
    def scale(effects, level)
      factor = 1 + LEVEL_STEP * level.clamp(LEVELS.keys.minmax.first, LEVELS.keys.minmax.last)
      effects.map { |effect| effect.merge(intensity: (effect[:intensity].to_f * factor).round.clamp(0, 100)) }
    end
end
