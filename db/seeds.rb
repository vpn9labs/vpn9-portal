# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create default admin user
puts "=== Creating Default Admin ==="
admin = Admin.find_or_create_by(email: "admin@vpn9.com") do |a|
  a.password = "admin123456"
  a.password_confirmation = "admin123456"
end
puts "Created admin: #{admin.email} (password: admin123456)"
puts ""

# Create sample plans
plans = [
  {
    name: "Monthly Plan",
    description: "Get 30 days of VPN access",
    price: 9.99,
    currency: "USD",
    duration_days: 30,
    device_limit: 5,
    features: [ "Unlimited bandwidth", "Access to all servers", "No logs policy", "24/7 support" ]
  },
  {
    name: "Quarterly Plan",
    description: "Get 90 days of VPN access and save 10%",
    price: 26.99,
    currency: "USD",
    duration_days: 90,
    device_limit: 5,
    features: [ "Unlimited bandwidth", "Access to all servers", "No logs policy", "24/7 support", "10% discount" ]
  },
  {
    name: "Annual Plan",
    description: "Get 365 days of VPN access and save 25%",
    price: 89.99,
    currency: "USD",
    duration_days: 365,
    device_limit: 10,
    features: [ "Unlimited bandwidth", "Access to all servers", "No logs policy", "Priority 24/7 support", "25% discount", "Free email forwarding" ]
  }
]

plans.each do |plan_attrs|
  Plan.find_or_create_by(name: plan_attrs[:name]) do |plan|
    plan.description = plan_attrs[:description]
    plan.price = plan_attrs[:price]
    plan.currency = plan_attrs[:currency]
    plan.duration_days = plan_attrs[:duration_days]
    plan.device_limit = plan_attrs[:device_limit]
    plan.features = plan_attrs[:features]
    plan.active = true
  end
end

puts "Created #{Plan.count} plans"

# Create high-volume test affiliate
puts "\n=== Creating High-Volume Test Affiliate ==="

# Create the main test affiliate
test_affiliate = Affiliate.find_or_create_by(email: "highvolume@example.com") do |affiliate|
  affiliate.name = "High Volume Tester"
  affiliate.code = "HIGHVOL123"
  affiliate.commission_rate = 25.0 # Higher commission for testing
  affiliate.status = :active
  affiliate.payout_currency = "btc"
  affiliate.payout_address = "bc1qhighvolume123456789"
  affiliate.password = "password123"
  affiliate.password_confirmation = "password123"
  affiliate.terms_accepted = true
  affiliate.minimum_payout_amount = 100.0
  affiliate.company_name = "Test Marketing Agency"
  affiliate.website = "https://testmarketing.example.com"
  affiliate.promotional_methods = "Content marketing, SEO, Social media advertising, Email campaigns"
  affiliate.expected_referrals = 1000
  affiliate.country = "United States"
  affiliate.created_at = 6.months.ago
end

puts "Created test affiliate: #{test_affiliate.email} (password: password123)"

# Create additional affiliates for comparison
other_affiliates = [
  {
    email: "medium@example.com",
    name: "Medium Volume Affiliate",
    code: "MEDIUM456",
    commission_rate: 20.0,
    status: :active
  },
  {
    email: "lowvolume@example.com",
    name: "Low Volume Affiliate",
    code: "LOW789",
    commission_rate: 20.0,
    status: :active
  },
  {
    email: "pending@example.com",
    name: "Pending Approval",
    code: "PEND012",
    commission_rate: 20.0,
    status: :pending
  }
]

other_affiliates.each do |attrs|
  Affiliate.find_or_create_by(email: attrs[:email]) do |affiliate|
    affiliate.name = attrs[:name]
    affiliate.code = attrs[:code]
    affiliate.commission_rate = attrs[:commission_rate]
    affiliate.status = attrs[:status]
    affiliate.payout_currency = "eth"
    affiliate.payout_address = "0x#{attrs[:code].downcase}"
    affiliate.password = "password123"
    affiliate.password_confirmation = "password123"
    affiliate.terms_accepted = true
    affiliate.minimum_payout_amount = 100.0
    affiliate.created_at = 4.months.ago
  end
end

puts "Created #{Affiliate.count} total affiliates"

# Generate affiliate clicks for the past 3 months
puts "\n=== Generating Affiliate Clicks ==="

# Different landing pages and referrers for realistic data
landing_pages = [ "/", "/signup", "/plans", "/features", "/pricing", "/about", "/security" ]
referrers = [
  "https://google.com/search?q=best+vpn",
  "https://facebook.com/posts/123456",
  "https://twitter.com/status/789012",
  "https://reddit.com/r/vpn/comments/abc123",
  "https://youtube.com/watch?v=xyz789",
  "https://blog.example.com/vpn-review",
  "https://techsite.com/best-vpn-2024",
  nil # Direct traffic
]

# Generate clicks with realistic distribution over 3 months
click_count = 0
90.downto(1) do |days_ago|
  date = days_ago.days.ago

  # More clicks on weekdays, fewer on weekends
  is_weekend = date.wday == 0 || date.wday == 6
  daily_clicks = is_weekend ? rand(5..10) : rand(10..20)

  # High volume affiliate gets most clicks
  daily_clicks.times do
    # 70% for high volume, 20% medium, 10% low
    affiliate = case rand(100)
    when 0..69
      test_affiliate
    when 70..89
      Affiliate.find_by(code: "MEDIUM456")
    else
      Affiliate.find_by(code: "LOW789")
    end

    next unless affiliate

    AffiliateClick.create!(
      affiliate: affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.#{rand(1..255)}.#{rand(1..255)}"),
      landing_page: landing_pages.sample,
      referrer: referrers.sample,
      user_agent_hash: Digest::SHA256.hexdigest("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"),
      created_at: date + rand(0..23).hours + rand(0..59).minutes
    )
    click_count += 1
  end
end

puts "Generated #{click_count} affiliate clicks"

# Generate users and referrals
puts "\n=== Generating Referrals and Users ==="

referral_count = 0
conversion_count = 0

# Create users and referrals with realistic conversion rates
90.downto(1) do |days_ago|
  date = days_ago.days.ago

  # 5-10% conversion rate from clicks
  daily_signups = rand(1..3)

  daily_signups.times do
    # Distribute referrals: 75% high volume, 20% medium, 5% low
    affiliate = case rand(100)
    when 0..74
      test_affiliate
    when 75..94
      Affiliate.find_by(code: "MEDIUM456")
    else
      Affiliate.find_by(code: "LOW789")
    end

    next unless affiliate

    # Create user
    user = User.create!(
      email_address: "user#{SecureRandom.hex(4)}@example.com",
      created_at: date
    )

    # Create referral
    referral = Referral.create!(
      affiliate: affiliate,
      user: user,
      referral_code: affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("10.0.#{rand(1..255)}.#{rand(1..255)}"),
      landing_page: landing_pages.sample,
      status: :pending,
      created_at: date
    )
    referral_count += 1

    # 60% of referrals convert to paid customers
    if rand(100) < 60
      conversion_date = date + rand(1..7).days

      # Skip if conversion would be in the future
      next if conversion_date > Time.current

      referral.update!(
        status: :converted,
        converted_at: conversion_date
      )
      conversion_count += 1

      # Create payment and commission for converted referrals
      plan = Plan.all.sample

      # Create payment
      crypto_currency = [ "BTC", "ETH", "USDT" ].sample
      payment = Payment.create!(
        user: user,
        plan: plan,
        amount: plan.price,
        currency: plan.currency,
        status: :paid,
        transaction_id: "txn_#{SecureRandom.hex(8)}",
        crypto_currency: crypto_currency,
        crypto_amount: plan.price * 0.000025, # Simulated crypto amount
        paid_at: conversion_date,
        created_at: conversion_date
      )

      # Create commission
      commission_amount = (payment.amount * affiliate.commission_rate / 100).round(2)

      # Determine commission status based on age
      commission_status = if conversion_date < 30.days.ago
        [ :paid, :approved ].sample # Older commissions are processed
      elsif conversion_date < 7.days.ago
        [ :approved, :pending ].sample # Recent commissions might be approved
      else
        :pending # Very recent commissions are pending
      end

      Commission.create!(
        affiliate: affiliate,
        payment: payment,
        referral: referral,
        amount: commission_amount,
        currency: payment.currency,
        commission_rate: affiliate.commission_rate,
        status: commission_status,
        created_at: conversion_date
      )
    end
  end
end

puts "Generated #{User.count} users"
puts "Generated #{referral_count} referrals (#{conversion_count} converted)"
puts "Generated #{Payment.count} payments"
puts "Generated #{Commission.count} commissions"

# Mark some older approved commissions as paid (simulating payout history)
puts "\n=== Simulating Payout History ==="

paid_count = 0

# Mark commissions older than 30 days as paid
[ 60, 30 ].each do |days_ago|
  payout_date = days_ago.days.ago

  # Get approved commissions for high-volume affiliate up to this date
  eligible_commissions = test_affiliate.commissions
    .where(status: :approved)
    .where("created_at <= ?", payout_date)

  if eligible_commissions.any?
    total_amount = eligible_commissions.sum(:amount)

    # Only mark as paid if above minimum payout amount
    if total_amount >= test_affiliate.minimum_payout_amount
      eligible_commissions.update_all(status: :paid)
      paid_count += eligible_commissions.count
      puts "Marked #{eligible_commissions.count} commissions as paid ($#{total_amount.round(2)})"
    end
  end
end

puts "Marked #{paid_count} commissions as paid"

# Generate some recent activity for dashboard display
puts "\n=== Generating Recent Activity ==="

# Today's clicks
20.times do
  AffiliateClick.create!(
    affiliate: test_affiliate,
    ip_hash: Digest::SHA256.hexdigest("172.16.#{rand(1..255)}.#{rand(1..255)}"),
    landing_page: landing_pages.sample,
    referrer: referrers.sample,
    user_agent_hash: Digest::SHA256.hexdigest("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"),
    created_at: Time.current - rand(0..23).hours
  )
end

# Recent referral
recent_user = User.create!(
  email_address: "recent#{SecureRandom.hex(4)}@example.com"
)

recent_referral = Referral.create!(
  affiliate: test_affiliate,
  user: recent_user,
  referral_code: test_affiliate.code,
  ip_hash: Digest::SHA256.hexdigest("203.0.113.#{rand(1..255)}"),
  landing_page: "/signup",
  status: :pending,
  created_at: 2.hours.ago
)

puts "Generated recent activity"

# Print summary statistics
puts "\n=== Summary Statistics for High-Volume Affiliate ==="
puts "Email: highvolume@example.com"
puts "Password: password123"
puts "Total Clicks: #{test_affiliate.affiliate_clicks.count}"
puts "Total Referrals: #{test_affiliate.referrals.count}"
puts "Converted Referrals: #{test_affiliate.referrals.converted.count}"
puts "Pending Commissions: #{test_affiliate.commissions.pending.count} ($#{test_affiliate.commissions.pending.sum(:amount).round(2)})"
puts "Approved Commissions: #{test_affiliate.commissions.approved.count} ($#{test_affiliate.commissions.approved.sum(:amount).round(2)})"
puts "Paid Commissions: #{test_affiliate.commissions.paid.count} ($#{test_affiliate.commissions.paid.sum(:amount).round(2)})"
puts "Total Earnings: $#{test_affiliate.commissions.sum(:amount).round(2)}"
puts "\n=== Seed data generation complete ==="#
