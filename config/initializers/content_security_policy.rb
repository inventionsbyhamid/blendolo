# Content Security Policy: everything comes from our own origin, with one exception. Hands-free capture runs MediaPipe
# Tasks Vision in the browser, so its script and WebAssembly come from one pinned package on jsDelivr, and its face
# model from one file (config.x.mediapipe); and the Google sign in form ends on Google's page. Inline scripts and styles need the per-request nonce (importmap and
# Turbo's progress bar use it). Images may be data: or blob: (camera frames and previews).
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

mediapipe = Rails.application.config.x.mediapipe

# Dodo Payments' hosted checkout and customer portal, in test mode and live.
dodo_pages = %w[https://test.checkout.dodopayments.com https://checkout.dodopayments.com
  https://test.customer.dodopayments.com https://customer.dodopayments.com].freeze

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    # Sign in with Google is a form POST that redirects to Google's sign in page; buying and "Manage" are form POSTs
    # that redirect to the payment provider's checkout and customer portal (Dodo Payments, test and live).
    policy.form_action :self, "https://accounts.google.com", *dodo_pages
    policy.frame_ancestors :none
    policy.object_src :none
    policy.font_src :self, :data
    policy.img_src :self, :data, :blob
    policy.media_src :self, :blob
    policy.worker_src :self, :blob
    policy.manifest_src :self
    policy.script_src :self, "'wasm-unsafe-eval'", mediapipe.package_url
    policy.style_src :self
    policy.connect_src :self, mediapipe.package_url, mediapipe.model_url
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
