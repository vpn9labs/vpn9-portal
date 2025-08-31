require "test_helper"

class SitemapsControllerTest < ActionDispatch::IntegrationTest
  test "should get sitemap" do
    get sitemap_url(format: :xml)
    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
  end

  test "sitemap should contain required URLs" do
    get sitemap_url(format: :xml)
    assert_response :success

    # Check that the response is valid XML
    doc = Nokogiri::XML(response.body)
    assert doc.errors.empty?, "XML should be valid"

    # Check for required namespace
    assert_equal "http://www.sitemaps.org/schemas/sitemap/0.9",
                 doc.root.namespace.href

    # Check that we have URLs
    urls = doc.css("url loc").map(&:text)
    assert urls.any?, "Sitemap should contain URLs"

    # Check for essential pages
    assert urls.any? { |url| url.include?("/") }, "Should include root URL"
    assert urls.any? { |url| url.include?("/signup") }, "Should include signup URL"
    assert urls.any? { |url| url.include?("/login") }, "Should include login URL"

    # Check for proper structure
    doc.css("url").each do |url_node|
      assert url_node.at_css("loc"), "Each URL should have a location"
      assert url_node.at_css("lastmod"), "Each URL should have a lastmod date"
      assert url_node.at_css("changefreq"), "Each URL should have a changefreq"
      assert url_node.at_css("priority"), "Each URL should have a priority"
    end
  end

  test "sitemap priorities should be correct" do
    get sitemap_url(format: :xml)
    assert_response :success

    doc = Nokogiri::XML(response.body)

    # Find root URL and check its priority
    root_url_node = doc.css("url").find do |node|
      loc = node.at_css("loc")&.text
      loc && !loc.include?("#") && loc.end_with?("/")
    end

    assert root_url_node, "Root URL should be present"
    root_priority = root_url_node.at_css("priority")&.text&.to_f
    assert_equal 1.0, root_priority, "Root URL should have highest priority"

    # Check that priorities are valid (between 0.0 and 1.0)
    doc.css("url priority").each do |priority_node|
      priority = priority_node.text.to_f
      assert priority >= 0.0 && priority <= 1.0,
             "Priority should be between 0.0 and 1.0, got #{priority}"
    end
  end

  test "sitemap should be accessible without authentication" do
    get sitemap_url(format: :xml)
    assert_response :success
  end

  test "sitemap lastmod dates should be valid" do
    get sitemap_url(format: :xml)
    assert_response :success

    doc = Nokogiri::XML(response.body)

    doc.css("url lastmod").each do |lastmod_node|
      date_str = lastmod_node.text
      # Check date format (YYYY-MM-DD)
      assert_match /\A\d{4}-\d{2}-\d{2}\z/, date_str,
                   "Date should be in YYYY-MM-DD format, got #{date_str}"

      # Check that date is parseable
      assert_nothing_raised { Date.parse(date_str) }
    end
  end

  test "sitemap changefreq values should be valid" do
    get sitemap_url(format: :xml)
    assert_response :success

    doc = Nokogiri::XML(response.body)
    valid_frequencies = %w[always hourly daily weekly monthly yearly never]

    doc.css("url changefreq").each do |freq_node|
      freq = freq_node.text
      assert valid_frequencies.include?(freq),
             "Invalid changefreq value: #{freq}"
    end
  end
end
