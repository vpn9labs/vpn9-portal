module DomainRedirect
  extend ActiveSupport::Concern

  # List of domains we own and should redirect
  DOMAINS = %w[
    vpn9.app
    vpn9.cloud
    vpn9.me
    vpn9.io
    vpn9.co
    vpn9.co.uk
    vpn9.eu
    vpn9.fr
    vpn9.de
    vpn9.at
    vpn9.ch
    vpn9.org
  ]

  included do
    before_action :redirect_to_primary_domain
  end

  private

  def redirect_to_primary_domain
    primary_domain = ENV.fetch("PRIMARY_DOMAIN", "vpn9.com")

    # Only redirect if we're on one of our secondary domains
    if DOMAINS.include?(request.host) && request.host != primary_domain
      redirect_to "https://#{primary_domain}#{request.fullpath}",
                  status: :moved_permanently,
                  allow_other_host: true
    end
  end
end
