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
        # Deeply frozen (Ractor.make_shareable freezes every nested hash, array and string), so no caller can
        # change the shared catalogue by accident.
        def by_id
          @by_id ||= Ractor.make_shareable(YAML.load_file(PATH).to_h { |id, attributes| [ id, build(id, attributes) ] })
        end

        def build(id, attributes)
          layer = attributes.fetch("layer")
          raise ArgumentError, "#{id}: unknown layer #{layer.inspect}" unless Step::LAYERS.include?(layer)

          Step.new(
            id: id,
            number: attributes["number"],
            name: attributes.fetch("name"),
            layer: layer,
            instruction: attributes.fetch("instruction"),
            dims: attributes.fetch("dims").transform_keys(&:to_sym),
            swaps: candidates(id, attributes),
            no_swap_why: attributes["no_swap_why"],
            why_easier: attributes["why_easier"],
            tips: Array(attributes["tips"]),
            product_type: attributes.fetch("product_type"),
            ease_tags: Array(attributes["ease_tags"]),
            effect: attributes["effect"]&.deep_symbolize_keys
          )
        end

        # swaps: a list of { to:, why: } (or ids, which share swap_why), or the one-item form swap: + swap_why:.
        def candidates(id, attributes)
          list =
            if attributes.key?("swaps")
              attributes.fetch("swaps").map do |candidate|
                candidate = { "to" => candidate, "why" => attributes["swap_why"] } if candidate.is_a?(String)
                Step::Candidate.new(to: candidate.fetch("to"), why: candidate.fetch("why"))
              end
            else
              swap = attributes.fetch("swap")
              swap == NO_SWAP ? [] : [ Step::Candidate.new(to: swap, why: attributes["swap_why"]) ]
            end
          raise ArgumentError, "#{id}: skip can't share swaps with other steps" if list.size > 1 && list.any? { |c| c.to == Step::SKIP }

          list
        end
    end
  end
end
