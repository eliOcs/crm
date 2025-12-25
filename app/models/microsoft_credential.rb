class MicrosoftCredential < ApplicationRecord
  belongs_to :user

  encrypts :access_token, :refresh_token

  validates :user_id, uniqueness: true
  validates :microsoft_user_id, presence: true, uniqueness: true
  validates :access_token, presence: true
  validates :refresh_token, presence: true
  validates :expires_at, presence: true

  def token_expired?
    expires_at < Time.current
  end

  def token_expiring_soon?
    expires_at < 5.minutes.from_now
  end
end
