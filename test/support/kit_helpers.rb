# Builds kits for request tests: consented, answered and with today's photo, as each test needs.
module KitHelpers
  def make_kit(consented: true, photo: true, path: :self_use, **answers)
    kit = Kit.create!(path:, consented_at: (Time.current if consented), **answers)
    add_photo(kit) if photo
    kit
  end

  def add_photo(kit, kind: :today, sampled: { "skin" => "#C99A7A" })
    kit.photos.create!(kind:, source: "upload", sha256: SecureRandom.hex(32), width: 96, height: 120, sampled:,
      image: { io: file_fixture("face.jpg").open, filename: "face.jpg", content_type: "image/jpeg" })
  end

  def photo_upload(name = "face.jpg", type = "image/jpeg")
    Rack::Test::UploadedFile.new(file_fixture(name), type)
  end

  def signed_cookie(name)
    ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash).signed[name]
  end

  # Counts Render#request! calls (the only way a preview reaches the appearance provider).
  module CountRequests
    mattr_accessor :count, default: 0

    def request!
      CountRequests.count += 1
      super
    end
  end
  Render.prepend(CountRequests) unless Render <= CountRequests
end
