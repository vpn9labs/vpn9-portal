class Relay < ApplicationRecord
  belongs_to :location

  enum :status, {
    inactive: 0,
    active: 1,
    maintenance: 2
  }

  validates :name, presence: true, uniqueness: true
  validates :hostname, presence: true, uniqueness: true
  validates :ipv4_address, presence: true
  validate :valid_ipv4_address
  validate :valid_ipv6_address
  validates :public_key, presence: true
  validates :port, presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 65535 }
  validates :status, presence: true

  private

  def valid_ipv4_address
    return if ipv4_address.blank?

    octets = ipv4_address.split(".")

    unless octets.length == 4
      errors.add(:ipv4_address, "must have 4 octets")
      return
    end

    octets.each do |octet|
      value = octet.to_i
      unless octet =~ /\A\d+\z/ && value >= 0 && value <= 255
        errors.add(:ipv4_address, "octets must be between 0 and 255")
        return
      end
    end
  end

  def valid_ipv6_address
    return if ipv6_address.blank?

    # Basic IPv6 validation - allow common formats
    # Full IPv6: 2001:0db8:0000:0000:0000:8a2e:0370:7334
    # Compressed: 2001:db8::8a2e:370:7334
    # IPv4 mapped: ::ffff:192.0.2.1

    # Remove any whitespace
    addr = ipv6_address.strip

    # Check for valid characters
    unless addr =~ /\A[0-9a-fA-F:\.]+\z/
      errors.add(:ipv6_address, "contains invalid characters")
      return
    end

    # Very basic check - should have at least one colon for IPv6
    unless addr.include?(":")
      errors.add(:ipv6_address, "is not a valid IPv6 address")
      return
    end

    # Check for multiple :: (only one compression allowed)
    if addr.scan("::").length > 1
      errors.add(:ipv6_address, "can only have one :: compression")
      nil
    end
  end
end
