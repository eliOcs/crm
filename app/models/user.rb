class User < ApplicationRecord
  INBOUND_EMAIL_DOMAIN = "inbox.mercuriocrm.es".freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_many :companies, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :emails, dependent: :destroy
  has_one :microsoft_credential, dependent: :destroy
  has_many :microsoft_subscriptions, dependent: :destroy
  has_many :microsoft_email_imports, dependent: :destroy

  before_create :generate_inbound_email_token

  def microsoft_connected?
    microsoft_credential.present?
  end

  # Returns the user's unique inbound email address
  # e.g., "anna.puchal.x7k9m2ab@inbox.mercuriocrm.es"
  def inbound_email_address
    "#{email_prefix}.#{inbound_email_token}@#{INBOUND_EMAIL_DOMAIN}"
  end

  # Find user by the local part of an inbound email (before @)
  def self.find_by_inbound_email(recipient)
    return nil unless recipient.to_s.downcase.end_with?("@#{INBOUND_EMAIL_DOMAIN}")

    local_part = recipient.to_s.split("@").first.downcase
    token = local_part.split(".").last
    find_by(inbound_email_token: token)
  end

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, on: :create
  validates :locale, inclusion: { in: %w[en es] }

  private

  def email_prefix
    email_address.split("@").first.parameterize.first(20)
  end

  def generate_inbound_email_token
    self.inbound_email_token = SecureRandom.alphanumeric(8).downcase
  end
end
