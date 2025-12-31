class MicrosoftSubscription < ApplicationRecord
  FOLDERS = %w[inbox sentitems].freeze
  EXPIRATION_BUFFER = 30.minutes

  belongs_to :user

  validates :subscription_id, presence: true, uniqueness: true
  validates :resource, presence: true
  validates :folder, presence: true, inclusion: { in: FOLDERS }
  validates :expires_at, presence: true

  scope :expiring_soon, -> { where("expires_at < ?", EXPIRATION_BUFFER.from_now) }
  scope :expired, -> { where("expires_at < ?", Time.current) }
  scope :active, -> { where("expires_at > ?", Time.current) }

  def expiring_soon?
    expires_at < EXPIRATION_BUFFER.from_now
  end

  def expired?
    expires_at < Time.current
  end
end
