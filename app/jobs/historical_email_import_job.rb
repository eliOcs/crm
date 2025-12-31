class HistoricalEmailImportJob < ApplicationJob
  queue_as :default

  FOLDERS = MicrosoftHistoricalImportService::FOLDERS

  # Retry with exponential backoff for transient failures
  retry_on MicrosoftGraphClient::GraphApiError, wait: :polynomially_longer, attempts: 5
  retry_on MicrosoftGraphClient::TokenExpiredError, wait: 30.seconds, attempts: 3

  # Discard if import or user no longer exists
  discard_on ActiveRecord::RecordNotFound

  def perform(import_id:)
    @import = MicrosoftEmailImport.find(import_id)
    @user = @import.user

    # Check if cancelled
    return if @import.cancelled?

    case @import.status
    when "pending"
      start_counting
    when "counting"
      finish_counting
    when "importing"
      process_batch
    end
  rescue => e
    handle_error(e)
  end

  private

  def start_counting
    @import.update!(status: "counting", started_at: Time.current)
    Rails.logger.info "[HistoricalImport] Starting count for import #{@import.id}"

    # Re-enqueue to perform the actual count
    self.class.perform_later(import_id: @import.id)
  end

  def finish_counting
    service = MicrosoftHistoricalImportService.new(@user, import: @import)
    total = service.count_emails

    @import.update!(
      status: "importing",
      total_emails: total,
      current_folder: FOLDERS.first,
      next_link: nil
    )

    Rails.logger.info "[HistoricalImport] Counted #{total} emails, starting import"

    # Continue to importing phase
    self.class.perform_later(import_id: @import.id)
  end

  def process_batch
    # Reload to check for cancellation
    @import.reload
    return if @import.cancelled?

    service = MicrosoftHistoricalImportService.new(@user, import: @import)
    current_folder = @import.current_folder

    result = service.import_batch(
      folder: current_folder,
      next_link: @import.next_link
    )

    # Update progress
    @import.update!(
      imported_emails: @import.imported_emails + result[:imported],
      skipped_emails: @import.skipped_emails + result[:skipped],
      failed_emails: @import.failed_emails + result[:failed],
      next_link: result[:next_link]
    )

    Rails.logger.info "[HistoricalImport] Batch complete: #{result}"

    if result[:folder_complete]
      move_to_next_folder
    else
      # More pages in this folder, continue
      self.class.perform_later(import_id: @import.id)
    end
  end

  def move_to_next_folder
    current_index = FOLDERS.index(@import.current_folder)
    next_folder = FOLDERS[current_index + 1]

    if next_folder
      @import.update!(current_folder: next_folder, next_link: nil)
      Rails.logger.info "[HistoricalImport] Moving to folder: #{next_folder}"
      self.class.perform_later(import_id: @import.id)
    else
      # All folders complete - mark as completed
      # Enrichment jobs run asynchronously in the background
      complete_import
    end
  end

  def complete_import
    @import.update!(
      status: "completed",
      completed_at: Time.current,
      enriched_emails: @import.imported_emails  # All imported emails were queued for enrichment
    )

    Rails.logger.info "[HistoricalImport] Import #{@import.id} completed. Stats: #{import_stats}"
  end

  def handle_error(error)
    Rails.logger.error "[HistoricalImport] Error: #{error.message}"
    @import.update!(
      status: "failed",
      error_message: error.message.truncate(500),
      completed_at: Time.current
    )
  end

  def import_stats
    {
      total: @import.total_emails,
      imported: @import.imported_emails,
      skipped: @import.skipped_emails,
      failed: @import.failed_emails
    }
  end
end
