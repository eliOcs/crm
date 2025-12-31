class MicrosoftHistoricalImportService
  BATCH_SIZE = 50
  FOLDERS = %w[inbox sentitems].freeze

  attr_reader :user, :import

  def initialize(user, import:, logger: Rails.logger)
    @user = user
    @import = import
    @credential = user.microsoft_credential
    @logger = logger
    @email_import_service = MicrosoftEmailImportService.new(user, logger: logger)
    @enrichment_service = EmailEnrichmentService.new(user, logger: logger)
  end

  # Count total emails across all folders matching the date filter
  def count_emails
    return 0 unless @credential

    client = build_client
    filter = date_filter

    total = FOLDERS.sum do |folder|
      count = client.count_folder_messages(folder, filter: filter)
      @logger.info "[HistoricalImport] #{folder}: #{count} emails"
      count
    end

    @logger.info "[HistoricalImport] Total emails to import: #{total}"
    total
  end

  # Import a batch of emails from the specified folder
  # Returns { imported:, skipped:, failed:, next_link:, folder_complete: }
  def import_batch(folder:, next_link: nil)
    return empty_result(folder_complete: true) unless @credential

    client = build_client
    response = fetch_messages(client, folder, next_link)

    messages = response["value"] || []
    result = { imported: 0, skipped: 0, failed: 0 }

    messages.each do |message|
      outcome = import_single_message(message)
      result[outcome] += 1

      # Update progress after each email for real-time feedback
      update_progress(outcome)
    end

    {
      **result,
      next_link: response["@odata.nextLink"],
      folder_complete: response["@odata.nextLink"].nil?
    }
  end

  private

  def import_single_message(message)
    graph_id = message["id"]

    # Check for duplicate
    if @user.emails.exists?(graph_id: graph_id)
      @logger.debug "[HistoricalImport] Skipped (duplicate): #{graph_id}"
      return :skipped
    end

    email = @email_import_service.import_by_graph_id(graph_id)
    if email
      # Process enrichment synchronously to ensure correct order
      # (contacts, companies, tasks depend on processing emails chronologically)
      @enrichment_service.process_email_record(email)
      :imported
    else
      :skipped
    end
  rescue => e
    @logger.error "[HistoricalImport] Error importing #{message['id']}: #{e.message}"
    :failed
  end

  def fetch_messages(client, folder, next_link)
    if next_link
      client.get_next_page(next_link)
    else
      client.folder_messages(folder,
        filter: date_filter,
        top: BATCH_SIZE,
        orderby: "receivedDateTime asc",
        select: %w[id]
      )
    end
  end

  def date_filter
    cutoff = import.cutoff_date.iso8601
    "receivedDateTime ge #{cutoff}"
  end

  def update_progress(outcome)
    case outcome
    when :imported
      @import.increment!(:imported_emails)
    when :skipped
      @import.increment!(:skipped_emails)
    when :failed
      @import.increment!(:failed_emails)
    end
    @import.broadcast_progress
  end

  def empty_result(folder_complete:)
    { imported: 0, skipped: 0, failed: 0, next_link: nil, folder_complete: folder_complete }
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
  end
end
