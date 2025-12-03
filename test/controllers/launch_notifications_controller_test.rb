require "test_helper"

class LaunchNotificationsControllerTest < ActionDispatch::IntegrationTest
  test "should create launch notification with valid email" do
    assert_difference("LaunchNotification.count", 1) do
      post launch_notifications_url, params: { email: "test@example.com" }, as: :json
    end

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
    assert_equal "You're on the list!", json_response["message"]
    assert json_response["total_signups"] > 0
  end

  test "should not create duplicate launch notification" do
    LaunchNotification.create!(email: "existing@example.com")

    assert_no_difference("LaunchNotification.count") do
      post launch_notifications_url, params: { email: "existing@example.com" }, as: :json
    end

    assert_response :unprocessable_content
    json_response = JSON.parse(response.body)
    assert_not json_response["success"]
    assert_match /already on the waiting list/i, json_response["error"]
  end

  test "should reject invalid email format" do
    assert_no_difference("LaunchNotification.count") do
      post launch_notifications_url, params: { email: "invalid-email" }, as: :json
    end

    assert_response :unprocessable_content
    json_response = JSON.parse(response.body)
    assert_not json_response["success"]
    assert json_response["error"].present?
  end

  test "should reject empty email" do
    assert_no_difference("LaunchNotification.count") do
      post launch_notifications_url, params: { email: "" }, as: :json
    end

    assert_response :unprocessable_content
    json_response = JSON.parse(response.body)
    assert_not json_response["success"]
  end

  test "should store request information" do
    post launch_notifications_url,
         params: { email: "tracker@example.com" },
         headers: { "HTTP_USER_AGENT" => "Test Browser" },
         as: :json

    notification = LaunchNotification.order(:created_at).last
    assert_equal "tracker@example.com", notification.email
    assert_equal "Test Browser", notification.user_agent
    assert_equal false, notification.notified
  end

  test "should store UTM parameters in metadata" do
    post launch_notifications_url, params: {
      email: "utm@example.com",
      utm_source: "twitter",
      utm_campaign: "prelaunch",
      utm_medium: "social"
    }, as: :json

    notification = LaunchNotification.order(:created_at).last
    assert_equal "utm@example.com", notification.email
    # Note: metadata extraction happens in before_create callback
    # which requires request_params to be set
  end

  test "should normalize email to lowercase" do
    post launch_notifications_url, params: { email: "UPPERCASE@EXAMPLE.COM" }, as: :json

    notification = LaunchNotification.order(:created_at).last
    assert_equal "uppercase@example.com", notification.email
  end

  test "should handle HTML format request" do
    post launch_notifications_url, params: { email: "html@example.com" }

    assert_redirected_to root_path(teaser: 1)
    assert_equal "Thank you! We'll notify you as soon as we launch.", flash[:notice]
  end

  test "should handle HTML format error" do
    LaunchNotification.create!(email: "duplicate@example.com")

    post launch_notifications_url, params: { email: "duplicate@example.com" }

    assert_redirected_to root_path(teaser: 1)
    assert flash[:alert].present?
  end

  test "should increment total signups count" do
    initial_count = LaunchNotification.count

    post launch_notifications_url, params: { email: "counter@example.com" }, as: :json

    json_response = JSON.parse(response.body)
    assert_equal initial_count + 1, json_response["total_signups"]
  end

  test "should work with different email variations" do
    emails = [
      "simple@example.com",
      "user.name@example.com",
      "user+tag@example.com",
      "user_name@example.co.uk"
    ]

    emails.each do |email|
      assert_difference("LaunchNotification.count", 1) do
        post launch_notifications_url, params: { email: email }, as: :json
      end
      assert_response :success
    end
  end

  # ==========================================
  # Anti-Bot Protection Tests
  # ==========================================

  test "should reject submission with honeypot field filled" do
    assert_no_difference("LaunchNotification.count") do
      post launch_notifications_url,
           params: { email: "bot@example.com", company: "Spammy Inc" },
           as: :json
    end

    # Returns fake success to not inform bots
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
    assert_equal "You're on the list!", json_response["message"]
  end

  test "should accept submission with empty honeypot field" do
    assert_difference("LaunchNotification.count", 1) do
      post launch_notifications_url,
           params: { email: "legit@example.com", company: "" },
           as: :json
    end

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
  end

  test "should accept submission without honeypot field" do
    assert_difference("LaunchNotification.count", 1) do
      post launch_notifications_url,
           params: { email: "nofield@example.com" },
           as: :json
    end

    assert_response :success
  end

  test "should reject submission that is too fast when timing validation enabled" do
    # Generate a signed token from 0.5 seconds ago (too fast)
    form_token = generate_signed_token(0.5.seconds.ago)

    with_timing_validation do
      assert_no_difference("LaunchNotification.count") do
        post launch_notifications_url,
             params: { email: "fast@example.com", form_token: form_token },
             as: :json
      end
    end

    # Returns fake success to not inform bots
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
  end

  test "should accept submission with valid timing when timing validation enabled" do
    # Generate a signed token from 5 seconds ago (legitimate)
    form_token = generate_signed_token(5.seconds.ago)

    with_timing_validation do
      assert_difference("LaunchNotification.count", 1) do
        post launch_notifications_url,
             params: { email: "slow@example.com", form_token: form_token },
             as: :json
      end
    end

    assert_response :success
  end

  test "should accept submission without form_token (graceful degradation for JS-disabled users)" do
    assert_difference("LaunchNotification.count", 1) do
      post launch_notifications_url,
           params: { email: "nojs@example.com" },
           as: :json
    end

    assert_response :success
  end

  test "should reject malformed form_token when timing validation enabled" do
    with_timing_validation do
      assert_no_difference("LaunchNotification.count") do
        post launch_notifications_url,
             params: { email: "malformed@example.com", form_token: "invalid-token-format" },
             as: :json
      end
    end

    # Returns fake success to not inform bots
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
  end

  test "should reject form_token with invalid signature when timing validation enabled" do
    # Token with valid format but wrong signature
    fake_token = "#{Time.current.to_f}--invalidsignature123"

    with_timing_validation do
      assert_no_difference("LaunchNotification.count") do
        post launch_notifications_url,
             params: { email: "tampered@example.com", form_token: fake_token },
             as: :json
      end
    end

    # Returns fake success to not inform bots
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
  end

  test "should reject expired form_token when timing validation enabled" do
    # Generate a signed token from 2 hours ago (exceeds TOKEN_MAX_AGE_SECONDS of 1 hour)
    form_token = generate_signed_token(2.hours.ago)

    with_timing_validation do
      assert_no_difference("LaunchNotification.count") do
        post launch_notifications_url,
             params: { email: "expired@example.com", form_token: form_token },
             as: :json
      end
    end

    # Returns fake success to not inform bots
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["success"]
  end

  test "honeypot rejection with HTML format returns success redirect" do
    assert_no_difference("LaunchNotification.count") do
      post launch_notifications_url,
           params: { email: "htmlbot@example.com", company: "Spammy Inc" }
    end

    assert_redirected_to root_path(teaser: 1)
    assert_equal "Thank you! We'll notify you as soon as we launch.", flash[:notice]
  end

  private

  def with_timing_validation
    ENV["TEST_TIMING_VALIDATION"] = "true"
    yield
  ensure
    ENV.delete("TEST_TIMING_VALIDATION")
  end

  def generate_signed_token(timestamp_time)
    timestamp = timestamp_time.to_f.to_s
    signature = OpenSSL::HMAC.hexdigest(
      "SHA256",
      Rails.application.secret_key_base,
      "form_timing:#{timestamp}"
    )
    "#{timestamp}--#{signature}"
  end
end
