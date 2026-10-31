require "vips"

# Makeup results come back with a near-black first row of pixels (and a slightly lighter row under it), which shows
# as a dark line along the top of the preview. Before a makeup result is stored, its top 2 rows go, and so do up to
# 2 columns on the left if they're as dark. The picture is 2 or so pixels smaller; nothing else changes.
module Appearance::EdgeTrim
  TOP = 2
  MAX_LEFT = 2
  # A left column darker than this share of the columns just inside it is cut off too.
  DARK = 0.5
  JPEG_QUALITY = 92

  module_function

  # image: Appearance::Image -> Appearance::Image (the same one when it can't be read)
  def call(image)
    source = Vips::Image.new_from_buffer(image.bytes, "")
    return image if source.width <= MAX_LEFT * 2 + 3 || source.height <= TOP * 2

    left = dark_columns(source)
    trimmed = source.crop(left, TOP, source.width - left, source.height - TOP)
    bytes = image.content_type == "image/png" ? trimmed.pngsave_buffer : trimmed.jpegsave_buffer(Q: JPEG_QUALITY)
    Appearance::Image.from_bytes(bytes, basename: File.basename(image.filename, ".*"))
  rescue Vips::Error
    image
  end

  # How many columns on the left are much darker than the picture just inside them.
  def dark_columns(source)
    grey = source.colourspace(:b_w).extract_band(0)
    height = grey.height - TOP
    inside = grey.crop(MAX_LEFT, TOP, 3, height).avg
    (0...MAX_LEFT).take_while { |x| grey.crop(x, TOP, 1, height).avg < inside * DARK }.size
  end
end
