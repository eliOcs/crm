class MicrosoftEmailImportService
  include Auditable

  attr_reader :user, :stats

  def initialize(user, logger: Rails.logger)
    @user = user
    @credential = user.microsoft_credential
    @logger = logger
    @stats = { imported: 0, skipped: 0, errors: 0 }
  end

  def import_by_graph_id(graph_id)
    return nil unless @credential

    # Check for duplicate
    if @user.emails.exists?(graph_id: graph_id)
      @stats[:skipped] += 1
      @logger.debug "Skipped (duplicate): #{graph_id}"
      return nil
    end

    client = build_client
    message = client.message(graph_id, select: message_fields)

    import_message(message)
  rescue MicrosoftGraphClient::GraphApiError => e
    @stats[:errors] += 1
    @logger.error "Error fetching message #{graph_id}: #{e.message}"
    nil
  end

  private

  def import_message(message)
    email = @user.emails.create!(
      graph_id: message["id"],
      conversation_id: message["conversationId"],
      subject: message["subject"],
      sent_at: parse_datetime(message["sentDateTime"] || message["receivedDateTime"]),
      body_plain: extract_plain_body(message),
      body_html: message.dig("body", "content"),
      from_address: parse_address(message["from"]),
      to_addresses: parse_addresses(message["toRecipients"]),
      cc_addresses: parse_addresses(message["ccRecipients"]),
      message_id: clean_message_id(message["internetMessageId"]),
      source_type: "graph"
    )

    # Import attachments if present
    import_attachments(email, message["id"]) if message["hasAttachments"]

    # Link sender contact if exists
    email.find_or_link_sender_contact

    @stats[:imported] += 1
    @logger.info "Imported email id=#{email.id} graph_id=#{message['id']} subject=#{email.subject.truncate(50)}"

    log_audit(
      record: email,
      action: "create",
      message: "import from Microsoft Graph",
      field_changes: { "source_type" => { "from" => nil, "to" => "graph" } },
      source_email: email
    )

    email
  rescue ActiveRecord::RecordInvalid => e
    @stats[:errors] += 1
    @logger.error "Error importing message: #{e.message}"
    nil
  end

  def import_attachments(email, message_id)
    client = build_client
    response = client.attachments(message_id)
    attachments = response["value"] || []

    attachments.each do |att|
      case att["@odata.type"]
      when "#microsoft.graph.fileAttachment"
        import_file_attachment(email, att)
      when "#microsoft.graph.itemAttachment"
        @logger.debug "Skipping item attachment: #{att['name']}"
      when "#microsoft.graph.referenceAttachment"
        @logger.debug "Skipping reference attachment: #{att['name']}"
      end
    end
  rescue => e
    @logger.warn "Failed to import attachments for #{message_id}: #{e.message}"
  end

  def import_file_attachment(email, att)
    content = Base64.decode64(att["contentBytes"])
    is_inline = att["isInline"] || false

    attachment = email.email_attachments.new(
      content_id: att["contentId"]&.gsub(/[<>]/, ""),
      inline: is_inline
    )

    attachment.attach_with_dedup(
      io: content,
      filename: att["name"] || "attachment",
      content_type: att["contentType"] || "application/octet-stream"
    )

    @logger.debug "Attached #{is_inline ? 'inline' : 'file'}: #{att['name']}"
  rescue => e
    @logger.warn "Failed to attach #{att['name']}: #{e.message}"
  end

  def parse_address(recipient)
    return { "email" => "unknown@unknown", "name" => nil } unless recipient

    email_addr = recipient["emailAddress"]
    {
      "email" => email_addr&.dig("address")&.downcase || "unknown@unknown",
      "name" => email_addr&.dig("name")
    }
  end

  def parse_addresses(recipients)
    return [] unless recipients

    recipients.map { |r| parse_address(r) }
  end

  def extract_plain_body(message)
    body = message["body"]
    return nil unless body

    if body["contentType"] == "text"
      body["content"]
    else
      # Strip HTML to get plain text
      ActionView::Base.full_sanitizer.sanitize(body["content"])
    end
  end

  def clean_message_id(id)
    id&.gsub(/[<>]/, "")
  end

  def parse_datetime(datetime_str)
    return Time.current unless datetime_str

    Time.parse(datetime_str)
  end

  def message_fields
    %w[
      id
      internetMessageId
      conversationId
      subject
      sentDateTime
      receivedDateTime
      from
      toRecipients
      ccRecipients
      body
      hasAttachments
    ]
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
