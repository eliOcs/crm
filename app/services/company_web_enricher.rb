class CompanyWebEnricher
  MODEL = "claude-sonnet-4-5-20250929"

  def initialize(company_name, hint_domain: nil, contact_domains: [])
    @company_name = company_name
    @hint_domain = hint_domain
    @contact_domains = contact_domains
    @client = Anthropic::Client.new
  end

  def enrich
    # Use beta API with structured outputs
    response = @client.beta.messages.create(
      model: MODEL,
      max_tokens: 1024,
      temperature: 0,  # Deterministic output
      betas: [ "structured-outputs-2025-11-13" ],
      tools: [ web_search_tool ],
      messages: [ { role: "user", content: prompt } ],
      output_format: output_schema
    )

    parse_response(response)
  rescue Anthropic::Errors::Error => e
    Rails.logger.warn("Company web enrichment failed: #{e.message}")
    {}
  rescue => e
    Rails.logger.warn("Company web enrichment error: #{e.message}")
    {}
  end

  private

  def web_search_tool
    {
      type: "web_search_20250305",
      name: "web_search",
      max_uses: 3
    }
  end

  def output_schema
    {
      type: "json_schema",
      schema: {
        type: "object",
        properties: {
          legal_name: { type: "string", description: "The full official/legal registered company name" },
          commercial_name: { type: "string", description: "The brand or trade name the company is commonly known by" },
          website: { type: "string", description: "The company's official website URL" },
          logo_url: { type: "string", description: "Direct URL to the company's official logo image (PNG, JPG, or SVG)" },
          description: { type: "string", description: "A brief 1-2 sentence description" },
          industry: { type: "string", description: "The industry or sector" },
          location: { type: "string", description: "Headquarters location (city, country)" },
          parent_company_name: { type: "string", description: "Name of the parent company/group if this is a subsidiary or brand" }
        },
        additionalProperties: false
      }
    }
  end

  def prompt
    domain_hint = @hint_domain.present? ? " (possibly associated with #{@hint_domain})" : ""
    contact_domains_hint = @contact_domains.any? ? "\nContacts from this company use email domains: #{@contact_domains.join(', ')}" : ""

    <<~PROMPT
      Search for information about the company "#{@company_name}"#{domain_hint}.#{contact_domains_hint}

      Find:
      - legal_name: The full official/legal registered name (e.g., "Acme Corporation, Inc.")
      - commercial_name: The brand or trade name commonly used (e.g., "Acme")
      - website: Official website URL
      - logo_url: Direct URL to their official logo image (look for PNG, JPG, or SVG on their website or press kit)
      - description: Brief description of what they do
      - industry: Industry or sector
      - location: Headquarters location (city, country)
      - parent_company_name: If this company is a subsidiary or brand of a larger group, provide the parent company name

      For logo_url, prefer high-quality logos from the company's official website, press/media kit, or about page.
      Only include fields you find reliable information for.

      IMPORTANT:
      - Return information about the SPECIFIC company requested, not its parent group
      - parent_company_name should be the OWNER/HOLDING company that owns the requested company
      - Example: If searching for "SubsidiaryBrand" owned by "ParentCorp", return SubsidiaryBrand's info with parent_company_name="ParentCorp"
      - Example: If searching for "ParentCorp" (a holding company), do NOT set parent_company_name to one of its subsidiaries - that's backwards!
      - The website should be for the SPECIFIC company requested, not the parent group's website
    PROMPT
  end

  def parse_response(response)
    # With structured outputs, the response should be valid JSON
    text_block = response.content.find { |block| block.type == :text }
    return {} unless text_block

    data = JSON.parse(text_block.text)

    {
      legal_name: data["legal_name"]&.strip.presence,
      commercial_name: data["commercial_name"]&.strip.presence,
      website: data["website"]&.strip.presence,
      logo_url: data["logo_url"]&.strip.presence,
      description: data["description"]&.strip.presence,
      industry: data["industry"]&.strip.presence,
      location: data["location"]&.strip.presence,
      parent_company_name: data["parent_company_name"]&.strip.presence
    }.compact
  rescue JSON::ParserError => e
    Rails.logger.warn("Failed to parse company enrichment response: #{e.message}")
    {}
  end
end
