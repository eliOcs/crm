class Company < ApplicationRecord
  belongs_to :user
  has_many :audit_logs, as: :auditable, dependent: :destroy
  has_and_belongs_to_many :contacts
  has_one_attached :logo

  validates :legal_name, presence: true
  validates :domain, uniqueness: { scope: :user_id }, allow_nil: true

  # Display name: prefer commercial name, fall back to legal name
  def display_name
    commercial_name.presence || legal_name
  end
end
