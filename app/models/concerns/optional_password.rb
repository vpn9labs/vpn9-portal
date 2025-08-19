module OptionalPassword
  extend ActiveSupport::Concern

  included do
    attr_accessor :password, :password_confirmation

    validates :password, length: { minimum: 6, allow_blank: true, allow_nil: true }
    validate :password_matches_confirmation, if: :password_present?

    private

    def password_present?
      password.present?
    end

    def password_matches_confirmation
      # Only validate if password_confirmation was actually provided (not nil or blank)
      if password_confirmation.present? && password != password_confirmation
        errors.add(:password_confirmation, "doesn't match Password")
      end
    end
  end
end
