class WebhooksController < ApplicationController
  # Skip authentication - webhooks come from Microsoft
  skip_before_action :require_authentication
  skip_before_action :verify_authenticity_token

  # POST /webhooks/microsoft
  def microsoft
    # Handle validation request (Microsoft sends this when creating subscription)
    if params[:validationToken].present?
      render plain: params[:validationToken], content_type: "text/plain"
      return
    end

    # Process notifications
    notifications = params[:value] || []

    notifications.each do |notification|
      process_notification(notification)
    end

    head :accepted
  end

  private

  def process_notification(notification)
    subscription_id = notification["subscriptionId"]
    resource_data = notification["resourceData"]
    client_state = notification["clientState"]

    # Find subscription
    subscription = MicrosoftSubscription.find_by(subscription_id: subscription_id)

    unless subscription
      Rails.logger.warn "Webhook: Unknown subscription #{subscription_id}"
      return
    end

    # Validate client_state
    unless valid_client_state?(subscription, client_state)
      Rails.logger.warn "Webhook: Invalid client_state for subscription #{subscription_id}"
      return
    end

    # Extract message ID and enqueue job
    message_id = resource_data&.dig("id")
    return unless message_id

    Rails.logger.info "Webhook: Enqueuing fetch for message #{message_id}"

    FetchMicrosoftEmailJob.perform_later(
      user_id: subscription.user_id,
      graph_id: message_id
    )
  end

  def valid_client_state?(subscription, client_state)
    ActiveSupport::SecurityUtils.secure_compare(
      subscription.client_state.to_s,
      client_state.to_s
    )
  end
end
