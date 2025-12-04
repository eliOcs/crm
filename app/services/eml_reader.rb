class EmlReader
  EMAILS_DIR = Rails.root.join("db/seeds/emails")

  def initialize(eml_path)
    @eml_path = eml_path
  end

  def read
    return nil unless File.exist?(@eml_path)

    mail = Mail.read(@eml_path)

    {
      from: extract_address(mail[:from]),
      to: extract_addresses(mail[:to]),
      cc: extract_addresses(mail[:cc]),
      subject: mail.subject,
      date: mail.date,
      body: extract_body(mail),
      html_body: extract_html_body(mail),
      attachments: extract_attachments(mail)
    }
  end

  def attachment(content_id)
    return nil unless File.exist?(@eml_path)

    mail = Mail.read(@eml_path)
    find_attachment_by_cid(mail, content_id)
  end

  def attachment_by_index(index)
    return nil unless File.exist?(@eml_path)

    mail = Mail.read(@eml_path)
    find_attachment_at_index(mail, index, counter: [ 0 ])
  end

  def self.all_paths
    Dir.glob(EMAILS_DIR.join("**/*.eml")).sort
  end

  def self.paginate(page:, per_page: 50)
    paths = all_paths
    total = paths.count
    offset = (page - 1) * per_page

    {
      emails: paths.slice(offset, per_page) || [],
      total: total,
      page: page,
      per_page: per_page,
      total_pages: (total.to_f / per_page).ceil
    }
  end

  def self.encode_path(path)
    Base64.urlsafe_encode64(path)
  end

  def self.decode_path(encoded)
    Base64.urlsafe_decode64(encoded)
  rescue ArgumentError
    nil
  end

  private

  def extract_address(field)
    return nil unless field

    addr = field.addrs.first
    return nil unless addr

    { email: addr.address, name: addr.display_name || addr.name }
  end

  def extract_addresses(field)
    return [] unless field

    field.addrs.map do |addr|
      { email: addr.address, name: addr.display_name || addr.name }
    end
  end

  def extract_body(mail)
    if mail.multipart?
      part = mail.text_part
      part&.decoded.to_s.force_encoding("UTF-8")
    else
      mail.body.decoded.to_s.force_encoding("UTF-8")
    end
  rescue => e
    "(Unable to decode body)"
  end

  def extract_html_body(mail)
    return nil unless mail.multipart?

    part = mail.html_part
    return nil unless part

    part.decoded.to_s.force_encoding("UTF-8")
  rescue => e
    nil
  end

  def extract_attachments(mail)
    attachments = []
    collect_attachments(mail, attachments)
    attachments
  end

  def collect_attachments(mail, attachments)
    mail.parts.each do |part|
      if part.content_type&.start_with?("message/rfc822")
        inner_mail = Mail.new(part.body.decoded)
        collect_attachments(inner_mail, attachments)
      elsif part.content_id.present?
        cid = part.content_id.gsub(/[<>]/, "")
        attachments << {
          index: attachments.size,
          content_id: cid,
          filename: part.filename,
          content_type: part.content_type&.split(";")&.first,
          inline: true
        }
      elsif part.attachment? || part.content_disposition&.start_with?("attachment")
        attachments << {
          index: attachments.size,
          filename: part.filename || "unnamed",
          content_type: part.content_type&.split(";")&.first,
          size: part.body.decoded.bytesize,
          inline: false
        }
      end
    end
  rescue => e
    # Skip malformed parts
  end

  def find_attachment_by_cid(mail, content_id)
    mail.parts.each do |part|
      if part.content_type&.start_with?("message/rfc822")
        inner_mail = Mail.new(part.body.decoded)
        result = find_attachment_by_cid(inner_mail, content_id)
        return result if result
      elsif part.content_id.present?
        cid = part.content_id.gsub(/[<>]/, "")
        # Match by filename prefix (before @) since URLs only contain the filename
        cid_filename = cid.split("@").first
        if cid_filename == content_id
          return {
            data: part.body.decoded,
            content_type: part.content_type&.split(";")&.first || "application/octet-stream",
            filename: part.filename
          }
        end
      end
    end
    nil
  rescue => e
    nil
  end

  def find_attachment_at_index(mail, target_index, counter:)
    mail.parts.each do |part|
      if part.content_type&.start_with?("message/rfc822")
        inner_mail = Mail.new(part.body.decoded)
        result = find_attachment_at_index(inner_mail, target_index, counter: counter)
        return result if result
      elsif part.content_id.present? || part.attachment? || part.content_disposition&.start_with?("attachment")
        if counter[0] == target_index
          return {
            data: part.body.decoded,
            content_type: part.content_type&.split(";")&.first || "application/octet-stream",
            filename: part.filename || "attachment"
          }
        end
        counter[0] += 1
      end
    end
    nil
  rescue => e
    nil
  end
end
