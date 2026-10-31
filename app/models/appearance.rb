# Makeup previews on a person's photo, behind one vendor-neutral interface (Appearance::Provider). App code talks to
# Appearance.provider and its value types only; the vendor adapter lives in Appearance::Youcam and never leaks out.
module Appearance
  OPERATIONS = %i[makeup transfer].freeze

  # Why a preview failed, in our words. The UI turns each into a hint ("Face the camera", "Try a closer photo").
  REASONS = %i[
    no_face many_faces face_too_small eyes_closed bad_pose bad_image too_large
    rate_limited out_of_units timeout provider_error
  ].freeze

  class << self
    attr_writer :provider

    def provider
      @provider ||= build_provider
    end

    # APPEARANCE_PROVIDER=youcam calls the live API; anything else (development, tests) replays recorded results.
    def build_provider(env = ENV)
      if env["APPEARANCE_PROVIDER"].to_s.strip == "youcam"
        Youcam::Provider.from_env(env)
      else
        FakeProvider.new
      end
    end
  end
end
