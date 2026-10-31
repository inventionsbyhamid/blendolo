require "vips"

# The copy of a photo we send to YouCam: upright, sRGB JPEG, long side at most 1024 (makeup transfer's limit, and under
# the 1080 px height makeup accepts), width a multiple of 8 (the result then keeps our size), no metadata (no EXIF,
# no GPS). The aspect ratio is kept to within a pixel.
module Appearance::Youcam::Derivative
  LONG_SIDE = 1024
  QUALITY = 90

  module_function

  def jpeg(image)
    source = Vips::Image.new_from_buffer(image.bytes, "").autorot
    source = source.flatten(background: [ 255, 255, 255 ]) if source.has_alpha?
    width, height = size_for(source.width, source.height)

    source.thumbnail_image(width, height:, size: :force).colourspace(:srgb).jpegsave_buffer(Q: QUALITY, strip: true)
  rescue Vips::Error
    raise Appearance::Error.new(:bad_image, message: "can't read the photo")
  end

  def size_for(width, height)
    scale = [ LONG_SIDE.fdiv([ width, height ].max), 1.0 ].min
    new_width = (width * scale).floor / 8 * 8
    raise Appearance::Error.new(:bad_image, message: "photo too narrow") if new_width < 8

    [ new_width, (height * new_width.fdiv(width)).round ]
  end
end
