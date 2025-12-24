class SettingsController < ApplicationController
  def edit
    fresh_when Current.user
  end

  def update
    if Current.user.update(settings_params)
      redirect_to edit_settings_path, notice: t("settings.saved")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.expect(user: [ :locale ])
  end
end
