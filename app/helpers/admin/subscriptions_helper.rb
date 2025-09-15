module Admin::SubscriptionsHelper
  # Returns a safe label for a user in select options.
  # Prefer the decrypted email when available; fall back to a generic label
  # if the email is blank or cannot be decrypted in this environment (e.g. test fixtures).
  def user_option_label(user)
    email = begin
      user.email_address
    rescue ActiveRecord::Encryption::Errors::Decryption
      nil
    end

    email.present? ? email : "User ##{user.id}"
  end
end

