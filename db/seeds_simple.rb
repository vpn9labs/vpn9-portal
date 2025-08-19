# Simplified seeds for testing affiliate portal
puts "=== Creating Test Affiliates ==="

# Create the main high-volume test affiliate
test_affiliate = Affiliate.find_or_create_by(email: "highvolume@example.com") do |affiliate|
  affiliate.name = "High Volume Tester"
  affiliate.code = "HIGHVOL123"
  affiliate.commission_rate = 25.0
  affiliate.status = :active
  affiliate.payout_currency = "btc"
  affiliate.payout_address = "bc1qhighvolume123456789"
  affiliate.password = "password123"
  affiliate.password_confirmation = "password123"
  affiliate.terms_accepted = true
  affiliate.minimum_payout_amount = 100.0
  affiliate.created_at = 3.months.ago
end

puts "Created test affiliate: #{test_affiliate.email} (password: password123)"

# Generate some clicks for today and past week
puts "\n=== Generating Sample Clicks ==="
landing_pages = [ "/", "/signup", "/plans", "/features", "/pricing" ]
referrers = [ "https://google.com", "https://facebook.com", "https://twitter.com", nil ]

# Past week clicks
7.times do |days_ago|
  rand(10..20).times do
    AffiliateClick.create!(
      affiliate: test_affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.#{rand(1..255)}.#{rand(1..255)}"),
      landing_page: landing_pages.sample,
      referrer: referrers.sample,
      created_at: days_ago.days.ago + rand(0..23).hours
    )
  end
end

# Today's clicks
15.times do
  AffiliateClick.create!(
    affiliate: test_affiliate,
    ip_hash: Digest::SHA256.hexdigest("10.0.#{rand(1..255)}.#{rand(1..255)}"),
    landing_page: landing_pages.sample,
    referrer: referrers.sample,
    created_at: Time.current - rand(0..12).hours
  )
end

puts "Generated #{test_affiliate.affiliate_clicks.count} clicks"

# Create a few test users and referrals
puts "\n=== Generating Sample Referrals ==="

# Past referrals
5.times do |i|
  user = User.create!(
    email_address: "testuser#{i}@example.com",
    created_at: (i + 1).weeks.ago
  )

  referral = Referral.create!(
    affiliate: test_affiliate,
    user: user,
    referral_code: test_affiliate.code,
    ip_hash: Digest::SHA256.hexdigest("172.16.#{rand(1..255)}.#{rand(1..255)}"),
    landing_page: "/signup",
    status: i < 3 ? :converted : :pending,
    converted_at: i < 3 ? (i + 1).weeks.ago + 1.day : nil,
    created_at: (i + 1).weeks.ago
  )

  # Create payment and commission for converted referrals
  if referral.converted?
    plan = Plan.first || Plan.create!(
      name: "Monthly Plan",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )

    payment = Payment.create!(
      user: user,
      plan: plan,
      amount: plan.price,
      currency: plan.currency,
      status: :paid,
      transaction_id: "test_txn_#{SecureRandom.hex(4)}",
      paid_at: referral.converted_at,
      created_at: referral.converted_at
    )

    Commission.create!(
      affiliate: test_affiliate,
      payment: payment,
      referral: referral,
      amount: (payment.amount * test_affiliate.commission_rate / 100).round(2),
      currency: payment.currency,
      commission_rate: test_affiliate.commission_rate,
      status: i == 0 ? :paid : (i == 1 ? :approved : :pending),
      created_at: referral.converted_at
    )
  end
end

# Recent pending referral
recent_user = User.create!(
  email_address: "recent_test@example.com"
)

Referral.create!(
  affiliate: test_affiliate,
  user: recent_user,
  referral_code: test_affiliate.code,
  ip_hash: Digest::SHA256.hexdigest("203.0.113.#{rand(1..255)}"),
  landing_page: "/signup",
  status: :pending,
  created_at: 2.hours.ago
)

puts "Generated #{test_affiliate.referrals.count} referrals"
puts "Generated #{Commission.where(affiliate: test_affiliate).count} commissions"

# Print summary
puts "\n=== Summary for Test Affiliate ==="
puts "Email: highvolume@example.com"
puts "Password: password123"
puts "Total Clicks: #{test_affiliate.affiliate_clicks.count}"
puts "Total Referrals: #{test_affiliate.referrals.count}"
puts "Converted: #{test_affiliate.referrals.converted.count}"
puts "Pending Commissions: #{test_affiliate.commissions.pending.count} ($#{test_affiliate.commissions.pending.sum(:amount).round(2)})"
puts "Approved Commissions: #{test_affiliate.commissions.approved.count} ($#{test_affiliate.commissions.approved.sum(:amount).round(2)})"
puts "Paid Commissions: #{test_affiliate.commissions.paid.count} ($#{test_affiliate.commissions.paid.sum(:amount).round(2)})"

puts "\n=== Seed data complete ==="
