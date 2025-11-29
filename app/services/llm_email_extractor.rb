class LlmEmailExtractor
  MODEL = "claude-3-5-haiku-latest"
  MAX_IMAGES = 5

  def initialize(eml_path)
    @eml_path = eml_path
    @client = Anthropic::Client.new
    @image_data = {}
  end

  def extract
    email_data = EmlReader.new(@eml_path).read
    return empty_result unless email_data

    @image_data = extract_inline_images(email_data)
    messages = build_messages(email_data)
    response = @client.messages.create(
      model: MODEL,
      max_tokens: 2048,
      temperature: 0,  # Deterministic output for consistent extraction
      messages: messages,
      system: cached_system_prompt
    )

    parse_response(response)
  rescue Anthropic::Error => e
    Rails.logger.error("LLM extraction failed: #{e.message}")
    empty_result
  end

  private

  def empty_result
    { contacts: [], companies: [], image_data: {} }
  end

  # Cached system prompt for API efficiency (90% token savings on repeated calls)
  def cached_system_prompt
    [
      {
        type: "text",
        text: system_prompt_text,
        cache_control: { type: "ephemeral" }
      }
    ]
  end

  def system_prompt_text
    <<~PROMPT
      You are a contact and company information extractor. Analyze emails and their attachments (especially signature images) to extract contact and company details.

      <instructions>
      Extract ALL contacts mentioned in the email, including:
      - Sender and recipients (from headers)
      - People mentioned in email signatures
      - People mentioned in the email body

      For each contact, extract:
      - email: Email address (required)
      - name: Full name
      - job_role: Job title or role (e.g., "Software Engineer", "CEO", "Sales Manager")
      - phone_numbers: Array of phone numbers (include country codes if visible)
      - company_name: Name of the company they work for (use commercial/brand name if available)

      Also extract ALL companies mentioned in the email:
      - From email signatures
      - From email domains (e.g., john@acme.com suggests "Acme")
      - From the email body content

      For each company, extract:
      - legal_name: The full official/legal registered name (e.g., "Industrial Técnica Pecuaria, S.A.")
      - commercial_name: The brand or trade name commonly used (e.g., "ITPSA")
      - website: The company's official website URL
      - logo_content_id: If any attached image appears to be a company logo, include its content_id
      </instructions>

      <examples>
      <example>
      Input email:
      From: John Doe <john.doe@acme.com>
      Subject: Meeting next week

      Best regards,
      John Doe
      Senior Developer
      Acme Corporation Inc.
      Tel: +1-555-123-4567
      www.acme.com

      Output:
      {"contacts": [{"email": "john.doe@acme.com", "name": "John Doe", "job_role": "Senior Developer", "phone_numbers": ["+1-555-123-4567"], "company_name": "Acme"}], "companies": [{"legal_name": "Acme Corporation Inc.", "commercial_name": "Acme", "website": "https://acme.com", "logo_content_id": null}]}
      </example>

      <example>
      Input email:
      From: info@newsletter.com
      Subject: Weekly digest

      (no signature)

      Output:
      {"contacts": [{"email": "info@newsletter.com", "name": null, "job_role": null, "phone_numbers": [], "company_name": null}], "companies": []}
      </example>
      </examples>

      <output_format>
      Return ONLY valid JSON with this structure:
      {
        "contacts": [
          {
            "email": "john.doe@acme.com",
            "name": "John Doe",
            "job_role": "Senior Developer",
            "phone_numbers": ["+1-555-123-4567"],
            "company_name": "Acme"
          }
        ],
        "companies": [
          {
            "legal_name": "Acme Corporation Inc.",
            "commercial_name": "Acme",
            "website": "https://acme.com",
            "logo_content_id": "image001"
          }
        ]
      }
      </output_format>

      <guidelines>
      - The company_name in contacts should match either legal_name or commercial_name in companies
      - For website, infer from email domain if not explicitly stated (e.g., @acme.com -> https://acme.com)
      - Set logo_content_id to null if no logo image is identified
      - Use null for fields where information is not available - never hallucinate
      - If no contacts found, return {"contacts": [], "companies": []}
      - Do not include any text outside the JSON object
      </guidelines>
    PROMPT
  end

  def build_messages(email_data)
    content = []

    # Add email text content
    content << {
      type: "text",
      text: build_email_text(email_data)
    }

    # Add inline images with their content IDs
    @image_data.first(MAX_IMAGES).each do |content_id, image|
      content << {
        type: "text",
        text: "Image (content_id: #{content_id}):"
      }
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
    images = {}
    return images unless email_data[:attachments].present?

    reader = EmlReader.new(@eml_path)

    email_data[:attachments].each do |attachment|
      next unless attachment[:content_type]&.start_with?("image/")

      cid = attachment[:content_id]&.split("@")&.first
      next unless cid

      attachment_data = reader.attachment(cid)
      next unless attachment_data

      images[cid] = {
        content_type: normalize_content_type(attachment_data[:content_type]),
        base64_data: Base64.strict_encode64(attachment_data[:data]),
        raw_data: attachment_data[:data]
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
    # Extract JSON object from response (in case there's extra text)
    json_match = text.match(/\{[\s\S]*\}/)
    return empty_result unless json_match

    data = JSON.parse(json_match[0])

    contacts = Array(data["contacts"]).map do |contact|
      {
        email: contact["email"]&.strip&.downcase,
        name: contact["name"]&.strip.presence,
        job_role: contact["job_role"]&.strip.presence,
        phone_numbers: Array(contact["phone_numbers"]).map(&:strip).reject(&:blank?),
        company_name: contact["company_name"]&.strip.presence
      }
    end.select { |c| c[:email].present? }

    companies = Array(data["companies"]).map do |company|
      {
        legal_name: company["legal_name"]&.strip.presence,
        commercial_name: company["commercial_name"]&.strip.presence,
        website: company["website"]&.strip.presence,
        logo_content_id: company["logo_content_id"]&.strip.presence
      }
    end.select { |c| c[:legal_name].present? || c[:commercial_name].present? }

    { contacts: contacts, companies: companies, image_data: @image_data }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse LLM response: #{e.message}")
    empty_result
  end
end
