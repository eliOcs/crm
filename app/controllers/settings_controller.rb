class SettingsController < ApplicationController
  def edit
    @active_import = Current.user.microsoft_email_imports.active.first
    @recent_imports = Current.user.microsoft_email_imports.recent.where.not(status: "pending")
    fresh_when @active_import || Current.user
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

    # Disable caching for polling endpoint
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    render partial: "microsoft_import_status", layout: "turbo_frame"
  end

  private

  def settings_params
    params.expect(user: [ :locale ])
  end
end
