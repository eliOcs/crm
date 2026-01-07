# frozen_string_literal: true

class PstEmailImportJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 50

  # Discard if import or user no longer exists
  discard_on ActiveRecord::RecordNotFound

  def perform(import_id:)
    @import = PstEmailImport.find(import_id)
    @user = @import.user

    return if @import.cancelled?

    case @import.status
    when "pending"
      start_extraction
    when "extracting"
      finish_extraction
    when "importing"
      process_batch
    end
  rescue => e
    handle_error(e)
  end

  private

  def start_extraction
    @import.update!(status: "extracting", started_at: Time.current)
    @import.broadcast_progress

    Rails.logger.info "[PstImport] Starting extraction for import #{@import.id}"

    # Re-enqueue to perform the actual extraction
    self.class.perform_later(import_id: @import.id)
  end

  def finish_extraction
    service = PstExtractionService.new(@import.pst_file_path, logger: Rails.logger)
    stats = service.extract

    @import.update!(
      status: "importing",
      extraction_dir: service.output_dir,
      total_emails: stats[:eml_count],
      current_index: 0
    )
    @import.broadcast_progress

    Rails.logger.info "[PstImport] Extracted #{stats[:eml_count]} emails"

    # Delete PST file after extraction (no longer needed)
    @import.cleanup_pst_file

    # Continue to importing phase
    self.class.perform_later(import_id: @import.id)
  end

  def process_batch
    @import.reload
    return if @import.cancelled?

    eml_files = Dir.glob(File.join(@import.extraction_dir, "**/*.eml"))
    eml_files = sort_by_date(eml_files)

    start_index = @import.current_index
    end_index = [ start_index + BATCH_SIZE, eml_files.count ].min

    processing_service = EmailProcessingService.new(@user, logger: Rails.logger)

    (start_index...end_index).each do |idx|
      # Check for cancellation before each email
      break if @import.reload.cancelled?

      eml_path = eml_files[idx]
      Rails.logger.debug "[PstImport] Processing #{idx + 1}/#{eml_files.count}: #{File.basename(eml_path)}"

      result = processing_service.process_eml(eml_path, enrich: :sync)
      update_progress(result.status)
    end

    @import.update!(current_index: end_index)

    if @import.cancelled?
      # Cleanup on cancellation
      @import.cleanup_temp_files
    elsif end_index >= eml_files.count
      complete_import
    else
      # More emails to process
      self.class.perform_later(import_id: @import.id)
    end
  end

  def update_progress(status)
    case status
    when :created
      @import.increment!(:imported_emails)
    when :skipped
      @import.increment!(:skipped_emails)
    when :error
      @import.increment!(:failed_emails)
    end
    @import.broadcast_progress
  end

  def complete_import
    @import.cleanup_temp_files
    @import.update!(
      status: "completed",
      completed_at: Time.current
    )
    @import.broadcast_progress

    Rails.logger.info "[PstImport] Import #{@import.id} completed. Stats: #{import_stats}"
  end

  def handle_error(error)
    Rails.logger.error "[PstImport] Error: #{error.message}"
    Rails.logger.error error.backtrace.first(10).join("\n")

    @import.cleanup_temp_files
    @import.update!(
      status: "failed",
      error_message: error.message.truncate(500),
      completed_at: Time.current
    )
    @import.broadcast_progress
  end

  def import_stats
    {
      total: @import.total_emails,
      imported: @import.imported_emails,
      skipped: @import.skipped_emails,
      failed: @import.failed_emails
    }
  end

  def sort_by_date(files)
    files_with_dates = files.map do |file|
      date = extract_date(file)
      [ file, date ]
    end

    files_with_dates
      .sort_by { |_file, date| date || Time.at(0) }
      .map(&:first)
  end

  def extract_date(eml_path)
    content = File.read(eml_path, 8192, encoding: "binary") rescue nil
    return nil unless content

    if content =~ /^Date:\s*(.+)$/i
      begin
        Time.parse($1.strip)
      rescue ArgumentError
        nil
      end
    end
  end
end
