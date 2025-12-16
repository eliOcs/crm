class Task < ApplicationRecord
  STATUSES = %w[incoming not_now todo in_progress blocked done].freeze

  belongs_to :user
  belongs_to :contact, optional: true
  belongs_to :company, optional: true

  has_many :audit_logs, as: :auditable, dependent: :destroy

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where.not(status: "done") }
  scope :by_status, ->(status) { where(status: status) }
  scope :with_due_date, -> { where.not(due_date: nil) }
  scope :overdue, -> { where("due_date < ?", Date.current).where.not(status: "done") }

  def summary_for_llm
    parts = [ "[#{id}] #{name}" ]
    parts << "(#{status})" if status != "incoming"
    parts << "due:#{due_date}" if due_date
    parts.join(" ")
  end

  def status_label
    {
      "incoming" => "Incoming",
      "not_now" => "Not Now",
      "todo" => "To Do",
      "in_progress" => "In Progress",
      "blocked" => "Blocked",
      "done" => "Done"
    }[status]
  end
end
