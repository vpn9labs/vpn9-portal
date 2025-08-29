class SitemapsController < ApplicationController
  allow_unauthenticated_access

  def show
    # Always generate sitemap URLs with primary domain
    @primary_domain = ENV.fetch("PRIMARY_DOMAIN", "vpn9.com")
    @base_url = "https://#{@primary_domain}"

    @static_pages = [
      {
        url: "#{@base_url}/",
        changefreq: "weekly",
        priority: 1.0,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/signup",
        changefreq: "monthly",
        priority: 0.9,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/session/new",
        changefreq: "weekly",
        priority: 0.8,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/attestation",
        changefreq: "weekly",
        priority: 0.7,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/transparency",
        changefreq: "weekly",
        priority: 0.7,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/security",
        changefreq: "weekly",
        priority: 0.7,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/affiliates/login",
        changefreq: "monthly",
        priority: 0.6,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/affiliates/new",
        changefreq: "monthly",
        priority: 0.6,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/#features",
        changefreq: "monthly",
        priority: 0.7,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/#privacy",
        changefreq: "monthly",
        priority: 0.7,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/#pricing",
        changefreq: "weekly",
        priority: 0.8,
        lastmod: Time.current
      },
      {
        url: "#{@base_url}/#technical",
        changefreq: "monthly",
        priority: 0.6,
        lastmod: Time.current
      }
    ]

    # Add legal pages if they exist
    if defined?(privacy_policy_url)
      @static_pages << {
        url: privacy_policy_url,
        changefreq: "yearly",
        priority: 0.5,
        lastmod: Time.current
      }
    end

    if defined?(terms_of_service_url)
      @static_pages << {
        url: terms_of_service_url,
        changefreq: "yearly",
        priority: 0.5,
        lastmod: Time.current
      }
    end

    respond_to do |format|
      format.xml { render layout: false }
    end
  end
end
