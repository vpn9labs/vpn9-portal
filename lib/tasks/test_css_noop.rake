# Skip css:build during tests or when explicitly requested
if ENV["SKIP_CSS_BUILD"] == "1" || ENV["RAILS_ENV"] == "test"
  begin
    Rake::Task["css:build"].clear
  rescue StandardError
    # Task may not be defined yet in some load orders; define anyway
  end

  namespace :css do
    desc "No-op css:build in test/offline"
    task :build do
      puts "Skipping css:build (test/offline environment)"
    end
  end
end
