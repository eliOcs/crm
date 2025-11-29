class Company < ApplicationRecord
  belongs_to :user
  has_many :contacts, dependent: :nullify
  has_one_attached :logo

  validates :name, presence: true
end
