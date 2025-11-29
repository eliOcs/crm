class CompanyWebEnricher
  MODEL = "claude-sonnet-4-5-20250929"

  def initialize(company_name, hint_domain: nil)
    @company_name = company_name
    @hint_domain = hint_domain
    @client = Anthropic::Client.new
  end

  def enrich
    # Use beta API with structured outputs
    response = @client.beta.messages.create(
      model: MODEL,
      max_tokens: 1024,
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
          name: { type: "string", description: "The full official/legal company name, or empty string if unknown" },
          website: { type: "string", description: "The company's official website URL, or empty string if unknown" },
          description: { type: "string", description: "A brief 1-2 sentence description, or empty string if unknown" },
          industry: { type: "string", description: "The industry or sector, or empty string if unknown" },
          location: { type: "string", description: "Headquarters location (city, country), or empty string if unknown" }
        },
        required: %w[name website description industry location],
        additionalProperties: false
      }
    }
  end

  def prompt
    domain_hint = @hint_domain.present? ? " (possibly associated with #{@hint_domain})" : ""

    <<~PROMPT
      Search for information about the company "#{@company_name}"#{domain_hint}.

      Find the company's full legal name, official website, a brief description of what they do,
      their industry/sector, and headquarters location.

      If you cannot find reliable information for a field, use an empty string.
    PROMPT
  end

  def parse_response(response)
    # With structured outputs, the response should be valid JSON
    text_block = response.content.find { |block| block.type == :text }
    return {} unless text_block

    data = JSON.parse(text_block.text)

    {
      name: data["name"]&.strip.presence,
      website: data["website"]&.strip.presence,
      description: data["description"]&.strip.presence,
      industry: data["industry"]&.strip.presence,
      location: data["location"]&.strip.presence
    }.compact
  rescue JSON::ParserError => e
    Rails.logger.warn("Failed to parse company enrichment response: #{e.message}")
    {}
  end
end
