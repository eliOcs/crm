class EnrichEmailJob < ApplicationJob
  queue_as :default

  # Retry for Anthropic API failures
  retry_on Anthropic::Errors::APIError, wait: :polynomially_longer, attempts: 3

  # Discard if email no longer exists
  discard_on ActiveRecord::RecordNotFound

  def perform(email_id:)
    email = Email.find(email_id)
    user = email.user

    service = EmailEnrichmentService.new(user)
    service.process_email_record(email)

    Rails.logger.info "[EnrichEmailJob] Processed email id=#{email.id} subject=#{email.subject.truncate(50)}"
    Rails.logger.info "[EnrichEmailJob] Stats: #{service.stats}"
  end
end
