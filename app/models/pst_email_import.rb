class PstEmailImport < ApplicationRecord
  include Turbo::Broadcastable

  belongs_to :user

  STATUSES = %w[pending extracting importing completed failed cancelled].freeze
  MAX_FILE_SIZE = 5.gigabytes

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending extracting importing]) }
  scope :recent, -> { order(created_at: :desc).limit(5) }

  def active?
    %w[pending extracting importing].include?(status)
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

  def status_label
    I18n.t("pst_import.statuses.#{status}")
  end

  # Broadcast progress update via Turbo Streams
  def broadcast_progress
    recent = active? ? [] : user.pst_email_imports.recent.where.not(status: "pending")

    broadcast_replace_to(
      user,
      :pst_import,
      target: "pst-import-status",
      partial: "settings/pst_import_status",
      locals: { active_import: self, recent_imports: recent }
    )
  end

  # Cleanup temp PST file
  def cleanup_pst_file
    return unless pst_file_path.present? && File.exist?(pst_file_path)
    FileUtils.rm_f(pst_file_path)
    update_column(:pst_file_path, nil)
  end

  # Cleanup extraction directory
  def cleanup_extraction_dir
    return unless extraction_dir.present? && Dir.exist?(extraction_dir)
    FileUtils.rm_rf(extraction_dir)
    update_column(:extraction_dir, nil)
  end

  # Cleanup all temp files
  def cleanup_temp_files
    cleanup_pst_file
    cleanup_extraction_dir
  end
end
