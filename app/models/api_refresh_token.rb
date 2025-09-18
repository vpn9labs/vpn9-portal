require "digest"

class ApiRefreshToken < ApplicationRecord
  belongs_to :user

  validates :token_hash, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
end
