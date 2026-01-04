class InboundMailbox < ApplicationMailbox
  def process
    user = find_user_by_recipient
    unless user
      Rails.logger.warn "[InboundMailbox] No user found for recipient: #{mail.to}"
      # Return 204 but don't process - email is silently discarded
      return
    end

    email = create_email_record(user)
    if email
      import_attachments(email)
      email.find_or_link_sender_contact
      Rails.logger.info "[InboundMailbox] Imported email id=#{email.id} for user=#{user.id}"
    end
  rescue => e
    Rails.logger.error "[InboundMailbox] Error processing email: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    # Re-raise to return 500 and trigger Postfix retry
    raise
  end

  private

  def find_user_by_recipient
    # mail.to can be an array of addresses
    Array(mail.to).each do |recipient|
      user = User.find_by_inbound_email(recipient)
      return user if user
    end
    nil
  end

  def create_email_record(user)
    message_id = extract_message_id

    # Skip if already imported (by message_id)
    if message_id.present? && user.emails.exists?(message_id: message_id)
      Rails.logger.debug "[InboundMailbox] Skipped duplicate: #{message_id}"
      return nil
    end

    user.emails.create!(
      subject: mail.subject,
      sent_at: mail.date || Time.current,
      body_plain: extract_plain_body,
      body_html: extract_html_body,
      from_address: extract_address(mail.from&.first),
      to_addresses: Array(mail.to).map { |a| extract_address(a) },
      cc_addresses: Array(mail.cc).map { |a| extract_address(a) },
      message_id: message_id,
      in_reply_to: extract_in_reply_to,
      references: extract_references,
      source_type: "forwarded"
    )
  end

  def import_attachments(email)
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
      Rails.logger.warn "[InboundMailbox] Failed to attach #{attachment.filename}: #{e.message}"
    end
  end

  def extract_message_id
    mail.message_id&.gsub(/[<>]/, "")
  end

  def extract_in_reply_to
    reply_to = mail.in_reply_to
    return nil unless reply_to
    Array(reply_to).first&.gsub(/[<>]/, "")
  end

  def extract_references
    refs = mail.references
    return [] unless refs
    Array(refs).map { |r| r.gsub(/[<>]/, "") }
  end

  def extract_plain_body
    if mail.multipart?
      mail.text_part&.decoded
    else
      mail.content_type&.include?("text/plain") ? mail.decoded : nil
    end
  rescue => e
    Rails.logger.warn "[InboundMailbox] Error decoding plain body: #{e.message}"
    nil
  end

  def extract_html_body
    if mail.multipart?
      mail.html_part&.decoded
    else
      mail.content_type&.include?("text/html") ? mail.decoded : nil
    end
  rescue => e
    Rails.logger.warn "[InboundMailbox] Error decoding HTML body: #{e.message}"
    nil
  end

  def extract_address(addr)
    return { "email" => "unknown@unknown", "name" => nil } unless addr

    parsed = Mail::Address.new(addr)
    { "email" => parsed.address&.downcase, "name" => parsed.display_name }
  rescue
    { "email" => addr.to_s.downcase, "name" => nil }
  end
end
