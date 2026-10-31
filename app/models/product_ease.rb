# How easy a product is to open and use, for different hands. A product is a format, a closure and a grip, and
# optionally the routine step it's for (its precision, eye and time dimensions). Its closure sets the O (opening)
# dimension and its grip the G (grip) dimension; everything is scored with the ease engine.
class ProductEase
  CLOSURES = { "pump" => 0, "flip_cap" => 0, "magnetic" => 0, "none" => 0, "pull_cap" => 1, "twist_cap" => 2,
               "clasp_compact" => 3 }.freeze
  GRIPS = %w[chunky big_handle standard slim].freeze
  FORMATS = %w[pump stick crayon cream balm gel pencil liquid powder spray wand].freeze
  # A product for no particular step: middling on everything but how it opens and how it's held.
  NEUTRAL = { P: 1, E: 0, G: 1, H: 0, T: 1, F: 1, O: 1 }.freeze

  # The hand profiles the API reports, each one answer at its strongest.
  PROFILES = {
    "steady" => {}, "tremor" => { tremor: 2 }, "pinch_grip" => { pinch: 2 }, "one_hand" => { one_hand: 2 },
    "tires_fast" => { fatigue: 2 }, "close_vision" => { near_vision: 2 }
  }.freeze

  # Which tags matter for which answer, and what to avoid.
  MATTERS = {
    tremor: %w[forgiving finger_applied chunky one_step away_from_eyes],
    pinch: %w[no_pinch_grip opens_one_handed pump flip_cap easy_cap chunky big_handle],
    one_hand: %w[opens_one_handed pump flip_cap one_step],
    fatigue: %w[one_step finger_applied pump],
    near_vision: %w[away_from_eyes one_step forgiving]
  }.freeze
  AVOID = {
    tremor: [ "Thin liquid liners and fine brushes", "Liquid lipsticks that set fast" ],
    pinch: [ "Twist caps and screw tops", "Slim pencils and thin brushes", "Compacts with a clasp" ],
    one_hand: [ "Twist caps and screw tops", "Palettes you have to hold while you use them" ],
    fatigue: [ "Looks with many steps", "Products you build up in layers" ],
    near_vision: [ "Steps right at the lash line", "Palettes with lots of small shades" ]
  }.freeze

  class Invalid < ArgumentError; end

  # A product in the demo catalogue.
  CatalogueProduct = Data.define(:key, :name, :maker, :ease)

  attr_reader :format, :closure, :grip, :step

  def self.catalogue
    @catalogue ||= YAML.load_file(Rails.root.join("config/blendolo/products.yml")).map do |key, attributes|
      CatalogueProduct.new(key:, name: attributes.fetch("name"), maker: attributes.fetch("maker"),
        ease: new(format: attributes.fetch("format"), closure: attributes.fetch("closure"),
          grip: attributes.fetch("grip"), step: attributes.fetch("step")))
    end.freeze
  end

  def self.for_step(step_id)
    catalogue.select { |product| product.ease.step&.id == step_id.to_s }
  end

  # Tags that make a product easier for these hands (answers above "no"), in the order they matter most.
  def self.tags_that_matter(profile)
    answered(profile).flat_map { |question| MATTERS.fetch(question) }.uniq
  end

  def self.avoid(profile)
    answered(profile).flat_map { |question| AVOID.fetch(question) }.uniq
  end

  def self.answered(profile)
    MATTERS.keys.select { |question| profile.public_send(question).to_i.positive? }
  end

  def initialize(format:, closure:, grip:, step: nil)
    @format = check(format, FORMATS, "format")
    @closure = check(closure, CLOSURES.keys, "closure")
    @grip = check(grip, GRIPS, "grip")
    @step = step.presence && Ease::StepCatalogue.fetch(step)
  rescue Ease::StepCatalogue::UnknownStep
    raise Invalid, "step must be one of the step ids in our catalogue"
  end

  # Ease tags, as keys of Ease::Words::TAGS.
  def tags
    tags = []
    tags << "pump" if closure == "pump" || format == "pump"
    tags << "flip_cap" if closure == "flip_cap"
    tags << "easy_cap" if closure == "pull_cap"
    tags << "opens_one_handed" if CLOSURES.fetch(closure).zero?
    tags << "chunky" if grip == "chunky"
    tags << "big_handle" if grip == "big_handle"
    tags << "no_pinch_grip" if %w[chunky big_handle].include?(grip) && CLOSURES.fetch(closure) < 2
    tags << "finger_applied" if %w[cream balm crayon stick].include?(format) && step&.ease_tags&.include?("finger_applied")
    tags << "forgiving" if %w[cream balm crayon gel].include?(format) || step&.ease_tags&.include?("forgiving")
    tags << "away_from_eyes" if step ? step.ease_tags.include?("away_from_eyes") : false
    tags.uniq
  end

  # The step's dimensions with how this product opens (O) and is held (G): a slim one is the hardest grip, a chunky
  # one or a big handle one step easier than the step's own tool.
  def dims
    base = step&.dims || NEUTRAL
    grip_dim =
      case grip
      when "slim" then 3
      when "standard" then base.fetch(:G)
      else [ base.fetch(:G) - 1, 0 ].max
      end
    base.merge(O: CLOSURES.fetch(closure), G: grip_dim)
  end

  def score(profile)
    Ease::Scorer.step(scored_step, profile)
  end

  # { "steady" => { score:, words: }, "tremor" => ..., ... }
  def ease_by_profile
    PROFILES.transform_values do |answers|
      score = score(Ease::HandProfile.new(**answers))
      { score:, words: Ease::Words.for(score) }
    end
  end

  # What GET /api/ease_tags answers.
  def as_api_json
    {
      product: { format:, closure:, grip:, step: step&.id },
      tags: tags.map { |tag| { key: tag, label: Ease::Words.tag(tag) } },
      ease: ease_by_profile,
      note: "Ease is Blendolo's own guide from 0 (hard) to 100 (easy), not a clinical measure."
    }
  end

  private
    def scored_step
      base = step || Ease::StepCatalogue.fixup
      base.with(dims: dims)
    end

    def check(value, allowed, name)
      value.to_s.presence_in(allowed) || raise(Invalid, "#{name} must be one of #{allowed.join(", ")}")
    end
end
