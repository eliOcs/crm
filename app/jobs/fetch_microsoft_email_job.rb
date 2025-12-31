class FetchMicrosoftEmailJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient failures
  retry_on MicrosoftGraphClient::GraphApiError, wait: :polynomially_longer, attempts: 5
  retry_on MicrosoftGraphClient::TokenExpiredError, wait: 30.seconds, attempts: 3

  # Discard if user no longer exists
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id:, graph_id:)
    user = User.find(user_id)
    return unless user.microsoft_connected?

    service = MicrosoftEmailImportService.new(user)
    email = service.import_by_graph_id(graph_id)

    # Queue enrichment job to extract contacts, companies, and tasks via LLM
    EnrichEmailJob.perform_later(email_id: email.id) if email
  end
end
