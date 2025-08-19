module HreflangHelper
  # Define domain to language/region mapping
  DOMAIN_LOCALES = {
    "vpn9.com" => "en",        # International/English
    "vpn9.fr" => "fr",          # French
    "vpn9.eu" => "en-GB",       # European English
    "vpn9.app" => "en-US",      # US English
    "vpn9.io" => "en"          # Technical audience
  }.freeze

  def hreflang_tags
    return "" unless defined?(request)

    current_path = request.path
    tags = []

    # Add hreflang tags for each regional domain
    DOMAIN_LOCALES.each do |domain, locale|
      url = "https://#{domain}#{current_path}"
      tags << tag.link(rel: "alternate", hreflang: locale, href: url)
    end

    # Add x-default for international users
    tags << tag.link(rel: "alternate", hreflang: "x-default", href: "https://vpn9.com#{current_path}")

    safe_join(tags)
  end

  def canonical_url_for_domain
    # Always point to the primary domain as canonical
    primary_domain = "vpn9.com"

    # For regional domains, still use primary as canonical unless serving unique content
    if serving_unique_regional_content?
      "https://#{request.host}#{request.path}"
    else
      "https://#{primary_domain}#{request.path}"
    end
  end

  private

  def serving_unique_regional_content?
    # Return true only if this domain serves unique content
    # For example, different pricing, different language, etc.
    request.host == "vpn9.fr" && locale == :fr
  end
end
