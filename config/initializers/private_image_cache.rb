# Photos and previews are faces. Active Storage's proxy sends them as public and cacheable for 100 years, so a
# shared device (or a cache on the way) could keep them long after "Delete everything". Ours are private, for an hour:
# as long as the links on the page work (ActiveStorage.urls_expire_in).
module PrivateImageCache
  private
    def http_cache_forever(public: false)
      expires_in 1.hour, public: false
      yield if stale?(etag: request.fullpath, last_modified: Time.utc(2011, 1, 1), public: false)
    end
end

Rails.application.config.to_prepare do
  [ ActiveStorage::Blobs::ProxyController, ActiveStorage::Representations::ProxyController ].each do |controller|
    controller.prepend(PrivateImageCache) unless controller <= PrivateImageCache
  end
end
