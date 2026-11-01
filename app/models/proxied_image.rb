# The resized copy of a photo or preview that pages show (RendersHelper#proxied_image_path), and that Examples makes
# ahead for example kits. WebP: every browser Blendolo lets in shows it (Safari 16.4 and up). Quality 85 keeps faces
# and lips crisp on high density phone screens, and is still smaller than the JPEG copies were.
module ProxiedImage
  module_function

  def variant(attachment, size)
    attachment.variant(resize_to_limit: [ size, size ], format: :webp, saver: { quality: 85 })
  end
end
