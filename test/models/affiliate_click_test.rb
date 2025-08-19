require "test_helper"
require "ostruct"

class AffiliateClickTest < ActiveSupport::TestCase
  def setup
    @affiliate = Affiliate.create!(
      name: "Test Affiliate",
      email: "affiliate@example.com",
      code: "TESTCODE",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "btc",
      payout_address: "bc1qtest123",
      password: "password123",
      password_confirmation: "password123",
      terms_accepted: true
    )

    @click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.1"),
      landing_page: "/signup"
    )
  end

  # === Validations ===

  test "should be valid with valid attributes" do
    assert @click.valid?
  end

  test "should require affiliate" do
    @click.affiliate = nil
    assert_not @click.valid?
    assert_includes @click.errors[:affiliate], "must exist"
  end

  test "should require ip_hash" do
    @click.ip_hash = nil
    assert_not @click.valid?
    assert_includes @click.errors[:ip_hash], "can't be blank"
  end

  test "should allow blank landing_page" do
    @click.landing_page = nil
    assert @click.valid?

    @click.landing_page = ""
    assert @click.valid?
  end

  test "should allow blank user_agent_hash" do
    @click.user_agent_hash = nil
    assert @click.valid?

    @click.user_agent_hash = ""
    assert @click.valid?
  end

  test "should allow blank referrer" do
    @click.referrer = nil
    assert @click.valid?

    @click.referrer = ""
    assert @click.valid?
  end

  # === Scopes ===

  test "recent scope should order by created_at desc" do
    older_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.2"),
      landing_page: "/",
      created_at: 2.days.ago
    )

    newer_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.3"),
      landing_page: "/pricing",
      created_at: Time.current + 1.second  # Make sure it's the newest
    )

    recent = AffiliateClick.recent
    assert_equal newer_click, recent.first
    assert_equal @click, recent.second
    assert_equal older_click, recent.third
  end

  test "converted scope should return only converted clicks" do
    @click.update!(converted: true)

    unconverted_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.4"),
      landing_page: "/features",
      converted: false
    )

    assert_includes AffiliateClick.converted, @click
    assert_not_includes AffiliateClick.converted, unconverted_click
  end

  test "unconverted scope should return only unconverted clicks" do
    @click.update!(converted: false)

    converted_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.5"),
      landing_page: "/buy",
      converted: true
    )

    assert_includes AffiliateClick.unconverted, @click
    assert_not_includes AffiliateClick.unconverted, converted_click
  end

  test "today scope should return clicks from today" do
    yesterday_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.6"),
      landing_page: "/",
      created_at: 1.day.ago
    )

    today_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.7"),
      landing_page: "/",
      created_at: 2.hours.ago
    )

    assert_includes AffiliateClick.today, today_click
    assert_not_includes AffiliateClick.today, yesterday_click
  end

  test "this_week scope should return clicks from past week" do
    old_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.8"),
      landing_page: "/",
      created_at: 2.weeks.ago
    )

    recent_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.9"),
      landing_page: "/",
      created_at: 3.days.ago
    )

    assert_includes AffiliateClick.this_week, recent_click
    assert_not_includes AffiliateClick.this_week, old_click
  end

  test "this_month scope should return clicks from past month" do
    old_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.10"),
      landing_page: "/",
      created_at: 2.months.ago
    )

    recent_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.11"),
      landing_page: "/",
      created_at: 2.weeks.ago
    )

    assert_includes AffiliateClick.this_month, recent_click
    assert_not_includes AffiliateClick.this_month, old_click
  end

  # === Class Methods ===

  test "track_click should create click with hashed IP" do
    request = OpenStruct.new(
      remote_ip: "203.0.113.42",
      user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
      fullpath: "/signup?ref=TEST",
      referrer: "https://google.com"
    )

    click = AffiliateClick.track_click(@affiliate, request, "/signup")

    assert click.persisted?
    assert_equal @affiliate, click.affiliate
    assert_equal AffiliateClick.hash_ip("203.0.113.42"), click.ip_hash
    assert_equal AffiliateClick.hash_string("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"), click.user_agent_hash
    assert_equal "/signup", click.landing_page
    assert_equal "https://google.com", click.referrer
  end

  test "track_click should use request fullpath if landing_page not provided" do
    request = OpenStruct.new(
      remote_ip: "203.0.113.43",
      user_agent: "Safari/537.36",
      fullpath: "/pricing?utm_source=affiliate",
      referrer: nil
    )

    click = AffiliateClick.track_click(@affiliate, request)

    assert_equal "/pricing?utm_source=affiliate", click.landing_page
  end

  test "hash_ip should return consistent hash for same IP" do
    ip = "192.168.1.100"

    hash1 = AffiliateClick.hash_ip(ip)
    hash2 = AffiliateClick.hash_ip(ip)

    assert_equal hash1, hash2
    assert_match /^[a-f0-9]{64}$/, hash1  # Should be SHA256 hash
  end

  test "hash_ip should return different hashes for different IPs" do
    hash1 = AffiliateClick.hash_ip("192.168.1.1")
    hash2 = AffiliateClick.hash_ip("192.168.1.2")

    assert_not_equal hash1, hash2
  end

  test "hash_ip should return nil for blank IP" do
    assert_nil AffiliateClick.hash_ip(nil)
    assert_nil AffiliateClick.hash_ip("")
    assert_nil AffiliateClick.hash_ip("   ")
  end

  test "hash_string should return consistent hash for same string" do
    string = "Mozilla/5.0 Test Browser"

    hash1 = AffiliateClick.hash_string(string)
    hash2 = AffiliateClick.hash_string(string)

    assert_equal hash1, hash2
    assert_match /^[a-f0-9]{64}$/, hash1
  end

  test "hash_string should return different hashes for different strings" do
    hash1 = AffiliateClick.hash_string("Chrome")
    hash2 = AffiliateClick.hash_string("Firefox")

    assert_not_equal hash1, hash2
  end

  test "hash_string should return nil for blank string" do
    assert_nil AffiliateClick.hash_string(nil)
    assert_nil AffiliateClick.hash_string("")
    assert_nil AffiliateClick.hash_string("   ")
  end

  # === Privacy Tests ===

  test "should not store actual IP addresses" do
    ip = "203.0.113.99"
    request = OpenStruct.new(
      remote_ip: ip,
      user_agent: "Test",
      fullpath: "/",
      referrer: nil
    )

    click = AffiliateClick.track_click(@affiliate, request)

    # Check that the actual IP is not stored anywhere
    assert_not_equal ip, click.ip_hash
    assert_not_includes click.attributes.values.map(&:to_s), ip
  end

  test "should not store actual user agent strings" do
    user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)"
    request = OpenStruct.new(
      remote_ip: "1.1.1.1",
      user_agent: user_agent,
      fullpath: "/",
      referrer: nil
    )

    click = AffiliateClick.track_click(@affiliate, request)

    # Check that the actual user agent is not stored
    assert_not_equal user_agent, click.user_agent_hash
    assert_not_includes click.attributes.values.map(&:to_s), user_agent
  end

  # === Conversion Tracking ===

  test "should default to unconverted state" do
    click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("10.0.0.1")
    )

    assert_equal false, click.converted
  end

  test "should track conversion status" do
    @click.update!(converted: true)
    assert @click.converted?

    @click.update!(converted: false)
    assert_not @click.converted?
  end

  # === Edge Cases ===

  test "should handle very long landing pages" do
    long_path = "/" + "a" * 1000

    click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("10.0.0.2"),
      landing_page: long_path
    )

    assert click.valid?
    assert_equal long_path, click.landing_page
  end

  test "should handle special characters in landing page" do
    special_path = "/page?param=value&other=test%20value#section"

    click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("10.0.0.3"),
      landing_page: special_path
    )

    assert click.valid?
    assert_equal special_path, click.landing_page
  end

  test "should handle unicode in referrer" do
    unicode_referrer = "https://例え.jp/ページ"

    click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("10.0.0.4"),
      referrer: unicode_referrer
    )

    assert click.valid?
    assert_equal unicode_referrer, click.referrer
  end

  test "should handle IPv6 addresses" do
    ipv6 = "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
    hash = AffiliateClick.hash_ip(ipv6)

    assert_not_nil hash
    assert_match /^[a-f0-9]{64}$/, hash
  end

  # === Association Tests ===

  test "should belong to affiliate" do
    assert_equal @affiliate, @click.affiliate
  end

  test "should be destroyed when affiliate is destroyed" do
    click_id = @click.id
    @affiliate.destroy

    assert_nil AffiliateClick.find_by(id: click_id)
  end

  # === Bulk Operations ===

  test "should handle bulk click creation" do
    clicks = []

    100.times do |i|
      clicks << {
        affiliate_id: @affiliate.id,
        ip_hash: Digest::SHA256.hexdigest("192.168.1.#{i}"),
        landing_page: "/page#{i}",
        created_at: i.hours.ago,
        updated_at: i.hours.ago
      }
    end

    assert_difference "AffiliateClick.count", 100 do
      AffiliateClick.insert_all(clicks)
    end
  end

  test "should efficiently query clicks by time period" do
    # Create clicks across different time periods
    100.times do |i|
      AffiliateClick.create!(
        affiliate: @affiliate,
        ip_hash: Digest::SHA256.hexdigest("10.0.0.#{i}"),
        created_at: i.days.ago
      )
    end

    # Test various time period queries
    assert AffiliateClick.today.count < AffiliateClick.this_week.count
    assert AffiliateClick.this_week.count < AffiliateClick.this_month.count
    assert AffiliateClick.this_month.count < AffiliateClick.count
  end

  # === Concurrent Access ===

  test "should handle concurrent click tracking" do
    threads = []
    clicks = []
    mutex = Mutex.new

    10.times do |i|
      threads << Thread.new do
        request = OpenStruct.new(
          remote_ip: "192.168.2.#{i}",
          user_agent: "Browser #{i}",
          fullpath: "/page#{i}",
          referrer: "https://site#{i}.com"
        )

        click = AffiliateClick.track_click(@affiliate, request)
        mutex.synchronize { clicks << click }
      end
    end

    threads.each(&:join)

    assert_equal 10, clicks.count
    assert clicks.all?(&:persisted?)
    assert_equal 10, clicks.map(&:ip_hash).uniq.count  # All different IPs
  end

  # === Data Integrity ===

  test "should maintain hash consistency across Rails restarts" do
    # Simulate getting the same hash function after restart
    ip = "192.168.100.1"
    original_hash = AffiliateClick.hash_ip(ip)

    # Clear any potential cache (though there shouldn't be any)
    AffiliateClick.connection.clear_cache! if AffiliateClick.connection.respond_to?(:clear_cache!)

    new_hash = AffiliateClick.hash_ip(ip)
    assert_equal original_hash, new_hash
  end

  test "should handle nil request attributes gracefully" do
    request = OpenStruct.new(
      remote_ip: "127.0.0.1",  # IP is required, so provide a valid one
      user_agent: nil,
      fullpath: nil,
      referrer: nil
    )

    # Should not raise an error
    click = AffiliateClick.track_click(@affiliate, request)

    assert click.persisted?
    assert_not_nil click.ip_hash  # IP hash should be present
    assert_nil click.user_agent_hash
    assert_nil click.landing_page
    assert_nil click.referrer
  end
end
