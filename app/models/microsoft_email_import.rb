class MicrosoftEmailImport < ApplicationRecord
  belongs_to :user

  TIME_RANGES = {
    "3_months" => 3.months,
    "1_year" => 1.year,
    "3_years" => 3.years
  }.freeze

  STATUSES = %w[pending counting importing enriching completed failed cancelled].freeze

  validates :time_range, presence: true, inclusion: { in: TIME_RANGES.keys }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending counting importing enriching]) }
  scope :recent, -> { order(created_at: :desc).limit(5) }

  def active?
    %w[pending counting importing enriching].include?(status)
  end

  def can_cancel?
    active?
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def cancelled?
    status == "cancelled"
  end

  def processed_emails
    imported_emails + skipped_emails + failed_emails
  end

  def progress_percentage
    return 0 if total_emails.zero?
    ((processed_emails.to_f / total_emails) * 100).round
  end

  def cutoff_date
    duration = TIME_RANGES[time_range]
    duration.ago.beginning_of_day
  end

  def time_range_label
    I18n.t("microsoft_import.time_ranges.#{time_range}")
  end

  def status_label
    I18n.t("microsoft_import.statuses.#{status}")
  end
end
