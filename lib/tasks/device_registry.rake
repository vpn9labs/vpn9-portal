namespace :device_registry do
  desc "Rebuild the device registry in Redis from the database"
  task rebuild: :environment do
    puts "Rebuilding device registry..."
    DeviceRegistry.rebuild!
    puts "Device registry rebuild complete."
  end

  desc "Print all device records stored in the Redis-backed DeviceRegistry"
  task :print, [ :only_active ] => :environment do |t, args|
    only_active = ActiveModel::Type::Boolean.new.cast(args[:only_active])

    ids = if only_active
      DeviceRegistry.global_active_set.members
    else
      Device.pluck(:id)
    end

    puts "DeviceRegistry records (#{ids.size} devices#{only_active ? ' - only active' : ''}):"
    puts "=" * 80

    ids.each do |id|
      begin
        hash = DeviceRegistry.device_hash(id)
        data = hash.respond_to?(:to_h) ? hash.to_h : {}
      rescue => e
        data = { error: "#{e.class}: #{e.message}" }
      end

      if data.nil? || data.empty?
        puts "- id=#{id} (no data in Redis)"
      else
        # Print a compact, readable line per device
        summary = {
          id: data["id"],
          user_id: data["user_id"],
          name: data["name"],
          public_key: data["public_key"],
          ipv4: data["ipv4"],
          ipv6: data["ipv6"],
          allowed_ips: data["allowed_ips"]
        }.compact
        puts "- #{summary.to_json}"
      end
    end

    puts "\nTip: pass only_active=true to limit to active devices"
    puts "e.g. rails device_registry:print[true]"
  end
end
