# Scrub IP addresses (IPv4/IPv6) from all log output to avoid leaking user IPs

module IpScrubber
  IPV4_REGEX = /\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/
  IPV6_REGEX = /\b(?:[A-F0-9]{1,4}:){1,7}[A-F0-9]{1,4}\b/i
  MASK = "[FILTERED_IP]"

  class Formatter
    def initialize(base_formatter)
      @base_formatter = base_formatter
    end

    def call(severity, time, progname, msg)
      formatted = @base_formatter.call(severity, time, progname, msg)
      formatted.gsub(IPV4_REGEX, MASK).gsub(IPV6_REGEX, MASK)
    end

    # Delegate tagging support if present to remain compatible with TaggedLogging
    def push_tags(*tags)
      @base_formatter.push_tags(*tags) if @base_formatter.respond_to?(:push_tags)
    end

    def pop_tags(size = 1)
      @base_formatter.pop_tags(size) if @base_formatter.respond_to?(:pop_tags)
    end

    def clear_tags!
      @base_formatter.clear_tags! if @base_formatter.respond_to?(:clear_tags!)
    end

    def tagged(*tags)
      if @base_formatter.respond_to?(:tagged)
        @base_formatter.tagged(*tags) { yield }
      else
        yield
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @base_formatter.respond_to?(method_name, include_private) || super
    end

    def method_missing(method_name, *args, &block)
      if @base_formatter.respond_to?(method_name)
        @base_formatter.public_send(method_name, *args, &block)
      else
        super
      end
    end
  end
end
