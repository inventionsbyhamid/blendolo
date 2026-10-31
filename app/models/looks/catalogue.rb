module Looks
  # The looks people can pick from, read once from config/blendolo/looks.yml.
  module Catalogue
    PATH = Rails.root.join("config/blendolo/looks.yml")

    class UnknownLook < KeyError; end

    class << self
      def all
        by_key.values
      end

      def keys
        by_key.keys
      end

      def fetch(key)
        by_key.fetch(key.to_s) { raise UnknownLook, "No look called #{key.inspect} in #{PATH.basename}" }
      end

      def key?(key)
        by_key.key?(key.to_s)
      end

      private
        def by_key
          @by_key ||= YAML.load_file(PATH).to_h { |key, attributes| [ key, build(key, attributes) ] }.freeze
        end

        def build(key, attributes)
          Look.new(
            key: key,
            name: attributes.fetch("name"),
            blurb: attributes.fetch("blurb"),
            steps: attributes.fetch("steps").map { |step| LookStep.wrap(step) }.freeze,
            thumbnail: attributes.fetch("thumbnail")
          )
        end
    end
  end
end
