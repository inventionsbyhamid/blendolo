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
    "timeout" => "That took too long on our side. Try again.",
    "provider_error" => "Something went wrong on our side. Try again.",
    "example" => "This preview isn't stored for the example person. Start your own kit to see it on you.",
    "no_credits" => CreditsHelper::OUT_OF_CREDITS,
    "sign_in" => CreditsHelper::SIGN_IN
  }.freeze
  PHOTO_REASONS = %w[no_face many_faces face_too_small eyes_closed bad_pose bad_image too_large].freeze
  # Failures on our side or the provider's that another go can fix. A pause is asked again too: Render#request! checks
  # the unit guard again, and a refusal costs nothing.
  # kit_cap: a per-kit limit that no longer exists (kits pay with credits); previews it held are asked again.
  TRY_AGAIN = %w[timeout provider_error rate_limited out_of_units daily_cap floor kit_cap].freeze

  def render_failure_message(render)
    FAILURES.fetch(render.failure_reason.to_s, FAILURES["provider_error"])
  end

  # The photo is the problem: offer to take it again.
  def render_failure_needs_photo?(render)
    PHOTO_REASONS.include?(render.failure_reason.to_s)
  end

  # A resized copy (makeup results arrive as large PNGs), served from our own origin.
  def render_image(render, alt:)
    proxied_image_tag(render.result, 900, alt:, class: "render__image")
  end

  # An <img> of proxied_image_path with the resized picture's width and height, once the original has been measured
  # (Active Storage analyses it after upload), so the page keeps the picture's place while it loads instead of
  # jumping down.
  def proxied_image_tag(attachment, size, **options)
    width, height = attachment.blob.metadata.values_at(:width, :height).map(&:to_i)
    if width.positive? && height.positive?
      scale = [ size.fdiv(width), size.fdiv(height), 1 ].min
      options = { width: (width * scale).round, height: (height * scale).round, **options }
    end
    image_tag proxied_image_path(attachment, size), **options
  end

  # Image links stay the same for this long, so a picture seen again (the next step card, back to a look) comes from
  # the browser's cache instead of the network. A link made at any moment still works for 50 to 60 minutes: never
  # longer than the hour image links get (ActiveStorage.urls_expire_in).
  IMAGE_LINK_STEP = 10.minutes

  # An attachment resized to fit size x size, as a same-origin path through the Active Storage proxy.
  def proxied_image_path(attachment, size)
    rails_storage_proxy_path(ProxiedImage.variant(attachment, size), expires_at: image_link_expiry)
  end

  # When the image links made now stop working: the start of this IMAGE_LINK_STEP, plus the hour.
  def image_link_expiry(now = Time.current)
    step = IMAGE_LINK_STEP.to_i
    Time.at(now.to_i - (now.to_i % step)).utc + ActiveStorage.urls_expire_in
  end
end
