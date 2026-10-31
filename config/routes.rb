Rails.application.routes.draw do
  # Nothing here uploads straight to storage, so Active Storage's direct upload endpoint is closed (drawn before the
  # engine's own route, so this one wins).
  match "/rails/active_storage/direct_uploads", to: ->(_) { [ 404, {}, [] ] }, via: :all

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The appearance provider says a task finished.
  post "webhooks/youcam" => "webhooks/youcam#create", as: :youcam_webhook
  # The payment provider says something was paid, renewed, cancelled or refunded.
  post "webhooks/dodo" => "webhooks/dodo#create", as: :dodo_webhook

  # Background jobs, for the owner (basic auth, config/initializers/mission_control.rb).
  mount MissionControl::Jobs::Engine, at: "/jobs"

  root "pages#home"

  # Google sign in (OmniAuth answers POST /auth/google_oauth2 itself), sign out, and the account.
  get "sign_in" => "sessions#new", as: :sign_in
  get "auth/:provider/callback" => "sessions#create", as: :auth_callback, constraints: { provider: "google_oauth2" }
  get "auth/failure" => "sessions#failure", as: :auth_failure
  delete "sign_out" => "sessions#destroy", as: :sign_out
  resource :account, only: %i[show destroy] do
    get :delete
  end

  # Prices, buying credits, the payment provider's portal, and the Clinic plan's client list. Terms and refunds are
  # what the payment provider asks every seller to publish.
  get "pricing" => "pages#pricing"
  get "terms" => "pages#terms"
  get "refunds" => "pages#refunds"
  post "checkout" => "checkouts#create", as: :checkout
  get "billing/success" => "checkouts#success", as: :billing_success
  post "billing/portal" => "billing_portals#create", as: :billing_portal
  get "clinic" => "clinics#show", as: :clinic
  post "clinic/kits" => "clinics#create_kit", as: :clinic_kits

  get "privacy" => "pages#privacy"
  get "accessibility" => "pages#accessibility"
  get "sources" => "pages#sources"
  get "guides" => "pages#guides"
  get "guides/:slug" => "pages#guide", as: :guide
  get "sitemap.xml" => "pages#sitemap", as: :sitemap, defaults: { format: :xml }

  # Start a kit: for me or for someone I help. Example people start from /examples.
  resource :start, only: %i[show create]

  # A kit is reached by its private token: /k/:token.
  resources :kits, path: "k", param: :token, only: %i[show destroy] do
    member do
      get :delete
    end

    resource :consent, only: %i[show create]
    get "hands/:question" => "hands#show", as: :hand, constraints: { question: /[1-5]/ }
    patch "hands/:question" => "hands#update", constraints: { question: /[1-5]/ }
    patch "hands_today" => "hands_today#update"
    resources :photos, only: %i[new create]
    resources :looks, only: %i[index show], param: :key do
      post :previews, on: :member
      post :tweak, on: :member
    end
    resources :renders, only: [] do
      post :try_again, on: :member
    end
    resource :routine, only: %i[show create] do
      get "steps/:n" => "routines#step", as: :step, constraints: { n: /\d+/ }
      get :print
    end
    resource :signature, only: %i[show create]
    resource :shopping, only: :show, controller: :shopping
    resources :shares, only: %i[index create destroy], param: :share_token do
      post :restore, on: :member
    end
  end

  # What a helper sees: read only, scoped, expiring, revocable.
  get "s/:token" => "public_shares#show", as: :public_share

  # Example people (Rosa, June, Amara): stored results, never a provider call.
  resources :examples, only: %i[index show], param: :key, constraints: { key: /rosa|june|amara/ } do
    post :start, on: :member
  end

  namespace :api do
    get "ease_tags" => "ease_tags#index", defaults: { format: :json }
  end
  get "brands" => "pages#brands"

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
