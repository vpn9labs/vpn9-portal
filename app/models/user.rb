require "eff_wordlist"
require "digest"

class User < ApplicationRecord
  include OptionalPassword

  enum :status, { active: 0, locked: 1, closed: 2 }

  # ───── Passphrase Configuration ─────
  PASSPHRASE_WORDS = 7
  RECOVERY_BITS    = 256
  ARGON_OPS        = 4
  ARGON_MEM_MB     = 256

  # ───── Defaul Device Limit ─────
  DEFAULT_DEVICE_LIMIT = 5

  has_many :sessions, dependent: :destroy
  has_many :subscriptions
  has_many :payments
  has_many :devices, dependent: :destroy
  has_one :referral
  has_one :referring_affiliate, through: :referral, source: :affiliate

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  encrypts :email_address, deterministic: true

  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true, allow_nil: true }

  # Soft delete functionality
  default_scope { where(deleted_at: nil) }
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { unscoped.where.not(deleted_at: nil) }
  scope :with_deleted, -> { unscoped }

  before_create :generate_passphrase
  before_create :populate_recovery_code

  # Argon2id digest
  def self.argon_hash(raw)
    Argon2::Password.new(
      t_cost: ARGON_OPS,
      m_cost_kb: ARGON_MEM_MB * 1024
    ).create(raw)
  end

  def verify_passphrase!(candidate)
    # Extract the stored hash (skip the search prefix)
    stored_hash = passphrase_hash[16..-1]
    result = Argon2::Password.verify_password(candidate, stored_hash)
    Rails.logger.info "Passphrase verification for user #{id}: candidate=#{candidate.inspect}, result=#{result}"
    result
  end

  # Passphrase authentication (with optional email/password)
  def self.authenticate_by_passphrase(identifier, email: nil)
    # Parse identifier - could be "passphrase" or "passphrase:password"
    passphrase, custom_password = identifier.split(":", 2)

    if email.present?
      # Find by email if provided
      user = find_by(email_address: email)
    else
      # Find by passphrase hash (we store a searchable hash)
      search_hash = Digest::SHA256.hexdigest(passphrase)[0..15]
      user = where("passphrase_hash LIKE ?", "#{search_hash}%").first
    end

    return nil unless user

    # Verify the full identifier (passphrase + optional password)
    full_identifier = custom_password.present? ? "#{passphrase}:#{custom_password}" : passphrase
    user.verify_passphrase!(full_identifier) ? user : nil
  rescue
    nil
  end

  # Regenerate passphrase (for password recovery)
  def regenerate_passphrase!
    generate_passphrase
    save!
    @issued_passphrase
  end

  # Check if user has active subscription
  def has_active_subscription?
    subscriptions.current.exists?
  end

  def current_subscription
    subscriptions.current.first
  end

  def device_limit
    current_subscription&.plan&.device_limit || DEFAULT_DEVICE_LIMIT
  end

  def can_add_device?
    devices.count < device_limit
  end

  def devices_remaining
    [ device_limit - devices.count, 0 ].max
  end

  # Soft delete functionality
  def soft_delete!(reason: nil)
    transaction do
      self.deletion_reason = reason
      self.deleted_at = Time.current

      # Destroy all sessions (they should cascade delete)
      sessions.destroy_all

      # Clear personal data but keep the record for audit trail
      self.email_address = nil if respond_to?(:email_address=)
      self.passphrase_hash = nil
      self.recovery_code = nil

      # Save without validation to ensure deletion completes
      save!(validate: false)
    end
  end

  def deleted?
    deleted_at.present?
  end

  private

    def generate_passphrase
      # Generate random passphrase
      passphrase = EffWordlist.generate_passphrase(PASSPHRASE_WORDS)
      @issued_passphrase = passphrase

      # If user provided a password during signup, append it
      if password.present?
        full_identifier = "#{passphrase}:#{password}"
      else
        full_identifier = passphrase
      end

      # Store Argon2 hash of the full identifier
      argon_hash = self.class.argon_hash(full_identifier)

      # Also store first part of SHA256 hash for lookup (first 16 chars)
      # This allows finding user by passphrase without storing it in plaintext
      search_hash = Digest::SHA256.hexdigest(passphrase)[0..15]
      self.passphrase_hash = "#{search_hash}#{argon_hash}"
    end

    def populate_recovery_code
      self.recovery_code ||= Base58.binary_to_base58(
        SecureRandom.random_bytes(RECOVERY_BITS / 8)
      )
    end

    # surfaces passphrase after create (service layer will read attr_reader)
    attr_reader :issued_passphrase
end
