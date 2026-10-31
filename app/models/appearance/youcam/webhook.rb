# A task notification from YouCam (Standard Webhooks). It says only that a task finished, never the result, so the
# app answers by polling that task. With YOUCAM_WEBHOOK_SECRET set, a call must carry a fresh, valid signature:
# HMAC-SHA256 of "<webhook-id>.<webhook-timestamp>.<raw body>" keyed with the secret's base64 part, sent as
# "v1,<base64>" in webhook-signature (several may be listed, space-separated, while secrets rotate).
class Appearance::Youcam::Webhook
  TOLERANCE = 5.minutes

  def initialize(body:, headers:, secret: ENV["YOUCAM_WEBHOOK_SECRET"])
    @body = body.to_s
    @headers = headers
    @secret = secret.to_s
  end

  def authentic?(now: Time.current)
    return true if @secret.empty?

    id, timestamp, signatures = @headers["webhook-id"], @headers["webhook-timestamp"], @headers["webhook-signature"]
    return false if [ id, timestamp, signatures ].any?(&:blank?)
    return false if (now.to_i - timestamp.to_i).abs > TOLERANCE

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{@body}"))
    signatures.split.any? do |entry|
      version, signature = entry.split(",", 2)
      version == "v1" && ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
    end
  end

  # The provider's id of the task that finished (Render#external_id), or nil.
  def external_id
    JSON.parse(@body).dig("data", "task_id").presence
  rescue JSON::ParserError, TypeError
    nil
  end

  private
    def key = Base64.decode64(@secret.delete_prefix("whsec_"))
end
