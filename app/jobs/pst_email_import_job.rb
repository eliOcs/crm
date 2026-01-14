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
      process_import_batch
    when "enriching"
      process_enrichment_batch
    end
  rescue => e
    handle_error(e)
  end

  private

  def start_extraction
    @import.update!(status: "extracting", started_at: Time.current)
    @import.broadcast_progress(force: true)

    Rails.logger.info "[PstImport] Starting extraction for import #{@import.id}"

    # Re-enqueue to perform the actual extraction
    self.class.perform_later(import_id: @import.id)
  end

  def finish_extraction
    # Create extraction directory
    extraction_base = File.join(Rails.root, "tmp", "pst_extractions", SecureRandom.uuid)
    FileUtils.mkdir_p(extraction_base)

    # Extract inbox PST
    inbox_dir = File.join(extraction_base, "inbox")
    inbox_service = PstExtractionService.new(@import.pst_file_path, output_dir: inbox_dir)
    inbox_stats = inbox_service.extract

    # Extract sent PST if provided
    sent_stats = { eml_count: 0 }
    if @import.sent_pst_file_path.present?
      sent_dir = File.join(extraction_base, "sent")
      sent_service = PstExtractionService.new(@import.sent_pst_file_path, output_dir: sent_dir)
      sent_stats = sent_service.extract
    end

    @import.update!(
      status: "importing",
      extraction_dir: extraction_base,
      total_emails: inbox_stats[:eml_count] + sent_stats[:eml_count],
      current_index: 0
    )
    @import.broadcast_progress(force: true)

    Rails.logger.info "[PstImport] Extracted #{inbox_stats[:eml_count]} inbox + #{sent_stats[:eml_count]} sent emails"

    # Delete PST files after extraction (no longer needed)
    @import.cleanup_pst_files

    # Continue to importing phase
    self.class.perform_later(import_id: @import.id)
  end

  def process_import_batch
    @import.reload
    return if @import.cancelled?

    eml_files = merged_eml_files
    start_index = @import.current_index
    end_index = [ start_index + BATCH_SIZE, eml_files.count ].min

    import_service = EmailImportService.new(@user, logger: Rails.logger)

    (start_index...end_index).each do |idx|
      # Check for cancellation before each email
      break if @import.reload.cancelled?

      eml_path = eml_files[idx]
      Rails.logger.debug "[PstImport] Importing #{idx + 1}/#{eml_files.count}: #{File.basename(eml_path)}"

      # Phase 1: Import only, NO enrichment
      email = import_service.import_from_eml(eml_path)
      update_import_progress(email ? :created : :skipped)
    end

    @import.update!(current_index: end_index)

    if @import.cancelled?
      @import.cleanup_temp_files
    elsif end_index >= eml_files.count
      # Phase 1 complete - move to Phase 2 (enrichment)
      start_enrichment
    else
      # More emails to import
      self.class.perform_later(import_id: @import.id)
    end
  end

  def start_enrichment
    email_count = @user.emails.count

    # Skip enrichment phase if no emails to process
    if email_count == 0
      Rails.logger.info "[PstImport] No emails to enrich, completing import"
      complete_import
      return
    end

    @import.update!(
      status: "enriching",
      current_index: 0,
      total_emails: email_count,
      # Reset counters for enrichment phase
      imported_emails: 0,
      skipped_emails: 0,
      failed_emails: 0
    )
    @import.broadcast_progress(force: true)

    Rails.logger.info "[PstImport] Starting enrichment phase for #{email_count} emails"

    self.class.perform_later(import_id: @import.id)
  end

  def process_enrichment_batch
    @import.reload
    return if @import.cancelled?

    # Get emails ordered by sent_at for chronological processing
    emails = @user.emails.order(:sent_at).offset(@import.current_index).limit(BATCH_SIZE)

    return complete_import if emails.empty?

    enrichment_service = EmailEnrichmentService.new(@user, logger: Rails.logger)

    emails.each_with_index do |email, idx|
      break if @import.reload.cancelled?

      global_idx = @import.current_index + idx + 1
      Rails.logger.debug "[PstImport] Enriching #{global_idx}/#{@import.total_emails}: #{email.subject&.truncate(40)}"

      enrichment_service.process_email_record(email)
      @import.increment!(:imported_emails)
      @import.broadcast_progress
    end

    new_index = @import.current_index + emails.count
    @import.update!(current_index: new_index)

    if @import.cancelled?
      @import.cleanup_temp_files
    elsif new_index >= @import.total_emails
      complete_import
    else
      self.class.perform_later(import_id: @import.id)
    end
  end

  def update_import_progress(status)
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
    @import.broadcast_progress(force: true)

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
    @import.broadcast_progress(force: true)
  end

  def import_stats
    {
      total: @import.total_emails,
      imported: @import.imported_emails,
      skipped: @import.skipped_emails,
      failed: @import.failed_emails
    }
  end

  # Returns all EML files from both inbox and sent directories, sorted by date
  def merged_eml_files
    return @merged_eml_files if @merged_eml_files

    inbox_dir = File.join(@import.extraction_dir, "inbox")
    sent_dir = File.join(@import.extraction_dir, "sent")

    inbox_files = Dir.exist?(inbox_dir) ? Dir.glob(File.join(inbox_dir, "**/*.eml")) : []
    sent_files = Dir.exist?(sent_dir) ? Dir.glob(File.join(sent_dir, "**/*.eml")) : []

    all_files = inbox_files + sent_files
    @merged_eml_files = sort_by_date(all_files)
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
