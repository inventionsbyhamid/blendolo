# The resized copy of a photo or preview that pages show (RendersHelper#proxied_image_path), and that Examples makes
# ahead for example kits. WebP: every browser Blendolo lets in shows it (Safari 16.4 and up), and at quality 80 it is
# about a third smaller than the JPEG copies were, with the same look.
module ProxiedImage
  module_function

  def variant(attachment, size)
    attachment.variant(resize_to_limit: [ size, size ], format: :webp, saver: { quality: 80 })
  end
end
