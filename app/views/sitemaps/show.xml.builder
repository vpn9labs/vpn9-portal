xml.instruct! :xml, version: "1.0"
xml.urlset(
  "xmlns" => "http://www.sitemaps.org/schemas/sitemap/0.9",
  "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
  "xsi:schemaLocation" => "http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd"
) do
  # Static pages
  @static_pages.each do |page|
    xml.url do
      xml.loc page[:url]
      xml.lastmod page[:lastmod].strftime("%Y-%m-%d")
      xml.changefreq page[:changefreq]
      xml.priority page[:priority]
    end
  end

  # Add blog posts if they exist
  if @blog_posts.present?
    @blog_posts.each do |post|
      xml.url do
        xml.loc blog_post_url(post)
        xml.lastmod post.updated_at.strftime("%Y-%m-%d")
        xml.changefreq "weekly"
        xml.priority 0.6
      end
    end
  end

  # Add products if they exist
  if @products.present?
    @products.each do |product|
      xml.url do
        xml.loc product_url(product)
        xml.lastmod product.updated_at.strftime("%Y-%m-%d")
        xml.changefreq "weekly"
        xml.priority 0.7
      end
    end
  end

  # Add user-generated content pages if appropriate
  # Note: Be careful about exposing private content in sitemaps

  # Add API documentation if public
  if defined?(api_docs_url)
    xml.url do
      xml.loc api_docs_url
      xml.lastmod Time.current.strftime("%Y-%m-%d")
      xml.changefreq "monthly"
      xml.priority 0.5
    end
  end

  # Add support pages
  if defined?(support_url)
    xml.url do
      xml.loc support_url
      xml.lastmod Time.current.strftime("%Y-%m-%d")
      xml.changefreq "monthly"
      xml.priority 0.6
    end
  end

  # Add documentation
  if defined?(docs_url)
    xml.url do
      xml.loc docs_url
      xml.lastmod Time.current.strftime("%Y-%m-%d")
      xml.changefreq "weekly"
      xml.priority 0.6
    end
  end
end
