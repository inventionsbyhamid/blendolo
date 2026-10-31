# Turns an uploaded face photo into a stored Photo: checks it is a JPEG, PNG, WebP or HEIC image up to 12 MB,
# turns it upright, shrinks it to 1600 px on the long side and saves it as a JPEG without EXIF (no location, no
# camera details). The same picture sent twice (a double tap, a retry) gives back the same Photo.
class PhotoUpload
  include ActiveModel::Model

  TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  MAX_BYTES = 12.megabytes
  LONG_SIDE = 1600

  attr_accessor :kit, :file, :kind, :sampled, :source

  validates :kind, inclusion: { in: Photo.kinds.keys, message: "isn't a kind of photo we take" }
  validate :file_is_a_photo

  def save
    return false unless valid?

    processed = ImageProcessing::Vips.source(file.tempfile.path).autorot.resize_to_limit(LONG_SIDE, LONG_SIDE)
      .convert("jpeg").saver(strip: true, quality: 88).call
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
