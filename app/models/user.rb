class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_many :companies, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :emails, dependent: :destroy
  has_one :microsoft_credential, dependent: :destroy

  def microsoft_connected?
    microsoft_credential.present?
  end

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, on: :create
  validates :locale, inclusion: { in: %w[en es] }
end
