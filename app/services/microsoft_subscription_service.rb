class MicrosoftSubscriptionService
  WEBHOOK_PATH = "/webhooks/microsoft"
  MAX_EXPIRATION_MINUTES = 4230 # ~3 days (Microsoft limit for mail)

  class SubscriptionError < StandardError; end

  def initialize(user, logger: Rails.logger)
    @user = user
    @credential = user.microsoft_credential
    @logger = logger
  end

  def create_subscriptions
    raise SubscriptionError, "No Microsoft credential" unless @credential

    results = {}

    %w[inbox sentitems].each do |folder|
      results[folder.to_sym] = create_subscription_for_folder(folder)
    end

    results
  end

  def renew_subscription(subscription)
    client = build_client
    new_expiration = MAX_EXPIRATION_MINUTES.minutes.from_now

    response = client.renew_subscription(
      subscription.subscription_id,
      new_expiration
    )

    subscription.update!(expires_at: Time.parse(response["expirationDateTime"]))
    @logger.info "Renewed subscription #{subscription.id} until #{subscription.expires_at}"
    subscription
  end

  def delete_subscription(subscription)
    client = build_client
    client.delete_subscription(subscription.subscription_id)
    subscription.destroy
    @logger.info "Deleted subscription #{subscription.id}"
  rescue MicrosoftGraphClient::GraphApiError => e
    # If already deleted at Microsoft, just remove locally
    @logger.warn "Could not delete subscription at Microsoft: #{e.message}"
    subscription.destroy
  end

  def renew_expiring_subscriptions
    @user.microsoft_subscriptions.expiring_soon.find_each do |subscription|
      renew_subscription(subscription)
    rescue => e
      @logger.error "Failed to renew subscription #{subscription.id}: #{e.message}"
    end
  end

  private

  def create_subscription_for_folder(folder)
    # Delete existing subscription for this folder if any
    existing = @user.microsoft_subscriptions.find_by(folder: folder)
    delete_subscription(existing) if existing

    client = build_client
    resource = "me/mailFolders/#{folder}/messages"
    client_state = SecureRandom.urlsafe_base64(32)
    expiration = MAX_EXPIRATION_MINUTES.minutes.from_now

    response = client.create_subscription(
      change_type: "created",
      notification_url: webhook_url,
      resource: resource,
      expiration_date_time: expiration.iso8601,
      client_state: client_state
    )

    subscription = @user.microsoft_subscriptions.create!(
      subscription_id: response["id"],
      resource: resource,
      folder: folder,
      expires_at: Time.parse(response["expirationDateTime"]),
      client_state: client_state
    )

    @logger.info "Created subscription for #{folder}: #{subscription.subscription_id}"
    subscription
  end

  def webhook_url
    base_url = ENV.fetch("APP_URL") { raise SubscriptionError, "APP_URL not configured" }
    "#{base_url}#{WEBHOOK_PATH}"
  end

  def build_client
    ensure_fresh_token!
    MicrosoftGraphClient.new(@credential.access_token)
  end

  def ensure_fresh_token!
    return unless @credential.token_expiring_soon?

    oauth = MicrosoftOauthService.new(redirect_uri: "")
    token_data = oauth.refresh_token(@credential)
    @credential.update!(token_data)
    @logger.info "Refreshed access token for user #{@user.id}"
  end
end
