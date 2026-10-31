# libvips may only open images through its trusted loaders, never through fallbacks such as ImageMagick, whatever an
# upload claims to be. PhotoUpload also checks which loader read the photo.
require "vips"

Vips.block_untrusted(true) if Vips.respond_to?(:block_untrusted) && Vips.at_least_libvips?(8, 13)
