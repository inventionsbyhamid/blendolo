# Stand-ins for code lane A (backend) is building, so the controllers can be tested before it merges. Each one
# loads only while the real file is missing, and switches itself off once the real code is on this branch:
# Render#request! (ProviderTracked), which asks the appearance provider for a render, and Examples.

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
