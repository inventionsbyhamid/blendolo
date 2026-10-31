module SharesHelper
  AUDIENCES = { "helper" => "A helper", "family" => "Family", "therapist" => "An occupational therapist" }.freeze
  SCOPES = { "routine_only" => "The routine only", "routine_and_photos" => "The routine and photos" }.freeze

  # The link as a QR code, an SVG drawn on the server (works when printed, needs no script).
  def share_qr(url)
    svg = RQRCode::QRCode.new(url).as_svg(module_size: 6, standalone: true, use_path: true, viewbox: true,
      svg_attributes: { class: "qr", role: "img", "aria-label": "QR code for the link" })
    svg.sub(/\A<\?xml[^>]*\?>/, "").html_safe # rubocop:disable Rails/OutputSafety -- our own SVG of our own URL
  end
end
