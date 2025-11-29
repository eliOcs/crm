class LlmContactExtractor
  MODEL = "claude-3-5-haiku-latest"
  MAX_IMAGES = 5

  def initialize(eml_path)
    @eml_path = eml_path
    @client = Anthropic::Client.new
  end

  def extract
    email_data = EmlReader.new(@eml_path).read
    return [] unless email_data

    messages = build_messages(email_data)
    response = @client.messages.create(
      model: MODEL,
      max_tokens: 2048,
      messages: messages,
      system: system_prompt
    )

    parse_response(response)
  rescue Anthropic::Error => e
    Rails.logger.error("LLM extraction failed: #{e.message}")
    []
  end

  private

  def system_prompt
    <<~PROMPT
      You are a contact information extractor. Analyze emails and their attachments (especially signature images) to extract contact details.

      Extract ALL contacts mentioned in the email, including:
      - Sender and recipients (from headers)
      - People mentioned in email signatures
      - People mentioned in the email body

      For each contact, extract:
      - email: Email address (required)
      - name: Full name
      - job_role: Job title or role (e.g., "Software Engineer", "CEO", "Sales Manager")
      - phone_numbers: Array of phone numbers (include country codes if visible)

      Return ONLY a valid JSON array of contacts. Example:
      [
        {
          "email": "john.doe@example.com",
          "name": "John Doe",
          "job_role": "Senior Developer",
          "phone_numbers": ["+1-555-123-4567"]
        }
      ]

      If you cannot find any contacts, return an empty array: []
      Do not include any text outside the JSON array.
    PROMPT
  end

  def build_messages(email_data)
    content = []

    # Add email text content
    content << {
      type: "text",
      text: build_email_text(email_data)
    }

    # Add inline images (signature images often contain contact info)
    images = extract_inline_images(email_data)
    images.first(MAX_IMAGES).each do |image|
      content << {
        type: "image",
        source: {
          type: "base64",
          media_type: image[:content_type],
          data: image[:base64_data]
        }
      }
    end

    [ { role: "user", content: content } ]
  end

  def build_email_text(email_data)
    parts = []
    parts << "From: #{format_address(email_data[:from])}" if email_data[:from]
    parts << "To: #{email_data[:to].map { |a| format_address(a) }.join(', ')}" if email_data[:to].present?
    parts << "Cc: #{email_data[:cc].map { |a| format_address(a) }.join(', ')}" if email_data[:cc].present?
    parts << "Subject: #{email_data[:subject]}" if email_data[:subject]
    parts << "Date: #{email_data[:date]}" if email_data[:date]
    parts << ""
    parts << "--- Email Body ---"
    parts << (email_data[:body].presence || "(no text body)")

    if email_data[:html_body].present?
      # Extract text from HTML for additional context
      plain_from_html = ActionController::Base.helpers.strip_tags(email_data[:html_body])
      if plain_from_html.present? && plain_from_html != email_data[:body]
        parts << ""
        parts << "--- HTML Body (text extracted) ---"
        parts << plain_from_html.truncate(3000)
      end
    end

    parts.join("\n")
  end

  def format_address(addr)
    return "" unless addr
    if addr[:name].present?
      "#{addr[:name]} <#{addr[:email]}>"
    else
      addr[:email].to_s
    end
  end

  def extract_inline_images(email_data)
    images = []
    return images unless email_data[:attachments].present?

    reader = EmlReader.new(@eml_path)

    email_data[:attachments].each do |attachment|
      next unless attachment[:content_type]&.start_with?("image/")

      cid = attachment[:content_id]&.split("@")&.first
      next unless cid

      attachment_data = reader.attachment(cid)
      next unless attachment_data

      images << {
        content_type: normalize_content_type(attachment_data[:content_type]),
        base64_data: Base64.strict_encode64(attachment_data[:data])
      }
    end

    images
  end

  def normalize_content_type(content_type)
    # Claude accepts: image/jpeg, image/png, image/gif, image/webp
    case content_type&.downcase
    when "image/jpeg", "image/jpg"
      "image/jpeg"
    when "image/png"
      "image/png"
    when "image/gif"
      "image/gif"
    when "image/webp"
      "image/webp"
    else
      "image/jpeg" # Default fallback
    end
  end

  def parse_response(response)
    text = response.content.first.text
    # Extract JSON array from response (in case there's extra text)
    json_match = text.match(/\[[\s\S]*\]/)
    return [] unless json_match

    contacts = JSON.parse(json_match[0])
    contacts.map do |contact|
      {
        email: contact["email"]&.strip&.downcase,
        name: contact["name"]&.strip.presence,
        job_role: contact["job_role"]&.strip.presence,
        phone_numbers: Array(contact["phone_numbers"]).map(&:strip).reject(&:blank?)
      }
    end.select { |c| c[:email].present? }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse LLM response: #{e.message}")
    []
  end
end
