class Company < ApplicationRecord
  belongs_to :user
  has_many :contacts, dependent: :nullify
  has_one_attached :logo

  validates :name, presence: true
  validates :domain, uniqueness: { scope: :user_id }, allow_nil: true

  before_validation :normalize_domain_from_website

  def self.normalize_domain(url)
    return nil if url.blank?
    url = url.downcase.strip
    # Add scheme if missing for URI parsing
    url = "https://#{url}" unless url.start_with?("http://", "https://")
    uri = URI.parse(url)
    host = uri.host
    host&.gsub(/^www\./, "")
  rescue URI::InvalidURIError
    nil
  end

  private

  def normalize_domain_from_website
    self.domain ||= self.class.normalize_domain(website) if website.present? && domain.blank?
  end
end
