require "test_helper"

class LaunchNotificationTest < ActiveSupport::TestCase
  test "should be valid with valid email" do
    notification = LaunchNotification.new(email: "test@example.com")
    assert notification.valid?
  end

  test "should require email" do
    notification = LaunchNotification.new(email: nil)
    assert_not notification.valid?
    assert_includes notification.errors[:email], "can't be blank"
  end

  test "should validate email format" do
    invalid_emails = [ "invalid", "user@", "@example.com", "user @example.com" ]
    invalid_emails.each do |email|
      notification = LaunchNotification.new(email: email)
      assert_not notification.valid?, "#{email} should be invalid"
    end
  end

  test "should accept valid email formats" do
    valid_emails = [ "user@example.com", "user.name@example.co.uk", "user+tag@example.com" ]
    valid_emails.each do |email|
      notification = LaunchNotification.new(email: email)
      assert notification.valid?, "#{email} should be valid"
    end
  end

  test "should enforce unique emails" do
    LaunchNotification.create!(email: "unique@example.com")
    duplicate = LaunchNotification.new(email: "unique@example.com")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "is already on the waiting list"
  end

  test "should normalize email to lowercase" do
    notification = LaunchNotification.create!(email: "UPPER@EXAMPLE.COM")
    assert_equal "upper@example.com", notification.email
  end

  test "should strip whitespace from email" do
    notification = LaunchNotification.create!(email: "  spaces@example.com  ")
    assert_equal "spaces@example.com", notification.email
  end

  test "should default notified to false" do
    notification = LaunchNotification.create!(email: "new@example.com")
    assert_equal false, notification.notified
  end

  test "should have working scopes" do
    notified = LaunchNotification.create!(email: "notified@example.com", notified: true)
    not_notified = LaunchNotification.create!(email: "waiting@example.com", notified: false)

    assert_includes LaunchNotification.not_notified, not_notified
    assert_not_includes LaunchNotification.not_notified, notified
  end

  test "should order by created_at with recent scope" do
    # Clear existing fixtures first
    LaunchNotification.delete_all

    old = LaunchNotification.create!(email: "old@example.com", created_at: 2.days.ago)
    new = LaunchNotification.create!(email: "new@example.com", created_at: 1.hour.ago)

    assert_equal new, LaunchNotification.recent.order(:created_at).first
    assert_equal old, LaunchNotification.recent.order(:created_at).last
  end

  test "should filter by source" do
    vpn9 = LaunchNotification.create!(email: "vpn9@example.com", source: "vpn9.com")
    other = LaunchNotification.create!(email: "other@example.com", source: "partner.com")

    assert_includes LaunchNotification.by_source("vpn9.com"), vpn9
    assert_not_includes LaunchNotification.by_source("vpn9.com"), other
  end

  test "should extract metadata from request params" do
    notification = LaunchNotification.new(email: "meta@example.com")
    notification.request_params = {
      utm_source: "twitter",
      utm_campaign: "launch",
      utm_medium: "social",
      ref: "influencer"
    }
    notification.save!

    assert_equal "twitter", notification.metadata["utm_source"]
    assert_equal "launch", notification.metadata["utm_campaign"]
    assert_equal "social", notification.metadata["utm_medium"]
    assert_equal "influencer", notification.metadata["ref"]
  end

  test "should ignore empty utm parameters" do
    notification = LaunchNotification.new(email: "empty@example.com")
    notification.request_params = {
      utm_source: "",
      utm_campaign: nil,
      utm_medium: "email"
    }
    notification.save!

    # Empty strings are still included in compact, only nil values are removed
    assert_equal "", notification.metadata["utm_source"]
    assert_nil notification.metadata["utm_campaign"]
    assert_equal "email", notification.metadata["utm_medium"]
  end
end
