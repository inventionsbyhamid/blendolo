# The example people from config/blendolo/examples.yml, and the kits visitors see them in.
#
# An example kit is read-only (Kit refuses changes to it) and shared by every visitor of that example:
# Examples.kit_for(key) returns the newest living kit built from the current version of that example (its yml entry
# and the files it names, see #digest), or builds a new one from the stored photos and finished previews. So new
# example photos or previews show up on the next visit after a deploy; older kits expire on their own. Example kits
# never call the provider (UnitGuard refuses them). bin/rails examples:rebuild builds fresh kits for everyone.
module Examples
  PATH = Rails.root.join("config/blendolo/examples.yml")

  class UnknownExample < KeyError; end

  Person = Data.define(:key, :name, :blurb, :hands, :hands_today, :chosen_look, :photos, :renders, :digest)

  class << self
    def all = people.values
    def keys = people.keys
    def photo_label = config.fetch("photo_label")

    def fetch(key)
      people.fetch(key.to_s) { raise UnknownExample, "No example called #{key.inspect} in #{PATH.basename}" }
    end

    def kit_for(key, now: Time.current)
      person = fetch(key)
      Kit.example.where(example_key: person.key, example_digest: person.digest).where.not(purge_after: ..now)
        .order(created_at: :desc).first || build_kit(person, now)
    end

    # A new kit for the example even if a current one lives (the newest wins in kit_for).
    def rebuild!(key, now: Time.current)
      build_kit(fetch(key), now)
    end

    private
      def build_kit(person, now)
        Kit.transaction do
          kit = Kit.new(path: :example, example_key: person.key, example_digest: person.digest, consented_at: now,
            chosen_look_key: person.chosen_look, hands_today: person.hands_today, **person.hands)
          kit.building_example = true
          kit.save!
          photos = person.photos.to_h do |kind, file|
            [ kind, kit.photos.create!(kind:, source: "example", sha256: Digest::SHA256.file(file_path(file)).hexdigest,
              image: attachable(file)) ]
          end
          person.renders.each do |render|
            kit.renders.create!(kind: render.fetch("kind"), look_key: render["look"], status: :done,
              photo: photos.fetch("today"), reference_photo: (photos.fetch("reference") if render["kind"] == "transfer"),
              result: attachable(render.fetch("file")))
          end
          kit.building_example = false
          kit
        end
      end

      def attachable(file)
        path = file_path(file)
        { io: StringIO.new(path.binread), filename: path.basename.to_s, content_type: Marcel::MimeType.for(path) }
      end

      def file_path(file) = Rails.root.join(config.fetch("images_dir"), file)

      # Changes whenever the person's yml entry or any file it names changes.
      def digest_for(entry)
        files = entry.fetch("photos").values + entry.fetch("renders").map { |render| render.fetch("file") }
        Digest::SHA256.hexdigest(JSON.generate([ entry, files.sort.map { |file| Digest::SHA256.file(file_path(file)).hexdigest } ]))
      end

      def people
        @people ||= config.fetch("people").to_h do |key, person|
          [ key, Person.new(
            key:, name: person.fetch("name"), blurb: person.fetch("blurb"),
            hands: person.fetch("hands").transform_keys(&:to_sym), hands_today: person.fetch("hands_today"),
            chosen_look: person.fetch("chosen_look"), photos: person.fetch("photos"), renders: person.fetch("renders"),
            digest: digest_for(person)
          ) ]
        end.freeze
      end

      def config
        @config ||= YAML.load_file(PATH)
      end
  end
end
