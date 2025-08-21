require Rails.root.join("lib/ip_scrubber")

Rails.application.config.after_initialize do
  base_formatter = Rails.logger.formatter || ActiveSupport::Logger::SimpleFormatter.new
  Rails.logger.formatter = IpScrubber::Formatter.new(base_formatter)
end
