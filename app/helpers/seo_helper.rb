module SeoHelper
  def default_meta_tags
    # Always use primary domain for canonical URLs to avoid duplicate content
    canonical_url = request.original_url.gsub(/https?:\/\/[^\/]+/, "https://vpn9.com")

    {
      title: "VPN9 - True Privacy VPN with Zero Logs | Anonymous Bitcoin & Monero Payments",
      description: "The only VPN that truly keeps no logs. Anonymous accounts, no email required. Pay with Bitcoin or Monero. Military-grade encryption. Open source.",
      keywords: "VPN, privacy, no logs, anonymous VPN, Bitcoin VPN, Monero VPN, WireGuard, zero logs VPN, private VPN, secure VPN",
      author: "VPN9",
      robots: "index, follow",
      canonical: canonical_url,
      'og:title': "VPN9 - True Privacy VPN with Zero Logs",
      'og:description': "The only VPN service that truly keeps no logs. Create anonymous accounts without email. Pay with cryptocurrency for complete privacy.",
      'og:type': "website",
      'og:url': canonical_url,
      'og:image': "#{request.base_url}/og-image.png",
      'og:site_name': "VPN9",
      'twitter:card': "summary_large_image",
      'twitter:title': "VPN9 - True Privacy VPN with Zero Logs",
      'twitter:description': "The only VPN that truly keeps no logs. Anonymous accounts, no email required. Pay with Bitcoin or Monero.",
      'twitter:image': "#{request.base_url}/twitter-card.png"
    }
  end

  def meta_tag_helpers(options = {})
    tags = default_meta_tags.merge(options)

    content_for :meta_tags do
      safe_join([
        tag.title(tags[:title]),
        tag.meta(name: "description", content: tags[:description]),
        tag.meta(name: "keywords", content: tags[:keywords]),
        tag.meta(name: "author", content: tags[:author]),
        tag.meta(name: "robots", content: tags[:robots]),
        tag.link(rel: "canonical", href: tags[:canonical]),

        # Open Graph tags
        tag.meta(property: "og:title", content: tags["og:title"]),
        tag.meta(property: "og:description", content: tags["og:description"]),
        tag.meta(property: "og:type", content: tags["og:type"]),
        tag.meta(property: "og:url", content: tags["og:url"]),
        tag.meta(property: "og:image", content: tags["og:image"]),
        tag.meta(property: "og:site_name", content: tags["og:site_name"]),

        # Twitter Card tags
        tag.meta(name: "twitter:card", content: tags["twitter:card"]),
        tag.meta(name: "twitter:title", content: tags["twitter:title"]),
        tag.meta(name: "twitter:description", content: tags["twitter:description"]),
        tag.meta(name: "twitter:image", content: tags["twitter:image"])
      ])
    end
  end

  def structured_data_for_vpn_service
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      "name": "VPN9",
      "applicationCategory": "SecurityApplication",
      "operatingSystem": [ "Windows", "macOS", "Linux", "iOS", "Android" ],
      "offers": {
        "@type": "Offer",
        "price": "9.00",
        "priceCurrency": "USD",
        "availability": "https://schema.org/InStock"
      },
      "aggregateRating": {
        "@type": "AggregateRating",
        "ratingValue": "4.9",
        "ratingCount": "2847"
      },
      "description": "True privacy VPN service with zero logs, anonymous accounts, and cryptocurrency payments",
      "screenshot": "#{request.base_url}/screenshot.png",
      "featureList": [
        "Zero connection logs",
        "Anonymous account creation",
        "Bitcoin and Monero payments",
        "WireGuard protocol",
        "Military-grade encryption",
        "No email required",
        "5 simultaneous connections",
        "Global server network"
      ],
      "creator": {
        "@type": "Organization",
        "name": "VPN9",
        "url": "#{request.base_url}"
      }
    }
  end

  def structured_data_for_organization
    {
      "@context": "https://schema.org",
      "@type": "Organization",
      "name": "VPN9",
      "url": request.base_url,
      "logo": "#{request.base_url}/logo.png",
      "description": "Privacy-focused VPN service with true no-logs policy",
      "sameAs": [
        "https://github.com/vpn9labs"
      ],
      "contactPoint": {
        "@type": "ContactPoint",
        "contactType": "customer support",
        "availableLanguage": [ "English" ]
      }
    }
  end

  def structured_data_for_faq
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      "mainEntity": [
        {
          "@type": "Question",
          "name": "Does VPN9 really keep no logs?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "Yes, VPN9 has been architected from the ground up to make logging impossible. We don't store connection times, IP addresses, bandwidth usage, or any activity data."
          }
        },
        {
          "@type": "Question",
          "name": "Can I pay with cryptocurrency?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "Yes, we accept Bitcoin, Monero, and other major cryptocurrencies for complete payment anonymity. No credit card or bank information required."
          }
        },
        {
          "@type": "Question",
          "name": "Do I need to provide an email address?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "No, VPN9 allows completely anonymous account creation. You can sign up without providing any personal information - just create a secure passphrase."
          }
        },
        {
          "@type": "Question",
          "name": "What VPN protocol does VPN9 use?",
          "acceptedAnswer": {
            "@type": "Answer",
            "text": "VPN9 uses WireGuard, the most modern and secure VPN protocol available, offering perfect forward secrecy and lightning-fast speeds."
          }
        }
      ]
    }
  end

  def breadcrumb_structured_data(items)
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      "itemListElement": items.map.with_index do |item, index|
        {
          "@type": "ListItem",
          "position": index + 1,
          "name": item[:name],
          "item": item[:url]
        }
      end
    }
  end
end
