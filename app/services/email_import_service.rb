class EmailImportService
  include Auditable

  attr_reader :user, :stats

  def initialize(user, logger: Rails.logger)
    @user = user
    @logger = logger
    @stats = {
      imported: 0,
      skipped: 0,
      errors: 0
    }
  end

  def import_from_eml(eml_path)
    reader = EmlReader.new(eml_path)
    email_data = reader.read
    return nil unless email_data

    mail = Mail.read(eml_path)
    message_id = extract_message_id(mail)

    # Skip if already imported (by message_id)
    if message_id.present? && @user.emails.exists?(message_id: message_id)
      @stats[:skipped] += 1
      @logger.debug "  Skipped (duplicate): #{message_id}"
      return nil
    end

    email = @user.emails.create!(
      subject: email_data[:subject],
      sent_at: email_data[:date] || Time.current,
      body_plain: email_data[:body],
      body_html: clean_html(email_data[:html_body]),
      from_address: email_data[:from] || { "email" => "unknown@unknown", "name" => nil },
      to_addresses: email_data[:to] || [],
      cc_addresses: email_data[:cc] || [],
      message_id: message_id,
      in_reply_to: extract_in_reply_to(mail),
      references: extract_references(mail),
      source_path: relative_path(eml_path)
    )

    # Import attachments
    import_attachments(email, reader, email_data[:attachments])

    # Link sender contact if exists
    email.find_or_link_sender_contact

    @stats[:imported] += 1
    @logger.debug "  Imported email id=#{email.id} message_id=#{message_id}"

    log_audit(
      record: email,
      action: "create",
      message: "import from EML",
      field_changes: { "source_path" => { "from" => nil, "to" => email.source_path } },
      source_email: email
    )

    email
  rescue => e
    @stats[:errors] += 1
    @logger.error "  Error importing #{eml_path}: #{e.message}"
    @logger.debug e.backtrace.first(5).join("\n")
    nil
  end

  private

  def extract_message_id(mail)
    mail.message_id&.gsub(/[<>]/, "")
  end

  def extract_in_reply_to(mail)
    reply_to = mail.in_reply_to
    return nil unless reply_to

    # in_reply_to can be a string or array
    Array(reply_to).first&.gsub(/[<>]/, "")
  end

  def extract_references(mail)
    refs = mail.references
    return [] unless refs

    Array(refs).map { |r| r.gsub(/[<>]/, "") }
  end

  def clean_html(html)
    return nil unless html.present?

    # Just store the raw HTML - sanitization happens at render time
    # This preserves the original content and allows flexible cleanup later
    html
  end

  def relative_path(eml_path)
    eml_path.to_s.sub("#{EmlReader::EMAILS_DIR}/", "")
  end

  def import_attachments(email, reader, attachments)
    return unless attachments.present?

    attachments.each_with_index do |att_meta, index|
      att_data = reader.attachment_by_index(index)
      next unless att_data

      attachment = email.email_attachments.new(
        content_id: att_meta[:content_id],
        inline: att_meta[:inline] || false
      )

      attachment.attach_with_dedup(
        io: att_data[:data],
        filename: att_data[:filename] || "attachment_#{index}",
        content_type: att_data[:content_type] || "application/octet-stream"
      )
    rescue => e
      @logger.warn "  Failed to attach #{att_meta[:filename]}: #{e.message}"
    end
  end
end
