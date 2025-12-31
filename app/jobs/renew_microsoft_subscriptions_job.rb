class RenewMicrosoftSubscriptionsJob < ApplicationJob
  queue_as :low

  def perform
    # Find all subscriptions expiring within the buffer period
    MicrosoftSubscription.expiring_soon.includes(:user).find_each do |subscription|
      user = subscription.user
      next unless user.microsoft_connected?

      begin
        service = MicrosoftSubscriptionService.new(user)
        service.renew_subscription(subscription)
      rescue => e
        Rails.logger.error "Failed to renew subscription #{subscription.id}: #{e.message}"
      end
    end
  end
end
