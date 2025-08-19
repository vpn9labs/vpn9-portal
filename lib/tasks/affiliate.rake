namespace :affiliate do
  desc "Create a test affiliate for development"
  task create_test: :environment do
    affiliate = Affiliate.find_or_create_by!(code: "TESTDEMO") do |a|
      a.name = "Test Affiliate"
      a.email = "test@affiliate.com"
      a.payout_address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
      a.payout_currency = "btc"
      a.commission_rate = 20.0
      a.status = :active
    end

    puts "Test affiliate created:"
    puts "  Code: #{affiliate.code}"
    puts "  Commission Rate: #{affiliate.commission_rate}%"
    puts "  Referral Link: #{affiliate.referral_link}"
    puts ""
    puts "Test the affiliate tracking by visiting:"
    puts "  http://localhost:3000?ref=#{affiliate.code}"
    puts "  http://localhost:3000/signup?ref=#{affiliate.code}"
  end

  desc "Show affiliate statistics"
  task :stats, [ :code ] => :environment do |t, args|
    if args[:code].blank?
      puts "Usage: rails affiliate:stats[CODE]"
      exit 1
    end

    affiliate = Affiliate.find_by(code: args[:code].upcase)

    if affiliate.nil?
      puts "Affiliate with code '#{args[:code]}' not found"
      exit 1
    end

    puts "Affiliate Statistics for #{affiliate.name || affiliate.code}"
    puts "=" * 50
    puts "Status: #{affiliate.status.humanize}"
    puts "Commission Rate: #{affiliate.commission_rate}%"
    puts ""
    puts "Performance Metrics:"
    puts "  Total Clicks: #{affiliate.total_clicks}"
    puts "  Total Referrals: #{affiliate.referrals.count}"
    puts "  Converted Referrals: #{affiliate.referrals.converted.count}"
    puts "  Conversion Rate: #{affiliate.conversion_rate}%"
    puts ""
    puts "Financial Summary:"
    puts "  Lifetime Earnings: $#{affiliate.lifetime_earnings}"
    puts "  Pending Balance: $#{affiliate.pending_balance}"
    puts "  Paid Out Total: $#{affiliate.paid_out_total}"
    puts ""
    puts "Commission Breakdown:"
    puts "  Pending: #{affiliate.commissions.pending.count} ($#{affiliate.total_pending_commission})"
    puts "  Approved: #{affiliate.commissions.approved.count} ($#{affiliate.total_approved_commission})"
    puts "  Paid: #{affiliate.commissions.paid.count}"
    puts "  Cancelled: #{affiliate.commissions.cancelled.count}"
    puts ""
    puts "Referral Link: #{affiliate.referral_link}"
  end
end
