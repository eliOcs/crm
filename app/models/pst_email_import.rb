class PstEmailImport < ApplicationRecord
  include Turbo::Broadcastable

  belongs_to :user

  STATUSES = %w[pending extracting importing enriching completed failed cancelled].freeze
  MAX_FILE_SIZE = 5.gigabytes

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending extracting importing enriching]) }
  scope :recent, -> { order(created_at: :desc).limit(5) }

  def active?
    %w[pending extracting importing enriching].include?(status)
  end

  def enriching?
    status == "enriching"
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

  # Returns estimated time remaining in seconds, or nil if not enough data
  def estimated_time_remaining
    return nil unless status == "importing" && started_at.present?
    return nil if processed_emails < 5 # Need some data for estimate

    elapsed = Time.current - started_at
    rate = processed_emails.to_f / elapsed # emails per second
    remaining = total_emails - processed_emails

    return nil if rate.zero?
    (remaining / rate).to_i
  end

  # Human-readable time remaining
  def time_remaining_text
    seconds = estimated_time_remaining
    return nil unless seconds

    if seconds < 60
      I18n.t("pst_import.time_remaining.seconds", count: seconds)
    elsif seconds < 3600
      minutes = (seconds / 60.0).round
      I18n.t("pst_import.time_remaining.minutes", count: minutes)
    else
      hours = (seconds / 3600.0).round
      I18n.t("pst_import.time_remaining.hours", count: hours)
    end
  end

  def status_label
    I18n.t("pst_import.statuses.#{status}")
  end

  BROADCAST_THROTTLE_SECONDS = 2

  # Broadcast progress update via Turbo Streams
  # Use force: true for important updates (status changes, completion)
  def broadcast_progress(force: false)
    now = Time.current

    # Throttle broadcasts unless forced
    unless force
      @last_broadcast_at ||= Time.at(0)
      return if (now - @last_broadcast_at) < BROADCAST_THROTTLE_SECONDS
    end

    @last_broadcast_at = now
    recent = active? ? [] : user.pst_email_imports.recent.where.not(status: "pending")

    broadcast_replace_to(
      user,
      :pst_import,
      target: "pst-import-status",
      partial: "settings/pst_import_status",
      locals: { active_import: self, recent_imports: recent }
    )
  end

  # Cleanup inbox PST file
  def cleanup_pst_file
    return unless pst_file_path.present? && File.exist?(pst_file_path)
    FileUtils.rm_f(pst_file_path)
    update_column(:pst_file_path, nil)
  end

  # Cleanup sent PST file
  def cleanup_sent_pst_file
    return unless sent_pst_file_path.present? && File.exist?(sent_pst_file_path)
    FileUtils.rm_f(sent_pst_file_path)
    update_column(:sent_pst_file_path, nil)
  end

  # Cleanup both PST files
  def cleanup_pst_files
    cleanup_pst_file
    cleanup_sent_pst_file
  end

  # Cleanup extraction directory
  def cleanup_extraction_dir
    return unless extraction_dir.present? && Dir.exist?(extraction_dir)
    FileUtils.rm_rf(extraction_dir)
    update_column(:extraction_dir, nil)
  end

  # Cleanup all temp files
  def cleanup_temp_files
    cleanup_pst_files
    cleanup_extraction_dir
  end

  # Display filename(s) for UI
  def display_filenames
    names = [ original_filename ]
    names << sent_original_filename if sent_original_filename.present?
    names.join(", ")
  end
end
