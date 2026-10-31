module PagesHelper
  # The landing photos: webp at 800 px and full size, with a jpeg fallback.
  def landing_picture(name, full:, height:, alt:, sizes:, eager: false, css: "photo")
    sources = "#{image_path("landing/#{name}-800.webp")} 800w, #{image_path("landing/#{name}-full.webp")} #{full}w"
    img_options = { class: css, width: 800, height:, alt: }
    img_options.merge!(eager ? { fetchpriority: "high" } : { loading: "lazy", decoding: "async" })

    tag.picture do
      tag.source(type: "image/webp", srcset: sources, sizes:) + image_tag("landing/#{name}-800.jpg", **img_options)
    end
  end
end
