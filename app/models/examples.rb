# The example people from config/blendolo/examples.yml, and the kits visitors see them in.
#
# An example kit is read-only (Kit refuses changes to it) and shared by every visitor of that example:
# Examples.kit_for(key) returns the newest living kit built from the current version of that example (its yml entry
# and the files it names, see #digest), or builds a new one from the stored photos and finished previews. So new
# example photos or previews show up on the next visit after a deploy; older kits expire on their own. Example kits
# never call the provider (UnitGuard refuses them). Each has a share link, to show what a helper sees.
# bin/rails examples:rebuild builds fresh kits for everyone.
module Examples
  PATH = Rails.root.join("config/blendolo/examples.yml")

  class UnknownExample < KeyError; end

  # The sizes the example pages show (RendersHelper#proxied_image_path), made in the background when a kit is built.
  VARIANT_SIZES = [ 900, 600 ].freeze

  Person = Data.define(:key, :name, :blurb, :hands, :hands_today, :chosen_look, :photos, :renders, :signature, :digest)

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

    # Makes the picture sizes the example pages show, so the first visit to a new example kit doesn't wait for them.
    def prepare_variants(kit)
      attachments = kit.photos.map(&:image) + kit.renders.map(&:result)
      attachments.select(&:attached?).product(VARIANT_SIZES).each do |attachment, size|
        ProxiedImage.variant(attachment, size).processed
      end
    end

    # A new kit for the example even if a current one lives (the newest wins in kit_for).
    def rebuild!(key, now: Time.current)
      build_kit(fetch(key), now)
    end

    private
      def build_kit(person, now)
        build_records(person, now).tap { |kit| PrepareExampleVariantsJob.perform_later(kit) }
      end

      def build_records(person, now)
        Kit.transaction do
          kit = Kit.new(path: :example, example_key: person.key, example_digest: person.digest, consented_at: now,
            chosen_look_key: person.chosen_look, hands_today: person.hands_today, **person.hands)
          kit.building_example = true
          kit.save!
          photos = person.photos.to_h do |kind, file|
            sampled = kind == "reference" ? person.signature.fetch("colours") : {}
            [ kind, kit.photos.create!(kind:, source: "example", sha256: Digest::SHA256.file(file_path(file)).hexdigest,
              sampled:, image: attachable(file)) ]
          end
          person.renders.each do |render|
            kit.renders.create!(kind: render.fetch("kind"), look_key: render["look"], status: :done,
              photo: photos.fetch("today"), reference_photo: (photos.fetch("reference") if render["kind"] == "transfer"),
              result: attachable(render.fetch("file")))
          end
          # "See what a helper sees": a read-only link with the routine and photos, for as long as the kit lives.
          kit.shares.create!(audience: :helper, scope: :routine_and_photos, expires_at: kit.purge_after)
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
            signature: person.fetch("signature"), digest: digest_for(person)
          ) ]
        end.freeze
      end

      def config
        @config ||= YAML.load_file(PATH)
      end
  end
end
