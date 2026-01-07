# Unified service for processing emails from any source.
#
# This service provides a single point for email storage and enrichment,
# regardless of how the email arrives (forwarding, Microsoft Graph, EML file).
#
# Usage:
#   service = EmailProcessingService.new(user)
#
#   # From EML file (rake task)
#   result = service.process_eml(eml_path, enrich: :sync)
#
#   # From Mail object (InboundMailbox)
#   result = service.process_mail(mail, source_type: "forwarded")
#
#   # From already-created Email record (Microsoft imports)
#   result = service.process_record(email, enrich: :async)
#
class EmailProcessingService
  # Result object returned by all processing methods
  class Result
    attr_reader :email, :status, :error

    def initialize(email:, status:, error: nil)
      @email = email
      @status = status  # :created, :skipped, :error
      @error = error
    end

    def success? = status != :error
    def created? = status == :created
    def skipped? = status == :skipped
  end

  attr_reader :user, :logger

  def initialize(user, logger: Rails.logger)
    @user = user
    @logger = logger
  end

  # Process an email from an EML file path.
  # Delegates to EmailImportService for parsing and storage.
  #
  # @param eml_path [String] Path to the EML file
  # @param enrich [:async, :sync, :skip] Enrichment mode (default: :async)
  # @return [Result]
  def process_eml(eml_path, enrich: :async)
    import_service = EmailImportService.new(user, logger: logger)
    email = import_service.import_from_eml(eml_path)

    if email
      trigger_enrichment(email, mode: enrich)
      Result.new(email: email, status: :created)
    else
      Result.new(email: nil, status: :skipped)
    end
  rescue => e
    logger.error "[EmailProcessingService] Error processing EML: #{e.message}"
    Result.new(email: nil, status: :error, error: e)
  end

  # Process an email from a Mail object (e.g., from ActionMailbox).
  # Creates the Email record, imports attachments, and triggers enrichment.
  #
  # @param mail [Mail::Message] The mail object to process
  # @param source_type [String] Source type ("forwarded", etc.)
  # @param enrich [:async, :sync, :skip] Enrichment mode (default: :async)
  # @return [Result]
  def process_mail(mail, source_type: "forwarded", enrich: :async)
    email = create_from_mail(mail, source_type)
    return Result.new(email: nil, status: :skipped) unless email

    import_attachments_from_mail(email, mail)
    email.find_or_link_sender_contact

    trigger_enrichment(email, mode: enrich)
    Result.new(email: email, status: :created)
  rescue => e
    logger.error "[EmailProcessingService] Error processing Mail: #{e.message}"
    logger.debug e.backtrace.first(5).join("\n")
    Result.new(email: nil, status: :error, error: e)
  end

  # Trigger enrichment for an already-created Email record.
  # Used when the email was created by another service (e.g., MicrosoftEmailImportService).
  #
  # @param email [Email] The email record to enrich
  # @param enrich [:async, :sync, :skip] Enrichment mode (default: :async)
  # @return [Result]
  def process_record(email, enrich: :async)
    trigger_enrichment(email, mode: enrich)
    Result.new(email: email, status: :created)
  end

  private

  def trigger_enrichment(email, mode:)
    case mode
    when :async
      EnrichEmailJob.perform_later(email_id: email.id)
      logger.info "[EmailProcessingService] Queued enrichment for email id=#{email.id}"
    when :sync
      service = EmailEnrichmentService.new(user, logger: logger)
      service.process_email_record(email)
      logger.info "[EmailProcessingService] Sync enrichment for email id=#{email.id}"
    when :skip
      logger.debug "[EmailProcessingService] Skipped enrichment for email id=#{email.id}"
    end
  end

  def create_from_mail(mail, source_type)
    message_id = extract_message_id(mail)

    # Skip duplicates
    if message_id.present? && user.emails.exists?(message_id: message_id)
      logger.debug "[EmailProcessingService] Skipped duplicate: #{message_id}"
      return nil
    end

    user.emails.create!(
      subject: mail.subject,
      sent_at: mail.date || Time.current,
      body_plain: extract_plain_body(mail),
      body_html: extract_html_body(mail),
      from_address: extract_address(mail.from&.first),
      to_addresses: Array(mail.to).map { |a| extract_address(a) },
      cc_addresses: Array(mail.cc).map { |a| extract_address(a) },
      message_id: message_id,
      in_reply_to: extract_in_reply_to(mail),
      references: extract_references(mail),
      source_type: source_type
    )
  end

  def extract_message_id(mail)
    mail.message_id&.gsub(/[<>]/, "")
  end

  def extract_in_reply_to(mail)
    reply_to = mail.in_reply_to
    return nil unless reply_to
    Array(reply_to).first&.gsub(/[<>]/, "")
  end

  def extract_references(mail)
    refs = mail.references
    return [] unless refs
    Array(refs).map { |r| r.gsub(/[<>]/, "") }
  end

  def extract_plain_body(mail)
    if mail.multipart?
      mail.text_part&.decoded
    else
      mail.content_type&.include?("text/plain") ? mail.decoded : nil
    end
  rescue => e
    logger.warn "[EmailProcessingService] Error decoding plain body: #{e.message}"
    nil
  end

  def extract_html_body(mail)
    if mail.multipart?
      mail.html_part&.decoded
    else
      mail.content_type&.include?("text/html") ? mail.decoded : nil
    end
  rescue => e
    logger.warn "[EmailProcessingService] Error decoding HTML body: #{e.message}"
    nil
  end

  def extract_address(addr)
    return { "email" => "unknown@unknown", "name" => nil } unless addr

    parsed = Mail::Address.new(addr)
    { "email" => parsed.address&.downcase, "name" => parsed.display_name }
  rescue
    { "email" => addr.to_s.downcase, "name" => nil }
  end

  def import_attachments_from_mail(email, mail)
    mail.attachments.each do |attachment|
      content_id = attachment.content_id&.gsub(/[<>]/, "")
      is_inline = attachment.content_disposition&.include?("inline") ||
                  attachment.content_id.present?

      email_attachment = email.email_attachments.new(
        content_id: content_id,
        inline: is_inline
      )

      email_attachment.attach_with_dedup(
        io: StringIO.new(attachment.decoded),
        filename: attachment.filename || "attachment",
        content_type: attachment.content_type&.split(";")&.first || "application/octet-stream"
      )
    rescue => e
      logger.warn "[EmailProcessingService] Failed to attach #{attachment.filename}: #{e.message}"
    end
  end
end
