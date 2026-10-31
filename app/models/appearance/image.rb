# An image going to or coming from the provider.
class Appearance::Image < Data.define(:io, :filename, :content_type)
  PNG = "\x89PNG\r\n\x1A\n".b.freeze
  JPEG = "\xFF\xD8\xFF".b.freeze

  # Results can be PNG bytes under a .jpg name, so the type comes from the bytes.
  def self.from_bytes(bytes, basename: "result")
    bytes = bytes.b
    type, extension =
      if bytes.start_with?(PNG) then [ "image/png", "png" ]
      elsif bytes.start_with?(JPEG) then [ "image/jpeg", "jpg" ]
      else raise Appearance::Error.new(:provider_error, message: "result is neither PNG nor JPEG")
      end

    new(io: StringIO.new(bytes), filename: "#{basename}.#{extension}", content_type: type)
  end

  def bytes
    io.rewind
    io.read.tap { io.rewind }
  end
end
