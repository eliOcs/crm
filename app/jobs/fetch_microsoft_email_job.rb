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

    # Import email via Graph API
    import_service = MicrosoftEmailImportService.new(user)
    email = import_service.import_by_graph_id(graph_id)
    return unless email

    # Use unified service for enrichment
    processing_service = EmailProcessingService.new(user)
    processing_service.process_record(email, enrich: :async)
  end
end
