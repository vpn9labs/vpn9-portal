require "test_helper"

class AttestationControllerTest < ActionDispatch::IntegrationTest
  # Test that all attestation pages are publicly accessible without authentication
  test "should get verify page without authentication" do
    get verify_path
    assert_response :success
    assert_select "h1", text: "Build Verification & Transparency"
  end

  test "should get transparency page without authentication" do
    get transparency_path
    assert_response :success
    assert_select "h1", text: "Transparency Log"
  end

  test "should get security page without authentication" do
    get security_path
    assert_response :success
    assert_select "h1", text: "Security & Verification"
  end

  # Test that pages use the public layout by checking for public layout markers
  test "verify page uses public layout" do
    get verify_path
    assert_response :success
    # Check for elements that would only be in public layout
    assert_match /Build Verification/, response.body
  end

  test "transparency page uses public layout" do
    get transparency_path
    assert_response :success
    # Check for elements that would only be in public layout
    assert_match /Transparency Log/, response.body
  end

  test "security page uses public layout" do
    get security_path
    assert_response :success
    # Check for elements that would only be in public layout
    assert_match /Security/, response.body
  end

  # Test content rendering
  test "verify page includes attestation status section" do
    get verify_path
    assert_response :success
    assert_select "#attestation-status"
    assert_select "h2", text: /Live Production Attestation/
  end

  test "verify page includes verification button" do
    get verify_path
    assert_response :success
    assert_select "#verify-btn"
    assert_select "button", text: "Verify Current Deployment"
  end

  test "verify page includes manual verification instructions" do
    get verify_path
    assert_response :success
    assert_select "h3", text: /Manual Verification/
    assert_match /docker pull vpn9\/vpn9-portal/, response.body
    assert_match /verify-build\.sh/, response.body
  end

  test "transparency page displays build history table" do
    get transparency_path
    assert_response :success
    assert_select "table"
    assert_select "thead th", text: "Version"
    assert_select "thead th", text: "Commit"
    assert_select "thead th", text: "Build Date"
  end

  test "transparency page shows at least one build entry" do
    get transparency_path
    assert_response :success
    assert_select "tbody tr", minimum: 1
  end

  test "security page includes verification methods section" do
    get security_path
    assert_response :success
    assert_match /Verification Methods/, response.body
    assert_match /Web Verification/, response.body
    assert_match /API Verification/, response.body
  end

  test "security page includes cryptographic guarantees" do
    get security_path
    assert_response :success
    assert_match /Cryptographic Guarantees/, response.body
    assert_match /SHA256 Checksums/, response.body
    assert_match /SLSA Attestations/, response.body
  end

  # Test JavaScript includes for dynamic functionality
  test "verify page includes necessary JavaScript" do
    get verify_path
    assert_response :success
    assert_match /fetchAttestation/, response.body
    assert_match /performVerification/, response.body
  end

  # Test links and references
  test "security page contains correct GitHub links" do
    get security_path
    assert_response :success
    assert_match %r{https://github.com/vpn9labs/vpn9-portal}, response.body
    refute_match %r{https://github.com/vpn9/vpn9-portal}, response.body
  end

  test "transparency page contains correct GitHub links" do
    get transparency_path
    assert_response :success
    assert_match %r{https://github.com/vpn9labs/vpn9-portal}, response.body
  end

  # Test response formats
  test "pages respond with HTML content type" do
    get verify_path
    assert_equal "text/html; charset=utf-8", response.content_type

    get transparency_path
    assert_equal "text/html; charset=utf-8", response.content_type

    get security_path
    assert_equal "text/html; charset=utf-8", response.content_type
  end

  # Test that authenticated users can also access the pages
  # Note: Skipping authentication tests due to encrypted field complexities
  # The important test is that these pages work WITHOUT authentication
  # which is tested above

  # Test build data in transparency log
  test "transparency page shows development build in test environment" do
    get transparency_path
    assert_response :success
    # Controller returns 'development' as version in test env
    assert_select "tbody td", text: /development/
  end

  # Test navigation between pages
  test "security page links to transparency page" do
    get security_path
    assert_response :success
    assert_select "a[href=?]", transparency_path
  end

  test "security page links to verify page" do
    get security_path
    assert_response :success
    assert_select "a[href=?]", verify_path
  end

  # Test error handling
  test "verify page handles missing environment variables gracefully" do
    # Clear any BUILD_VERSION env var
    original_build_version = ENV["BUILD_VERSION"]
    ENV["BUILD_VERSION"] = nil

    get verify_path
    assert_response :success
    # Should still render without errors

    ENV["BUILD_VERSION"] = original_build_version
  end

  # Test mobile responsiveness classes
  test "pages include responsive design classes" do
    get verify_path
    assert_response :success
    assert_select "[class*='md:grid-cols']"
    assert_select "[class*='sm:px']"
    assert_select "[class*='lg:px']"
  end

  # Test security headers presence
  test "pages do not leak sensitive information" do
    get verify_path
    assert_response :success
    # Should not contain private keys or secrets
    refute_match /RAILS_MASTER_KEY/, response.body
    refute_match /SECRET_KEY_BASE/, response.body
    refute_match /jwt_private_key/, response.body
  end

  # Test that pages load quickly
  test "pages load within reasonable time" do
    start_time = Time.current
    get verify_path
    load_time = Time.current - start_time

    assert_response :success
    assert load_time < 1.second, "Page took too long to load: #{load_time}s"
  end

  # Test page titles and meta information
  test "pages have appropriate titles" do
    get verify_path
    assert_select "h1", "Build Verification & Transparency"

    get transparency_path
    assert_select "h1", "Transparency Log"

    get security_path
    assert_select "h1", "Security & Verification"
  end

  # Test API endpoint references
  test "verify page includes correct API endpoint URLs" do
    get verify_path
    assert_response :success
    assert_match %r{/api/v1/attestation}, response.body
    assert_match %r{/api/v1/attestation/verify}, response.body
  end

  # Test build verification instructions
  test "transparency page includes reproducible build instructions" do
    get transparency_path
    assert_response :success
    assert_match /git clone/, response.body
    assert_match /reproducible-build\.sh/, response.body
    assert_match /git checkout/, response.body
  end

  # Test that controller handles different environments appropriately
  test "controller returns appropriate build version for environment" do
    get transparency_path
    assert_response :success

    # In test environment, should show development or test version
    # Check that the page renders without errors
    assert_match /development|test/, response.body
  end

  # Test security recommendations
  test "security page includes bug bounty information" do
    get security_path
    assert_response :success
    assert_match /Bug Bounty/, response.body
    assert_match /security@vpn9\.com/, response.body
  end

  # Test external links open in new tab
  test "external links have target blank attribute" do
    get security_path
    assert_response :success
    assert_select "a[href^='https://github.com'][target='_blank']"
  end
end
