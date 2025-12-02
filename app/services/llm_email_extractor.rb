class LlmEmailExtractor
  MODEL = "claude-3-5-haiku-latest"
  MAX_IMAGES = 10

  def initialize(eml_path)
    @eml_path = eml_path
    @client = Anthropic::Client.new
    @image_data = {}
  end

  def extract
    email_data = EmlReader.new(@eml_path).read
    return empty_result unless email_data

    @image_data = extract_inline_images(email_data)
    @email_text = build_email_text(email_data)

    # Two focused extraction calls for better accuracy
    contacts = extract_contacts
    companies = extract_companies

    { contacts: contacts, companies: companies, image_data: @image_data }
  rescue Anthropic::Error => e
    Rails.logger.error("LLM extraction failed: #{e.message}")
    empty_result
  end

  private

  def empty_result
    { contacts: [], companies: [], image_data: {} }
  end

  # === CONTACTS EXTRACTION ===

  def extract_contacts
    response = @client.messages.create(
      model: MODEL,
      max_tokens: 2048,
      temperature: 0,
      messages: [ { role: "user", content: @email_text } ],
      system: contacts_system_prompt
    )
    parse_contacts_response(response)
  rescue Anthropic::Error => e
    Rails.logger.error("Contact extraction failed: #{e.message}")
    []
  end

  def contacts_system_prompt
    <<~PROMPT
      You are a contact information extractor. Extract ALL people mentioned in emails.

      <instructions>
      Extract ALL contacts from the email:
      1. From/To/Cc headers - extract every email address
      2. Email signatures - extract detailed info (name, role, phone, etc.)
      3. Forwarded email headers - extract sender/recipients from "De:", "From:", "Para:", "To:" lines
      4. Email body mentions - any person referenced by name or email

      For each contact, extract:
      - email: Email address (required, lowercase)
      - name: Full name (if available)
      - job_role: Job title - NOT the department (see examples below)
      - department: Department or division name
      - phone_numbers: Array of phone numbers with country codes
      - company_name: Company name from signature (used to infer company domain)

      Distinguishing job_role vs department:
      - "[Department] Manager" -> extract the department name, job_role is "Manager"
      - "[Department] Technician" -> extract the department name, job_role is "Technician"
      - "Senior Engineer" -> job_role only, no department
      - "[Division] Director" -> extract division as department, job_role is "Director"
      </instructions>

      <output_format>
      Return ONLY a JSON array of contacts:
      [
        {"email": "john@example.com", "name": "John Doe", "job_role": "Manager", "department": "Sales", "phone_numbers": ["+1-555-1234"], "company_name": "Example Corp"}
      ]

      If no contacts found, return: []
      </output_format>

      <guidelines>
      - Extract EVERY email address mentioned, even if minimal info available
      - Use null for unknown fields, never hallucinate
      - Normalize emails to lowercase
      - Include country codes in phone numbers when visible
      </guidelines>
    PROMPT
  end

  def parse_contacts_response(response)
    text = response.content.first.text
    json_match = text.match(/\[[\s\S]*\]/)
    return [] unless json_match

    Array(JSON.parse(json_match[0])).map do |contact|
      {
        email: contact["email"]&.strip&.downcase,
        name: contact["name"]&.strip.presence,
        job_role: contact["job_role"]&.strip.presence,
        department: contact["department"]&.strip.presence,
        phone_numbers: Array(contact["phone_numbers"]).map(&:strip).reject(&:blank?),
        company_name: contact["company_name"]&.strip.presence
      }
    end.select { |c| c[:email].present? }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse contacts response: #{e.message}")
    []
  end

  # === COMPANIES EXTRACTION ===

  def extract_companies
    content = [ { type: "text", text: @email_text } ]

    # Add images for logo identification
    @image_data.first(MAX_IMAGES).each do |content_id, image|
      content << { type: "text", text: "Image (content_id: #{content_id}):" }
      content << {
        type: "image",
        source: {
          type: "base64",
          media_type: image[:content_type],
          data: image[:base64_data]
        }
      }
    end

    response = @client.messages.create(
      model: MODEL,
      max_tokens: 2048,
      temperature: 0,
      messages: [ { role: "user", content: content } ],
      system: companies_system_prompt
    )
    parse_companies_response(response)
  rescue Anthropic::Error => e
    Rails.logger.error("Company extraction failed: #{e.message}")
    []
  end

  def companies_system_prompt
    <<~PROMPT
      You are a company information extractor. Extract ALL companies/organizations mentioned in emails.

      <instructions>
      Extract ALL companies from the email:
      1. Email signatures - company names, addresses, websites
      2. Email domains - infer company from contact email domains
      3. Legal notices/disclaimers - often contain full legal names, addresses, and VAT IDs
      4. Forwarded emails - companies mentioned in nested signatures

      For each company, extract:
      - legal_name: Full official/registered name (includes legal suffix like S.A., S.L., Inc., Ltd., GmbH)
      - commercial_name: Brand/trade name commonly used (shorter, without legal suffix)
      - domain: Email domain for this company (e.g., "example.com" from contacts @example.com)
      - website: Official website URL
      - location: Physical address from signature or legal notice
      - vat_id: Tax/VAT identification number (C.I.F., NIF, VAT, Tax ID, EIN, etc.)
      - logo_content_id: Content ID of the company's logo image (if visible in signature)

      Image references in the email use markdown: ![alt](cid:image_id)
      Match logo images to companies by their position near company names in signatures.
      </instructions>

      <output_format>
      Return ONLY a JSON array of companies:
      [
        {"legal_name": "Example Corporation Inc.", "commercial_name": "Example", "domain": "example.com", "website": "https://example.com", "location": "123 Main St, City, Country", "vat_id": "XX12345678", "logo_content_id": "image001.png"}
      ]

      If no companies found, return: []
      </output_format>

      <guidelines>
      - Extract both legal and commercial names when available
      - IMPORTANT: Always extract domain from contact emails associated with this company
      - Infer website from domain if not explicit (e.g., domain "example.com" -> website "https://example.com")
      - Look carefully at legal notices/disclaimers at the bottom of emails for VAT IDs
      - Use null for unknown fields, never hallucinate
      - Only set logo_content_id if you can identify a logo image for that company
      </guidelines>
    PROMPT
  end

  def parse_companies_response(response)
    text = response.content.first.text
    json_match = text.match(/\[[\s\S]*\]/)
    return [] unless json_match

    Array(JSON.parse(json_match[0])).map do |company|
      {
        legal_name: company["legal_name"]&.strip.presence,
        commercial_name: company["commercial_name"]&.strip.presence,
        domain: company["domain"]&.strip&.downcase.presence,
        website: company["website"]&.strip.presence,
        location: company["location"]&.strip.presence,
        vat_id: company["vat_id"]&.strip.presence,
        logo_content_id: company["logo_content_id"]&.strip.presence
      }
    end.select { |c| c[:legal_name].present? || c[:commercial_name].present? }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse companies response: #{e.message}")
    []
  end

  # === SHARED HELPERS ===

  def build_email_text(email_data)
    parts = []
    parts << "From: #{format_address(email_data[:from])}" if email_data[:from]
    parts << "To: #{email_data[:to].map { |a| format_address(a) }.join(', ')}" if email_data[:to].present?
    parts << "Cc: #{email_data[:cc].map { |a| format_address(a) }.join(', ')}" if email_data[:cc].present?
    parts << "Subject: #{email_data[:subject]}" if email_data[:subject]
    parts << "Date: #{email_data[:date]}" if email_data[:date]
    parts << ""

    if email_data[:html_body].present?
      markdown = HtmlToMarkdown.new(email_data[:html_body]).convert
      parts << "--- Email Body (Markdown) ---"
      parts << markdown.truncate(12000)
    elsif email_data[:body].present?
      parts << "--- Email Body ---"
      parts << email_data[:body]
    else
      parts << "(no body)"
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
    seen_hashes = {}

    email_data[:attachments].each do |attachment|
      next unless attachment[:content_type]&.start_with?("image/")

      cid = attachment[:content_id]&.split("@")&.first
      next unless cid

      attachment_data = reader.attachment(cid)
      next unless attachment_data

      sha = Digest::SHA256.hexdigest(attachment_data[:data])
      next if seen_hashes[sha]
      seen_hashes[sha] = cid

      images[cid] = {
        content_type: normalize_content_type(attachment_data[:content_type]),
        base64_data: Base64.strict_encode64(attachment_data[:data]),
        raw_data: attachment_data[:data]
      }
    end

    images
  end

  def normalize_content_type(content_type)
    case content_type&.downcase
    when "image/jpeg", "image/jpg" then "image/jpeg"
    when "image/png" then "image/png"
    when "image/gif" then "image/gif"
    when "image/webp" then "image/webp"
    else "image/jpeg"
    end
  end
end
