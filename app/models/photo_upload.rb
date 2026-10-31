# Turns an uploaded face photo into a stored Photo: checks it is a JPEG, PNG, WebP or HEIC image up to 12 MB,
# turns it upright, shrinks it to 1600 px on the long side and saves it as a JPEG without EXIF (no location, no
# camera details). The same picture sent twice (a double tap, a retry) gives back the same Photo.
class PhotoUpload
  include ActiveModel::Model

  TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  # The libvips loaders those types use. Anything else (a file that only claims to be a photo) is refused.
  LOADERS = %w[jpegload pngload webpload heifload].freeze
  MAX_BYTES = 12.megabytes
  LONG_SIDE = 1600

  attr_accessor :kit, :file, :kind, :sampled, :source

  validates :kind, inclusion: { in: Photo.kinds.keys, message: "isn't a kind of photo we take" }
  validate :file_is_a_photo

  def save
    return false unless valid?
    return false unless read_by_a_photo_loader?

    processed = ImageProcessing::Vips.source(file.tempfile.path).autorot.resize_to_limit(LONG_SIDE, LONG_SIDE)
      .custom { |image| in_srgb(image) }.convert("jpeg").saver(strip: true, quality: 88).call
    bytes = File.binread(processed.path)
    sha256 = Digest::SHA256.hexdigest(bytes)

    @photo = kit.photos.find_by(kind:, sha256:) || create_photo(bytes, sha256, processed.path)
    true
  rescue Vips::Error
    errors.add(:file, "couldn't be read as a photo")
    false
  ensure
    processed&.close!
  end

  attr_reader :photo

  private
    # Colours as they look: a photo with its own colour profile (Display P3 from an iPhone) is converted to sRGB
    # before the profile is stripped, so lip and skin colours don't shift.
    def in_srgb(image)
      if image.get_typeof("icc-profile-data").positive?
        image.icc_transform("srgb", embedded: true, intent: :perceptual)
      else
        image.colourspace(:srgb)
      end
    end

    def read_by_a_photo_loader?
      loader = Vips::Image.new_from_file(file.tempfile.path, access: :sequential).get("vips-loader").to_s
      return true if LOADERS.any? { |name| loader.start_with?(name) }

      errors.add(:file, "isn't a JPEG, PNG, WebP or HEIC photo")
      false
    rescue Vips::Error
      errors.add(:file, "couldn't be read as a photo")
      false
    end

    def create_photo(bytes, sha256, path)
      image = Vips::Image.new_from_file(path)
      kit.photos.create!(kind:, sha256:, width: image.width, height: image.height, sampled: clean_sampled,
        source: source.presence_in(Photo::SOURCES) || "upload",
        image: { io: StringIO.new(bytes), filename: "#{kind}.jpg", content_type: "image/jpeg" })
    end

    # Colours sampled in the browser, as JSON: { "lips": "#A84452", ... }. Anything else is dropped.
    def clean_sampled
      parsed = sampled.is_a?(String) ? JSON.parse(sampled) : sampled.to_h
      parsed.to_h.slice(*Photo::SAMPLED_REGIONS).select { |_region, hex| hex.to_s.match?(/\A#\h{6}\z/) }
        .transform_values(&:upcase)
    rescue JSON::ParserError
      {}
    end

    def file_is_a_photo
      unless file.respond_to?(:tempfile)
        errors.add(:file, "is missing")
        return
      end

      errors.add(:file, "is bigger than 12 MB") if file.size > MAX_BYTES
      type = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
      errors.add(:file, "isn't a JPEG, PNG, WebP or HEIC photo") unless TYPES.include?(type)
    end
end
