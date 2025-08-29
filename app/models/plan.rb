class Plan < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_many :payments, dependent: :destroy

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  # Allow lifetime plans without duration_days
  validates :duration_days, presence: true, numericality: { greater_than: 0 }, unless: :lifetime?
  validates :device_limit, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  scope :active, -> { where(active: true) }

  def display_price
    if currency == "USD"
      "$#{price} #{currency}"
    elsif currency == "EUR"
      "€#{price} #{currency}"
    elsif currency == "GBP"
      "£#{price} #{currency}"
    else
      "#{price} #{currency}"
    end
  end

  def monthly?
    !lifetime? && (duration_days == 30 || duration_days == 31)
  end

  def yearly?
    !lifetime? && (duration_days == 365 || duration_days == 366)
  end

  def display_device_limit
    device_limit == 100 ? "Unlimited" : device_limit.to_s
  end

  def display_duration
    return "Lifetime" if lifetime?
    case duration_days
    when 30, 31 then "Monthly"
    when 365, 366 then "Yearly"
    when 7 then "Weekly"
    when 90 then "Quarterly"
    else "#{duration_days} days"
    end
  end

  def active_subscriptions_count
    subscriptions.active.count
  end

  def total_revenue
    payments.successful.sum(:amount)
  end

  def can_be_deleted?
    !subscriptions.exists?
  end
end
