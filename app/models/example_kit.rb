# Example people (Rosa, June, Amara): seeded kits with a photo and stored previews. A visitor gets their own copy,
# so their taps never change what the next visitor sees, and a copy only ever shows stored previews: example kits
# never call the appearance provider. Photos and previews share the seeded files; nothing is uploaded again.
module ExampleKit
  NAMES = { "rosa" => "Rosa", "june" => "June", "amara" => "Amara" }.freeze
  KEYS = NAMES.keys.freeze
  COPY_RETENTION_DAYS = 7

  module_function

  def name_for(key)
    NAMES.fetch(key.to_s, "Example")
  end

  # The seeded kit for an example person: the first kit made with that key. Copies come later.
  def template(key)
    Kit.example.where(example_key: key.to_s).order(:id).first
  end

  # A fresh copy of the example person's kit for one visitor, or nil when the example isn't seeded yet.
  def start!(key)
    template = template(key) or return

    Kit.transaction do
      Kit.create!(path: :example, example_key: template.example_key, retention_days: COPY_RETENTION_DAYS,
        consented_at: Time.current, hands_today: template.hands_today, chosen_look_key: template.chosen_look_key,
        routine: template.routine, **template.slice(*Kit::HAND_QUESTIONS).symbolize_keys).tap do |kit|
        template.photos.each { |photo| copy_photo(photo, kit) }
      end
    end
  end

  # A stored preview from the example person's seeded kit with the same look, kind and effects, copied into the
  # visitor's kit (same file, on the visitor's copy of the photo), or nil when none was stored.
  def stored_render(kit, attributes)
    template = template(kit.example_key) or return
    wanted = attributes.slice(:look_key, :kind, :effects)
    source = Previews.matching(template.renders.done, wanted).joins(:result_attachment).order(:id).last
    return unless source

    kit.renders.create!(attributes.merge(status: :done, result: source.result.blob))
  end

  def copy_photo(photo, kit)
    kit.photos.create!(kind: photo.kind, source: "example", sha256: photo.sha256, width: photo.width,
      height: photo.height, sampled: photo.sampled, image: photo.image.blob)
  end
end
