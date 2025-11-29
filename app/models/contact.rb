class Contact < ApplicationRecord
  belongs_to :user
  has_and_belongs_to_many :companies

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: { scope: :user_id }
end
