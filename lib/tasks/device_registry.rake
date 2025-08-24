namespace :device_registry do
  desc "Rebuild the device registry in Redis from the database"
  task rebuild: :environment do
    puts "Rebuilding device registry..."
    DeviceRegistry.rebuild!
    puts "Device registry rebuild complete."
  end
end
