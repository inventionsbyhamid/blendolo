module RendersHelper
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
    "out_of_units" => "We've made all the previews we can today. Please come back tomorrow.",
    "daily_cap" => "We've made all the previews we can today. Please come back tomorrow.",
    "floor" => "We've made all the previews we can today. Please come back tomorrow.",
    "kit_cap" => "You've made all the previews this kit can make. Your routine and step cards still work.",
    "timeout" => "That took too long on our side. Try again.",
    "provider_error" => "Something went wrong on our side. Try again.",
    "example" => "This preview isn't stored for the example person. Start your own kit to see it on you."
  }.freeze
  PHOTO_REASONS = %w[no_face many_faces face_too_small eyes_closed bad_pose bad_image too_large].freeze

  def render_failure_message(render)
    FAILURES.fetch(render.failure_reason.to_s, FAILURES["provider_error"])
  end

  # The photo is the problem: offer to take it again.
  def render_failure_needs_photo?(render)
    PHOTO_REASONS.include?(render.failure_reason.to_s)
  end

  # A resized copy: makeup results arrive as large PNGs.
  def render_image(render, alt:)
    image_tag render.result.variant(resize_to_limit: [ 900, 900 ]), alt:, class: "render__image"
  end
end
