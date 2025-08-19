require "countries"

class Location < ApplicationRecord
  has_many :relays, dependent: :destroy

  validates :country_code, presence: true, length: { is: 2 }
  validates :city, presence: true

  # Geocoding
  geocoded_by :full_address
  after_validation :geocode, if: :should_geocode?

  def country
    @country ||= ISO3166::Country[country_code.upcase]
  end

  def country_name
    country&.common_name || country&.iso_short_name || country_code.upcase
  end

  def country_flag
    # Convert country code to emoji flag
    # Each letter needs to be converted to regional indicator symbol
    return "" unless country_code.present?

    country_code.upcase.chars.map do |char|
      # Regional indicator symbols start at U+1F1E6 for 'A'
      # 'A' is 65 in ASCII, so we need to add the offset
      (char.ord - 65 + 0x1F1E6).chr(Encoding::UTF_8)
    end.join
  end

  def city_code
    city.downcase.gsub(/[^a-z0-9]/, "") if city.present?
  end

  private

  def full_address
    "#{city}, #{country_code}"
  end

  def should_geocode?
    (city_changed? || country_code_changed?) && city.present? && country_code.present?
  end
end
