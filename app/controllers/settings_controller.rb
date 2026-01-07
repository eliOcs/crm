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

    # Validate file presence
    unless params[:pst_file].present?
      redirect_to edit_settings_path, alert: t("pst_import.no_file")
      return
    end

    uploaded_file = params[:pst_file]

    # Validate file size
    if uploaded_file.size > PstEmailImport::MAX_FILE_SIZE
      redirect_to edit_settings_path, alert: t("pst_import.file_too_large")
      return
    end

    # Save file to temp directory (stream copy, not loading into memory)
    pst_dir = Rails.root.join("tmp", "pst_uploads")
    FileUtils.mkdir_p(pst_dir)
    pst_path = pst_dir.join("#{SecureRandom.uuid}.pst")
    FileUtils.cp(uploaded_file.tempfile.path, pst_path)

    # Create import record
    import = Current.user.pst_email_imports.create!(
      original_filename: uploaded_file.original_filename,
      file_size: uploaded_file.size,
      pst_file_path: pst_path.to_s
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
