module Looks
  # One step of a look: which step, and the colour and intensity this look wants for it.
  # colour is "#RRGGBB" or a list for multi-colour patterns; nil uses the step's default.
  # intensity is 0..100; nil uses the step's default.
  class LookStep < Data.define(:step_id, :colour, :intensity)
    def initialize(step_id:, colour: nil, intensity: nil)
      super(step_id: step_id.to_s, colour: normalise(colour), intensity:)
    end

    # Accepts a LookStep, an Ease::Step, a step id, or a Hash such as { "step" => "tinted_balm", "colour" => "#A84452" }
    # (keys step, step_id or id; string or symbol keys), so a stored routine reads back the same way.
    def self.wrap(value)
      case value
      when LookStep then value
      when Ease::Step then new(step_id: value.id)
      when String, Symbol then new(step_id: value)
      when Hash
        attributes = value.symbolize_keys
        new(step_id: attributes[:step_id] || attributes[:step] || attributes.fetch(:id),
            colour: attributes[:colour], intensity: attributes[:intensity])
      else raise ArgumentError, "Can't read a look step from #{value.inspect}"
      end
    end

    def step
      Ease::StepCatalogue.fetch(step_id)
    end

    private
      def normalise(colour)
        colour.is_a?(Array) ? colour.map { |hex| hex.to_s.upcase }.freeze : colour&.to_s&.upcase
      end
  end
end
