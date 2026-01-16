class SettingsController < ApplicationController
  def edit
    @active_import = Current.user.microsoft_email_imports.active.first
    @recent_imports = Current.user.microsoft_email_imports.recent.where.not(status: "pending")
    @active_pst_import = Current.user.pst_email_imports.active.first
    @recent_pst_imports = Current.user.pst_email_imports.recent.where.not(status: "pending")
    fresh_when @active_import || @active_pst_import || Current.user
  end

  def update
    if Current.user.update(settings_params)
      redirect_to edit_settings_path, notice: t("settings.saved")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def start_microsoft_import
    # Check for existing active import
    if Current.user.microsoft_email_imports.active.exists?
      redirect_to edit_settings_path, alert: t("microsoft_import.already_running")
      return
    end

    # Validate Microsoft connection
    unless Current.user.microsoft_connected?
      redirect_to edit_settings_path, alert: t("microsoft_import.not_connected")
      return
    end

    time_range = params[:time_range]
    unless MicrosoftEmailImport::TIME_RANGES.key?(time_range)
      redirect_to edit_settings_path, alert: t("microsoft_import.invalid_time_range")
      return
    end

    import = Current.user.microsoft_email_imports.create!(time_range: time_range)
    HistoricalEmailImportJob.perform_later(import_id: import.id)

    redirect_to edit_settings_path, notice: t("microsoft_import.started")
  end

  def cancel_microsoft_import
    import = Current.user.microsoft_email_imports.find(params[:id])

    if import.can_cancel?
      import.update!(status: "cancelled", completed_at: Time.current)
      redirect_to edit_settings_path, notice: t("microsoft_import.cancelled")
    else
      redirect_to edit_settings_path, alert: t("microsoft_import.cannot_cancel")
    end
  end

  def microsoft_import_status
    @active_import = Current.user.microsoft_email_imports.active.first
    @recent_imports = Current.user.microsoft_email_imports.recent.where.not(status: "pending")
    render partial: "microsoft_import_status"
  end

  def start_pst_import
    # Check for existing active import
    if Current.user.pst_email_imports.active.exists?
      redirect_to edit_settings_path, alert: t("pst_import.already_running")
      return
    end

    # Inbox PST is required
    inbox_file = params[:inbox_pst_file]
    sent_file = params[:sent_pst_file]

    unless inbox_file.present?
      redirect_to edit_settings_path, alert: t("pst_import.no_inbox_file")
      return
    end

    # Validate file sizes
    if inbox_file.size > PstEmailImport::MAX_FILE_SIZE
      redirect_to edit_settings_path, alert: t("pst_import.file_too_large")
      return
    end

    if sent_file.present? && sent_file.size > PstEmailImport::MAX_FILE_SIZE
      redirect_to edit_settings_path, alert: t("pst_import.file_too_large")
      return
    end

    # Save files to temp directory
    pst_dir = Rails.root.join("tmp", "pst_uploads")
    FileUtils.mkdir_p(pst_dir)

    inbox_path = pst_dir.join("#{SecureRandom.uuid}_inbox.pst")
    FileUtils.cp(inbox_file.tempfile.path, inbox_path)

    sent_path = nil
    if sent_file.present?
      sent_path = pst_dir.join("#{SecureRandom.uuid}_sent.pst")
      FileUtils.cp(sent_file.tempfile.path, sent_path)
    end

    # Create import record
    import = Current.user.pst_email_imports.create!(
      original_filename: inbox_file.original_filename,
      file_size: inbox_file.size,
      pst_file_path: inbox_path.to_s,
      sent_original_filename: sent_file&.original_filename,
      sent_file_size: sent_file&.size,
      sent_pst_file_path: sent_path&.to_s
    )

    PstEmailImportJob.perform_later(import_id: import.id)

    redirect_to edit_settings_path, notice: t("pst_import.started")
  end

  def cancel_pst_import
    import = Current.user.pst_email_imports.find(params[:id])

    if import.can_cancel?
      import.cleanup_temp_files
      import.update!(status: "cancelled", completed_at: Time.current)
      redirect_to edit_settings_path, notice: t("pst_import.cancelled")
    else
      redirect_to edit_settings_path, alert: t("pst_import.cannot_cancel")
    end
  end

  def retry_pst_import
    import = Current.user.pst_email_imports.find(params[:id])

    unless import.failed?
      redirect_to edit_settings_path, alert: t("pst_import.cannot_retry")
      return
    end

    # Resume enrichment from where it left off
    # imported_emails represents successfully processed count before failure
    import.update!(
      status: "enriching",
      error_message: nil,
      completed_at: nil,
      current_index: import.imported_emails,
      total_emails: Current.user.emails.count
      # Keep imported_emails, skipped_emails, failed_emails counts to resume progress
    )

    PstEmailImportJob.perform_later(import_id: import.id)
    redirect_to edit_settings_path, notice: t("pst_import.retrying")
  end

  def pst_import_status
    @active_pst_import = Current.user.pst_email_imports.active.first
    @recent_pst_imports = Current.user.pst_email_imports.recent.where.not(status: "pending")
    render partial: "pst_import_status"
  end

  private

  def settings_params
    params.expect(user: [ :locale, :inbound_email_enabled ])
  end
end
