class SetupMicrosoftSubscriptionsJob < ApplicationJob
  queue_as :default

  retry_on MicrosoftGraphClient::GraphApiError, wait: 1.minute, attempts: 3
  retry_on MicrosoftSubscriptionService::SubscriptionError, wait: 1.minute, attempts: 3

  discard_on ActiveRecord::RecordNotFound

  def perform(user_id:)
    user = User.find(user_id)
    return unless user.microsoft_connected?

    service = MicrosoftSubscriptionService.new(user)
    results = service.create_subscriptions

    Rails.logger.info "Created Microsoft subscriptions for user #{user_id}: inbox=#{results[:inbox]&.id}, sentitems=#{results[:sentitems]&.id}"
  end
end
