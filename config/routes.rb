Rails.application.routes.draw do
  root to: "root#index"

  # Public attestation and verification pages
  get "/attestation", to: "attestation#show", as: :attestation
  get "/transparency", to: "attestation#transparency", as: :transparency
  get "/security", to: "attestation#security", as: :security

  get "/signup", to: "signups#new"
  post "/signup", to: "signups#create"
  get "/login", to: "sessions#new", as: :new_session
  resource :session, only: [ :create, :destroy ]
  resources :passwords, param: :token

  # Launch notification signups (teaser page)
  resources :launch_notifications, only: [ :create ]

  # Sitemap
  get "/sitemap.xml", to: "sitemaps#show", format: :xml, as: :sitemap

  # Account deletion
  resource :account_deletion, only: [ :new, :create ]

  # Device management
  resources :devices, only: [ :index, :destroy ]

  # New device setup flow with client-side key generation
  resource :device_setup, only: [ :new, :create ], controller: "device_setup" do
    collection do
      get :locations
      get "relays/:location_id", to: "device_setup#relays", as: :relays
    end
  end

  # Admin routes
  namespace :admin do
    root to: "dashboard#index"
    resource :session, only: [ :new, :create, :destroy ]
    resources :users, only: [ :index, :show, :edit, :update ] do
      resources :devices, only: [ :destroy ]
    end
    resources :subscriptions, only: [ :index, :show, :edit, :update, :new, :create ]
    resources :plans
    resources :locations
    resources :relays

    # Affiliate management
    resources :affiliates do
      member do
        post :toggle_status
      end
    end

    resources :commissions, only: [ :index, :show ] do
      member do
        post :approve
        post :cancel
      end
      collection do
        post :bulk_approve
        post :bulk_cancel
      end
    end

    resources :payouts, only: [ :index, :new, :create ] do
      collection do
        get :export
      end
    end

    resources :payout_requests do
      member do
        post :approve
        post :reject
        post :process_payment
      end
      collection do
        post :bulk_approve
        post :bulk_process
      end
    end

    # Analytics
    get "analytics", to: "affiliate_analytics#index"
    get "analytics/affiliate/:id", to: "affiliate_analytics#affiliate", as: :affiliate_analytics
    get "analytics/export", to: "affiliate_analytics#export", as: :analytics_export

    # Launch Notifications
    resources :launch_notifications, only: [ :index, :show, :destroy ] do
      collection do
        get :stats
        get :export
      end
    end
  end

  # Affiliate sign-up and authentication
  resources :affiliates, only: [ :index, :new, :create ] do
    collection do
      get "thank-you", to: "affiliates#thank_you", as: :thank_you
      get "login", to: "affiliates#login", as: :login
      post "login", to: "affiliates#authenticate"
      delete "logout", to: "affiliates#logout", as: :logout
    end
  end

  # Affiliate portal (authenticated area)
  namespace :affiliates do
    get "dashboard", to: "dashboard#index"

    resource :profile, only: [ :show, :edit, :update ] do
      member do
        patch :update_password
      end
    end

    resources :referrals, only: [ :index, :show ]

    resources :earnings, only: [ :index ] do
      collection do
        get :payouts
        post :request_payout
      end
      member do
        post :cancel_payout
      end
    end

    resources :marketing_tools, only: [ :index ] do
      collection do
        get :link_generator
        get :banners
        get :email_templates
      end
    end
  end

  # Payment and subscription routes
  resources :plans, only: [ :index, :show ] do
    resources :payments, only: [ :new, :create ]
  end

  resources :payments, only: [ :show ] do
    collection do
      # Preserve helper webhook_payments_path while routing to API controller
      post :webhook, to: "payments/bitcart_webhook#create"
    end
  end

  resources :subscriptions, only: [ :index, :show ] do
    member do
      post :cancel
    end
  end

  # API routes
  namespace :api do
    namespace :v1 do
      # Minimal auth - no tracking
      scope :auth do
        post :token, to: "auth#token"
        get :verify, to: "auth#verify"
      end

      resources :devices, only: [ :create ]

      # Relay list - no tracking of which relay user connects to
      resources :relays, only: [ :index ]

      # DNS leak test endpoint
      get :dns_leak_test, to: "dns_leak_test#show"
      get "dns_leak_test/results", to: "dns_leak_test#results"

      # Runtime attestation and verification
      get :attestation, to: "attestation#show"
      get "attestation/verify", to: "attestation#verify"
      get "attestation/debug", to: "attestation#debug"
      get :transparency, to: "attestation#transparency"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
