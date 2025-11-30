class AuditLog < ApplicationRecord
  belongs_to :user
  belongs_to :auditable, polymorphic: true

  validates :action, presence: true, inclusion: { in: %w[create update destroy link unlink] }
  validates :auditable_type, presence: true
  validates :auditable_id, presence: true

  def self.current_version
    @current_version ||= `git rev-parse --short HEAD`.strip
  end
end
