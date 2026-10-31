# A picture for Chrome's fake camera (--use-file-for-fake-video-capture reads Y4M video), for system tests that need
# a face in front of the camera.
module FakeCamera
  module_function

  # Writes the image to path as a few identical Y4M frames (4:2:0, full range), which Chrome shows over and over.
  def write(image_path, path, frames: 2)
    rgb = Vips::Image.new_from_file(image_path.to_s).colourspace(:srgb)
    rgb = rgb.extract_band(0, n: 3).crop(0, 0, rgb.width & ~1, rgb.height & ~1)
    r, g, b = rgb.bandsplit
    y = r * 0.299 + g * 0.587 + b * 0.114
    u = (b - y) * 0.564 + 128
    v = (r - y) * 0.713 + 128
    planes = [ y, u.resize(0.5), v.resize(0.5) ].map { |plane| plane.cast(:uchar).write_to_memory }
    frame = "FRAME\n".b + planes.join
    File.binwrite(path, "YUV4MPEG2 W#{rgb.width} H#{rgb.height} F30:1 Ip A1:1 C420jpeg\n".b + frame * frames)
    path
  end
end
