module Auth
  class MicrosoftController < ApplicationController
    def connect
      oauth = MicrosoftOauthService.new(redirect_uri: callback_url)
      state = SecureRandom.urlsafe_base64(32)
      session[:oauth_state] = state

      redirect_to oauth.authorization_url(state: state), allow_other_host: true
    end

    def callback
      if params[:error]
        Rails.logger.error("Microsoft OAuth error: #{params[:error_description]}")
        redirect_to edit_settings_path, alert: t("settings.microsoft.auth_failed")
        return
      end

      unless valid_state?
        redirect_to edit_settings_path, alert: t("settings.microsoft.invalid_state")
        return
      end

      oauth = MicrosoftOauthService.new(redirect_uri: callback_url)
      token_data = oauth.exchange_code(params[:code])

      client = MicrosoftGraphClient.new(token_data[:access_token])
      profile = client.me

      Current.user.create_microsoft_credential!(
        microsoft_user_id: profile["id"],
        email: profile["mail"] || profile["userPrincipalName"],
        **token_data
      )

      # Setup webhook subscriptions for inbox and sent folders
      SetupMicrosoftSubscriptionsJob.perform_later(user_id: Current.user.id)

      redirect_to edit_settings_path, notice: t("settings.microsoft.connected")
    rescue OAuth2::Error, MicrosoftGraphClient::GraphApiError => e
      Rails.logger.error("Microsoft OAuth error: #{e.message}")
      redirect_to edit_settings_path, alert: t("settings.microsoft.auth_failed")
    end

    def disconnect
      # Delete webhook subscriptions at Microsoft before destroying credential
      if Current.user.microsoft_connected?
        service = MicrosoftSubscriptionService.new(Current.user)
        Current.user.microsoft_subscriptions.find_each do |subscription|
          service.delete_subscription(subscription)
        rescue => e
          Rails.logger.warn "Could not delete subscription #{subscription.id}: #{e.message}"
        end
      end

      Current.user.microsoft_credential&.destroy
      redirect_to edit_settings_path, notice: t("settings.microsoft.disconnected")
    end

    private

    def callback_url
      callback_auth_microsoft_url
    end

    def valid_state?
      params[:state].present? && params[:state] == session.delete(:oauth_state)
    end
  end
end
