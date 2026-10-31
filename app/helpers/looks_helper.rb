module LooksHelper
  # The picture of a look on a model, or nil while it isn't in the assets yet.
  def look_thumbnail(look)
    path = look.thumbnail.to_s
    path if path.present? && Rails.application.assets.load_path.find(path)
  end
end
