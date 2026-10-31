# Stand-ins for code other lanes are building, so the controllers can be tested before it merges. Each one loads
# only while the real file is missing, and switches itself off once the real code is on this branch.
#
#   Lane C (engine): Ease::* and Looks::* as their interfaces are written in the plan and on the engine branch.
#   Lane A (backend): Render#request! (ProviderTracked), which asks the appearance provider for a render.
#
# The stand-in data uses real step ids and look keys (red_lip, everyday_fresh), so tests keep passing on the real
# engine.

unless Rails.root.join("app/models/ease/step_catalogue.rb").exist?
  module Ease
    class Step < Data.define(:id, :name, :instruction, :dims, :swap, :swap_why, :why_easier, :tips, :product_type,
                             :ease_tags, :effect)
      FIXUP = "fixup".freeze
      def precision = dims.fetch(:P)
      def fixup? = id == FIXUP
      def skip? = swap == "skip"
      def swap_id = (swap unless skip?)
    end

    class HandProfile < Data.define(:tremor, :pinch, :one_hand, :fatigue, :near_vision)
      def initialize(tremor: 0, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0) = super
      def weights = { P: 1 + tremor, E: 1 + near_vision, G: 1 + pinch, H: 1 + (one_hand.zero? ? 0 : 2), T: 1 + fatigue, F: 1 + tremor, O: pinch }
    end

    module StepCatalogue
      STEPS = {
        "liquid_foundation_brush" => [ "Liquid foundation, tube and brush", { P: 0, E: 0, G: 1, H: 1, T: 2, F: 0, O: 1 }, "tinted_moisturiser_pump", "Foundation", { category: "foundation", colour: "#C99A7A", intensity: 50 } ],
        "tinted_moisturiser_pump" => [ "Tinted moisturiser from a pump", { P: 0, E: 0, G: 0, H: 0, T: 1, F: 0, O: 0 }, nil, "Tinted moisturiser", { category: "foundation", colour: "#C99A7A", intensity: 25 } ],
        "liquid_liner_wing" => [ "Winged liquid liner", { P: 3, E: 2, G: 2, H: 1, T: 2, F: 3, O: 1 }, "smudged_pencil_liner", "Liquid liner", { category: "eye_liner", colour: "#1A1A1A", intensity: 90, pattern: "wing" } ],
        "smudged_pencil_liner" => [ "Smudged pencil line", { P: 1, E: 2, G: 1, H: 0, T: 1, F: 0, O: 0 }, nil, "Chunky pencil", { category: "eye_liner", colour: "#1A1A1A", intensity: 88, pattern: "smoke" } ],
        "mascara_upper" => [ "Mascara, upper lashes", { P: 2, E: 3, G: 2, H: 0, T: 1, F: 2, O: 1 }, nil, "Mascara", { category: "eyelashes", colour: "#000000", intensity: 85 } ],
        "liquid_matte_lipstick" => [ "Liquid matte lipstick", { P: 3, E: 0, G: 2, H: 1, T: 1, F: 3, O: 1 }, "tinted_balm", "Liquid lipstick", { category: "lip_color", colour: "#B0182A", intensity: 85, texture: "matte" } ],
        "tinted_balm" => [ "Tinted balm", { P: 1, E: 0, G: 0, H: 0, T: 0, F: 0, O: 0 }, nil, "Tinted balm", { category: "lip_color", colour: "#B0182A", intensity: 45, texture: "sheer" } ],
        "powder_blush_brush" => [ "Powder blush, small brush", { P: 1, E: 0, G: 2, H: 1, T: 1, F: 1, O: 1 }, "cream_blush_fingers", "Powder blush", { category: "blush", colour: "#E59A7A", intensity: 40 } ],
        "cream_blush_fingers" => [ "Cream blush with fingers", { P: 0, E: 0, G: 0, H: 0, T: 0, F: 0, O: 0 }, nil, "Cream blush stick", { category: "blush", colour: "#E59A7A", intensity: 35 } ],
        "fixup" => [ "Tidy up", { P: 0, E: 1, G: 1, H: 0, T: 0, F: 0, O: 0 }, nil, "Cotton buds and micellar water", nil ]
      }.freeze

      def self.fetch(id)
        name, dims, swap, product_type, effect = STEPS.fetch(id.to_s)
        Step.new(id: id.to_s, name:, instruction: "#{name}.", dims:, swap:, swap_why: ("Easier for shaky hands." if swap),
          why_easier: "Kind to hands.", tips: [ "Rest your elbow on the table." ], product_type:,
          ease_tags: [ "forgiving" ], effect:)
      end

      def self.fixup = fetch(Step::FIXUP)
    end

    module Scorer
      module_function

      def step(step, profile)
        weights = profile.weights
        sum = step.dims.sum { |dimension, value| weights.fetch(dimension) * value }
        max = weights.values.sum * 3
        (100 * (1 - sum.to_r / max)).round
      end

      def look(steps, profile)
        hardest = steps.min_by { |step| step(step, profile) }
        { ease: hardest ? step(hardest, profile) : 100, hardest_step: hardest }
      end
    end

    module Words
      EASY = 80
      TAGS = { "forgiving" => "Blends away wobbles" }.freeze
      module_function

      def for(score)
        if score >= 80 then "Easy" elsif score >= 60 then "Some care" elsif score >= 40 then "Tricky" else "Hard" end
      end

      def tag(tag) = TAGS.fetch(tag.to_s, tag.to_s.humanize)
    end

    module RoutineOrder
      module_function

      def order(steps)
        steps = steps.reject(&:fixup?).uniq(&:id)
        precise, rest = steps.partition { |step| step.precision >= 2 }
        precise.sort_by { |step| -step.precision } + rest + [ StepCatalogue.fixup ]
      end
    end

    class SwapPlanner
      def initialize(profile) = @profile = profile

      def plan(steps)
        swaps = []
        unswappable = []
        planned = steps.map do |step|
          ease = Scorer.step(step, @profile)
          next step if ease >= Words::EASY

          easier = StepCatalogue.fetch(step.swap_id) if step.swap_id
          if easier && Scorer.step(easier, @profile) > ease
            swaps << { from: step, to: easier, why: step.swap_why }
            easier
          else
            unswappable << step
            step
          end
        end
        { steps: planned.uniq(&:id), swaps:, unswappable: }
      end
    end
  end

  module Looks
    class LookStep < Data.define(:step_id, :colour, :intensity)
      def initialize(step_id:, colour: nil, intensity: nil) = super(step_id: step_id.to_s, colour:, intensity:)

      def self.wrap(value)
        case value
        when LookStep then value
        when Ease::Step then new(step_id: value.id)
        when String, Symbol then new(step_id: value)
        when Hash
          attributes = value.symbolize_keys
          new(step_id: attributes[:step_id] || attributes[:step] || attributes.fetch(:id), colour: attributes[:colour],
            intensity: attributes[:intensity])
        end
      end

      def step = Ease::StepCatalogue.fetch(step_id)
    end

    class Look < Data.define(:key, :name, :blurb, :steps, :thumbnail)
      def self.plan(look_steps, profile)
        Ease::SwapPlanner.new(profile).plan(look_steps.map { |step| LookStep.wrap(step).step })
      end

      def self.easy_steps(look_steps, profile)
        look_steps = look_steps.map { |step| LookStep.wrap(step) }
        swaps = plan(look_steps, profile)[:swaps].index_by { |swap| swap[:from].id }
        look_steps.filter_map do |look_step|
          swap = swaps[look_step.step_id]
          next look_step unless swap
          LookStep.new(step_id: swap[:to].id, colour: look_step.colour) if swap[:to]
        end
      end

      def ease_steps = steps.map(&:step)
      def plan(profile) = self.class.plan(steps, profile)
      def easy_steps(profile) = self.class.easy_steps(steps, profile)
    end

    module Catalogue
      class UnknownLook < KeyError; end

      LOOKS = {
        "everyday_fresh" => [ "Everyday fresh", [ { step: "liquid_foundation_brush" }, { step: "powder_blush_brush", colour: "#E59A7A" }, { step: "tinted_balm", colour: "#B5776B" } ] ],
        "red_lip" => [ "The red lip", [ { step: "liquid_foundation_brush" }, { step: "liquid_liner_wing", intensity: 90 }, { step: "mascara_upper" }, { step: "liquid_matte_lipstick", colour: "#B0182A" } ] ],
        # These two swap places when pinching is hard and one hand does the work, as real looks do.
        "barely_there" => [ "Barely there", [ { step: "tinted_balm", colour: "#B5776B" }, { step: "liquid_foundation_brush" } ] ],
        "rosy_glow" => [ "Rosy glow", [ { step: "cream_blush_fingers", colour: "#E59A7A" }, { step: "smudged_pencil_liner" } ] ]
      }.freeze

      def self.all = LOOKS.keys.map { |key| fetch(key) }

      def self.fetch(key)
        name, steps = LOOKS.fetch(key.to_s) { raise UnknownLook, "No look called #{key.inspect}" }
        Look.new(key: key.to_s, name:, blurb: "#{name}, made easier.", steps: steps.map { |step| LookStep.wrap(step) },
          thumbnail: "looks/#{key}.jpg")
      end
    end

    module EffectsBuilder
      module_function

      def build(steps, skin: nil)
        steps.map { |step| LookStep.wrap(step) }.filter_map do |look_step|
          effect = look_step.step.effect or next
          colour = look_step.colour || (skin if effect[:category] == "foundation") || effect[:colour]
          { category: effect[:category], colour:, intensity: look_step.intensity || effect[:intensity],
            texture: effect[:texture], pattern: effect[:pattern], mode: nil }
        end.uniq { |effect| effect[:category] }
      end

      def signature(sampled:, liner:, lips:)
        liner_step = { "winged" => "liquid_liner_wing", "thin" => "liquid_liner_wing", "smudged" => "smudged_pencil_liner", "none" => nil }.fetch(liner.to_s) { raise ArgumentError }
        lip_step = { "matte" => "liquid_matte_lipstick", "shiny" => "tinted_balm", "sheer" => "tinted_balm" }.fetch(lips.to_s) { raise ArgumentError }
        sampled = sampled.to_h.stringify_keys
        [
          ([ "powder_blush_brush", sampled["cheeks"] ] if sampled["cheeks"]),
          ([ liner_step, nil ] if liner_step),
          ([ lip_step, sampled["lips"] ] if sampled["lips"])
        ].compact.map { |step_id, colour| LookStep.new(step_id:, colour:) }
      end
    end
  end
end

unless Rails.root.join("app/models/concerns/provider_tracked.rb").exist?
  Render.class_eval do
    # Stand-in for ProviderTracked#request!: the real one keys the call, checks the cache and the unit guard, and
    # queues the provider jobs. Here it only marks the render as queued.
    def request!
      update!(status: :pending)
      :queued
    end
  end
end

unless Rails.root.join("app/models/examples.rb").exist?
  # Stand-in for lane A's Examples (config/blendolo/examples.yml): one shared, read-only kit per example person,
  # built on demand with a photo, an old photo and finished previews of their chosen look.
  module Examples
    class UnknownExample < KeyError; end

    Person = Data.define(:key, :name, :blurb, :hands, :hands_today, :chosen_look)
    PEOPLE = {
      "rosa" => Person.new(key: "rosa", name: "Rosa", blurb: "Rosa is 74 and has Parkinson's.",
        hands: { tremor: 2, pinch: 1, one_hand: 0, fatigue: 1, near_vision: 1 }, hands_today: 2, chosen_look: "red_lip"),
      "june" => Person.new(key: "june", name: "June", blurb: "June is 66. Arthritis makes small caps hard to grip.",
        hands: { tremor: 0, pinch: 2, one_hand: 0, fatigue: 1, near_vision: 1 }, hands_today: 1, chosen_look: "everyday_fresh"),
      "amara" => Person.new(key: "amara", name: "Amara", blurb: "Amara is 55 and mostly uses her right hand.",
        hands: { tremor: 0, pinch: 1, one_hand: 2, fatigue: 2, near_vision: 0 }, hands_today: 1, chosen_look: "red_lip")
    }.freeze

    def self.all = PEOPLE.values
    def self.keys = PEOPLE.keys
    def self.photo_label = "AI generated photo"
    def self.fetch(key) = PEOPLE.fetch(key.to_s) { raise UnknownExample, "No example called #{key.inspect}" }

    def self.kit_for(key, now: Time.current)
      person = fetch(key)
      Kit.example.where(example_key: person.key).where.not(purge_after: ..now).order(created_at: :desc).first ||
        build_kit(person, now)
    end

    def self.build_kit(person, now)
      image = -> { { io: Rails.root.join("test/fixtures/files/face.jpg").open, filename: "face.jpg", content_type: "image/jpeg" } }
      Kit.transaction do
        kit = Kit.create!(path: :example, example_key: person.key, consented_at: now, chosen_look_key: person.chosen_look,
          hands_today: person.hands_today, **person.hands)
        today = kit.photos.create!(kind: :today, source: "example", sha256: SecureRandom.hex(32), image: image.call)
        reference = kit.photos.create!(kind: :reference, source: "example", sha256: SecureRandom.hex(32), image: image.call)
        [ [ :classic, person.chosen_look, nil ], [ :easy, person.chosen_look, nil ], [ :transfer, nil, reference ],
          [ :easy, "signature", nil ] ].each do |kind, look_key, reference_photo|
          kit.renders.create!(kind:, look_key:, reference_photo:, photo: today, status: :done, result: image.call)
        end
        kit
      end
    end
  end
end
