namespace :subscriptions do
  desc "Mark expired subscriptions and deactivate devices"
  task expire: :environment do
    count = Subscription.sync_expirations!
    puts "Expired subscriptions processed for #{count} users"
  end
end
