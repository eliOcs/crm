class LlmCompanyDeduplicator
  MODEL = "claude-3-5-haiku-latest"
  MAX_IMAGES = 50 # Max images to send (companies with logos)

  def initialize(companies)
    @companies = companies
    @client = Anthropic::Client.new
  end

  def find_duplicates
    return [] if @companies.size < 2

    messages = build_messages
    response = @client.messages.create(
      model: MODEL,
      max_tokens: 4096,
      messages: messages,
      system: system_prompt
    )

    parse_response(response)
  rescue Anthropic::Error => e
    Rails.logger.error("LLM deduplication failed: #{e.message}")
    []
  end

  private

  def system_prompt
    <<~PROMPT
      You are a company deduplication assistant. Analyze a list of companies and identify which ones are likely duplicates of each other.

      Look for:
      - Same company with different name variations (e.g., "ITPSA" vs "Industrial Técnica Pecuaria, S.A.")
      - Abbreviations and full names (e.g., "Casa MG" vs "Casa Mendes Gonçalves")
      - Typos or accent variations (e.g., "Técnica" vs "Tecnica")
      - Same domain indicating same company
      - Visually similar or identical logos
      - STRONG SIGNAL: Contacts linked to multiple companies (if the same person works at two "different" companies, they're likely duplicates)

      Return ONLY valid JSON with this structure:
      {
        "duplicate_groups": [
          {
            "company_ids": [26, 51],
            "reason": "Same company - 'Casa MG' appears to be abbreviation of 'Casa Mendes Gonçalves', logos are identical"
          }
        ]
      }

      Guidelines:
      - Only group companies you are confident are duplicates
      - Be conservative: different companies may have similar logos (e.g., both use green colors)
      - Shared contacts are a VERY strong signal - prioritize this over logo similarity
      - Each company should appear in at most ONE group
      - company_ids should contain 2 or more IDs
      - If no duplicates found, return {"duplicate_groups": []}
      - Do not include any text outside the JSON object
    PROMPT
  end

  def build_messages
    content = []

    content << {
      type: "text",
      text: build_companies_text
    }

    # Add logos for companies that have them
    companies_with_logos = @companies.select { |c| c.logo.attached? }.first(MAX_IMAGES)
    companies_with_logos.each do |company|
      logo_data = read_logo(company)
      next unless logo_data

      content << {
        type: "text",
        text: "Logo for company ID #{company.id} (#{company.name}):"
      }
      content << {
        type: "image",
        source: {
          type: "base64",
          media_type: logo_data[:content_type],
          data: logo_data[:base64_data]
        }
      }
    end

    [ { role: "user", content: content } ]
  end

  def build_companies_text
    lines = [ "Companies to analyze for duplicates:", "" ]

    @companies.each do |company|
      parts = [ "ID: #{company.id}", "Name: #{company.name}" ]
      parts << "Domain: #{company.domain}" if company.domain.present?
      parts << "Website: #{company.website}" if company.website.present? && company.website != company.domain
      parts << "Has logo: yes" if company.logo.attached?
      parts << "Contacts: #{company.contacts.count}"
      lines << parts.join(" | ")
    end

    # Add shared contacts info (strong duplicate signal)
    shared_contacts = find_shared_contacts
    if shared_contacts.any?
      lines << ""
      lines << "IMPORTANT - Contacts linked to multiple companies (strong duplicate signal):"
      shared_contacts.each do |contact, company_ids|
        lines << "  #{contact.email} (#{contact.name}) → Company IDs: #{company_ids.join(', ')}"
      end
    end

    lines.join("\n")
  end

  def find_shared_contacts
    # Find contacts that belong to multiple companies in our set
    company_ids = @companies.map(&:id)
    shared = {}

    Contact.joins(:companies)
           .where(companies: { id: company_ids })
           .group("contacts.id")
           .having("COUNT(companies.id) > 1")
           .includes(:companies)
           .each do |contact|
      relevant_company_ids = contact.companies.where(id: company_ids).pluck(:id)
      shared[contact] = relevant_company_ids if relevant_company_ids.size > 1
    end

    shared
  end

  def read_logo(company)
    return nil unless company.logo.attached?

    blob = company.logo.blob
    content_type = normalize_content_type(blob.content_type)
    data = blob.download

    {
      content_type: content_type,
      base64_data: Base64.strict_encode64(data)
    }
  rescue => e
    Rails.logger.error("Failed to read logo for company #{company.id}: #{e.message}")
    nil
  end

  def normalize_content_type(content_type)
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
      "image/jpeg"
    end
  end

  def parse_response(response)
    text = response.content.first.text
    json_match = text.match(/\{[\s\S]*\}/)
    return [] unless json_match

    data = JSON.parse(json_match[0])
    Array(data["duplicate_groups"]).map do |group|
      {
        company_ids: Array(group["company_ids"]).map(&:to_i),
        reason: group["reason"]
      }
    end.select { |g| g[:company_ids].size >= 2 }
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse LLM deduplication response: #{e.message}")
    []
  end
end
