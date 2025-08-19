class LaunchNotification < ApplicationRecord
  # Validations
  validates :email, presence: true,
                   format: { with: URI::MailTo::EMAIL_REGEXP },
                   uniqueness: { case_sensitive: false, message: "is already on the waiting list" }

  # Normalizations
  normalizes :email, with: ->(email) { email.strip.downcase }

  # Scopes
  scope :not_notified, -> { where(notified: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_source, ->(source) { where(source: source) }

  # Callbacks
  before_create :extract_metadata_from_params

  # Store request information
  attr_accessor :request_params

  private

  def extract_metadata_from_params
    return unless request_params.present?

    # Extract UTM parameters and other tracking data
    self.metadata = {
      utm_source: request_params[:utm_source],
      utm_medium: request_params[:utm_medium],
      utm_campaign: request_params[:utm_campaign],
      utm_term: request_params[:utm_term],
      utm_content: request_params[:utm_content],
      ref: request_params[:ref]
    }.compact
  end
end
