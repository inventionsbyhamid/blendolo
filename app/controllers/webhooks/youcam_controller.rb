# POST /webhooks/youcam: a provider task finished, so poll its render now instead of at the next scheduled poll.
# Unknown or already finished tasks get 200 and nothing else, so the provider stops retrying.
module Webhooks
  class YoucamController < ActionController::API
    rate_limit to: 120, within: 1.minute

    def create
      webhook = Appearance::Youcam::Webhook.new(body: request.raw_post, headers: request.headers)
      return head(:unauthorized) unless webhook.authentic?

      tracked = Render.running.find_by(external_id: webhook.external_id) if webhook.external_id
      ProviderPollJob.perform_later(tracked, reschedule: false) if tracked
      head :ok
    end
  end
end
