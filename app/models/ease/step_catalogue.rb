module Ease
  # Every step Blendolo knows, read once from config/blendolo/steps.yml.
  module StepCatalogue
    PATH = Rails.root.join("config/blendolo/steps.yml")
    NO_SWAP = "none".freeze

    class UnknownStep < KeyError; end

    class << self
      def all
        by_id.values
      end

      def ids
        by_id.keys
      end

      def fetch(id)
        by_id.fetch(id.to_s) { raise UnknownStep, "No step called #{id.inspect} in #{PATH.basename}" }
      end

      def key?(id)
        by_id.key?(id.to_s)
      end

      def fixup
        fetch(Step::FIXUP)
      end

      private
        def by_id
          @by_id ||= YAML.load_file(PATH).to_h { |id, attributes| [ id, build(id, attributes) ] }.freeze
        end

        def build(id, attributes)
          swap = attributes.fetch("swap")

          Step.new(
            id: id,
            number: attributes["number"],
            name: attributes.fetch("name"),
            instruction: attributes.fetch("instruction"),
            dims: attributes.fetch("dims").transform_keys(&:to_sym).freeze,
            swap: (swap unless swap == NO_SWAP),
            swap_why: attributes["swap_why"],
            why_easier: attributes["why_easier"],
            tips: Array(attributes["tips"]).freeze,
            product_type: attributes.fetch("product_type"),
            ease_tags: Array(attributes["ease_tags"]).freeze,
            effect: attributes["effect"]&.deep_symbolize_keys&.freeze
          )
        end
    end
  end
end
