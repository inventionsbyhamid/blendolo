module RendersHelper
  # Live previews held by the app's own limits (today's units, the balance we keep back, the provider's balance).
  PAUSED = "Live previews are paused for now. Try again later, or see an example person.".freeze
  # What to say when a preview can't be made, by Render#failure_reason, and what to do next.
  FAILURES = {
    "no_face" => "We couldn't find a face in the photo.",
    "many_faces" => "There's more than one face in the photo. Please use a photo of just you.",
    "face_too_small" => "Your face is too small in the photo. Come a little closer.",
    "eyes_closed" => "Your eyes look closed in the photo. Liner needs open eyes.",
    "bad_pose" => "Your head is turned in the photo. Please face the camera.",
    "bad_image" => "We couldn't read that photo.",
    "too_large" => "That photo is too big for us.",
    "rate_limited" => "Lots of people are trying looks right now. Try again in a minute.",
    "out_of_units" => PAUSED,
    "daily_cap" => PAUSED,
    "floor" => PAUSED,
    "kit_cap" => "You've made all the previews this kit can make. Your routine and step cards still work.",
    "timeout" => "That took too long on our side. Try again.",
    "provider_error" => "Something went wrong on our side. Try again.",
    "example" => "This preview isn't stored for the example person. Start your own kit to see it on you."
  }.freeze
  PHOTO_REASONS = %w[no_face many_faces face_too_small eyes_closed bad_pose bad_image too_large].freeze
  # Failures on our side or the provider's that another go can fix. A pause is asked again too: Render#request! checks
  # the unit guard again, and a refusal costs nothing.
  TRY_AGAIN = %w[timeout provider_error rate_limited out_of_units daily_cap floor].freeze

  def render_failure_message(render)
    FAILURES.fetch(render.failure_reason.to_s, FAILURES["provider_error"])
  end

  # The photo is the problem: offer to take it again.
  def render_failure_needs_photo?(render)
    PHOTO_REASONS.include?(render.failure_reason.to_s)
  end

  # A resized copy (makeup results arrive as large PNGs), served from our own origin.
  def render_image(render, alt:)
    image_tag proxied_image_path(render.result, 900), alt:, class: "render__image"
  end

  # An attachment resized to fit size x size, as a same-origin path through the Active Storage proxy.
  def proxied_image_path(attachment, size)
    rails_storage_proxy_path(ProxiedImage.variant(attachment, size))
  end
end
