#
# User represents an account in VPN9's privacy‑first system.
#
# Responsibilities
# - Passphrase‑based authentication with optional appended password
#   (memorized phrase generated from EFF wordlist; no emails required).
# - Status lifecycle via `status` enum (`active`, `locked`, `closed`).
# - Owns subscriptions, payments, and devices with soft‑delete semantics.
# - Enforces device limits derived from the current subscription plan.
#
# Authentication Model
# - Users are identified by an EFF‑wordlist passphrase. Optionally, a user‑chosen
#   password may be appended to strengthen the identifier (`passphrase:password`).
# - We never store the passphrase in plaintext. For lookup, we store the first
#   16 hex characters of SHA256(passphrase) as a prefix + Argon2id of the full
#   identifier (passphrase or passphrase:password).
# - `authenticate_by_passphrase` verifies this identifier and returns the user.
#
# Soft Delete
# - Users can be soft‑deleted. Default scope excludes deleted users while
#   keeping records for audit. Associated sessions are destroyed and select
#   personal fields are cleared.
#
# Device Limits
# - Device limits come from the user's current subscription plan. If there is
#   no active subscription, a sensible default is used (`DEFAULT_DEVICE_LIMIT`).
# - Helpers `can_add_device?` and `devices_remaining` expose current capacity.
#
# @!attribute [rw] email_address
#   Encrypted email (optional); deterministic encryption for uniqueness.
#   @return [String, nil]
# @!attribute [rw] passphrase_hash
#   Searchable prefix + Argon2id hash of the full credential identifier.
#   @return [String]
# @!attribute [rw] recovery_code
#   Base58 recovery code for account recovery.
#   @return [String]
# @!attribute [rw] deleted_at
#   Timestamp for soft deletion; default scope excludes deleted users.
#   @return [ActiveSupport::TimeWithZone, nil]
# @!attribute [rw] deletion_reason
#   Optional reason recorded at soft deletion time.
#   @return [String, nil]
# @!attribute [r] status
#   Lifecycle state (`active`, `locked`, `closed`).
#   @return [String]
#
# @!constant PASSPHRASE_WORDS
#   Number of words to generate for new passphrases.
#   @return [Integer]
# @!constant RECOVERY_BITS
#   Size of recovery code in bits.
#   @return [Integer]
# @!constant ARGON_OPS
#   Argon2 iterations (time cost).
#   @return [Integer]
# @!constant ARGON_MEM_MB
#   Argon2 memory cost in MB.
#   @return [Integer]
# @!constant DEFAULT_DEVICE_LIMIT
#   Default maximum devices when no subscription exists.
#   @return [Integer]
#
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
  # Derive an Argon2id hash for a given raw credential identifier.
  #
  # @param raw [String] The credential identifier (passphrase or passphrase:password)
  # @return [String] Argon2id hash
  def self.argon_hash(raw)
    Argon2::Password.new(
      t_cost: ARGON_OPS,
      m_cost_kb: ARGON_MEM_MB * 1024
    ).create(raw)
  end

  # Verify the given full identifier against the stored hash.
  #
  # @param candidate [String] passphrase or passphrase:password
  # @return [Boolean]
  def verify_passphrase!(candidate)
    # Extract the stored hash (skip the search prefix)
    stored_hash = passphrase_hash[16..-1]
    result = Argon2::Password.verify_password(candidate, stored_hash)
    result
  end

  # Passphrase authentication (with optional email/password)
  #
  # Authenticate a user either by email+passphrase or by passphrase only.
  # When authenticating by passphrase only, we find by the searchable prefix
  # (first 16 hex chars of SHA256(passphrase)) and then verify the full
  # identifier using Argon2id.
  #
  # @param identifier [String] passphrase or passphrase:password
  # @param email [String, nil] optional email to locate the user first
  # @return [User, nil]
  # @example
  #   User.authenticate_by_passphrase("word1-word2-...-word7")
  #   User.authenticate_by_passphrase("word1-...-word7:custompw")
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
  #
  # Generates a new passphrase and updates the stored hashes.
  # Returns the newly issued passphrase via an attr_reader.
  #
  # @return [String] newly generated passphrase
  def regenerate_passphrase!
    generate_passphrase
    save!
    @issued_passphrase
  end

  # Check if user has active subscription
  def has_active_subscription?
    subscriptions.current.exists?
  end

  # The user's current active subscription, if any.
  # @return [Subscription, nil]
  def current_subscription
    subscriptions.current.first
  end

  # Max devices allowed for the user (from plan or default)
  # @return [Integer]
  def device_limit
    current_subscription&.plan&.device_limit || DEFAULT_DEVICE_LIMIT
  end

  # Whether a new device can be added under the current limit
  # @return [Boolean]
  def can_add_device?
    devices.count < device_limit
  end

  # Remaining device slots available
  # @return [Integer]
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

  # Whether the user has been soft‑deleted.
  # @return [Boolean]
  def deleted?
    deleted_at.present?
  end

  private

    # Generate the passphrase and store both a searchable SHA256 prefix and
    # a secure Argon2id of the full identifier (with optional appended password).
    # Sets @issued_passphrase for surfacing post‑create/regenerate.
    # @return [void]
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

    # Populate the recovery code as Base58 random payload.
    # @return [void]
    def populate_recovery_code
      self.recovery_code ||= Base58.binary_to_base58(
        SecureRandom.random_bytes(RECOVERY_BITS / 8)
      )
    end

    # surfaces passphrase after create (service layer will read attr_reader)
    attr_reader :issued_passphrase
end
