class ContactEnrichmentService
  attr_reader :user, :stats

  def initialize(user, logger: Rails.logger)
    @user = user
    @logger = logger
    @stats = {
      contacts_new: 0,
      contacts_enriched: 0,
      contacts_skipped: 0,
      companies_new: 0,
      companies_enriched: 0,
      companies_web_enriched: 0,
      logos_attached: 0,
      errors: 0
    }
  end

  def process_email(eml_path)
    result = LlmEmailExtractor.new(eml_path).extract
    @logger.info "  LLM: #{result[:contacts].count} contacts, #{result[:companies].count} companies"

    company_map = {}
    result[:companies].each do |company_data|
      company = process_company(company_data, result)
      next unless company

      company_map[company_data[:legal_name]] = company if company_data[:legal_name]
      company_map[company_data[:commercial_name]] = company if company_data[:commercial_name]
    end

    result[:contacts].each do |contact_data|
      process_contact(contact_data, company_map)
    end
  end

  private

  def find_company_by_domain(website)
    return nil unless website.present?
    domain = Company.normalize_domain(website)
    return nil unless domain.present?
    @user.companies.find_by(domain: domain)
  end

  def find_company_by_name(name)
    return nil unless name.present?
    name_pattern = "%#{name.downcase}%"
    @user.companies.find_by("LOWER(legal_name) LIKE ? OR LOWER(commercial_name) LIKE ?", name_pattern, name_pattern)
  end

  def process_company(company_data, result)
    display_name = company_data[:commercial_name] || company_data[:legal_name]
    return nil unless display_name

    display_name_lower = display_name.downcase
    contact_domains = result[:contacts]
      .select { |c| c[:company_name]&.downcase == display_name_lower }
      .map { |c| c[:email]&.split("@")&.last }
      .compact.uniq

    # Try to find existing company
    company = find_company_by_domain(company_data[:website])
    company ||= find_company_by_name(company_data[:legal_name])
    company ||= find_company_by_name(company_data[:commercial_name])

    enriched = {}
    if company.nil?
      @logger.info "  Web enriching: #{display_name}..."
      enriched = CompanyWebEnricher.new(
        display_name,
        hint_domain: company_data[:website],
        contact_domains: contact_domains
      ).enrich

      if enriched.any?
        @stats[:companies_web_enriched] += 1
        @logger.info "  Web enriched: #{enriched[:legal_name] || enriched[:commercial_name]}"

        company = find_company_by_domain(enriched[:website])
        company ||= find_company_by_name(enriched[:legal_name])
        company ||= find_company_by_name(enriched[:commercial_name])

        # Domain mismatch check
        if company && contact_domains.any?
          enriched_domain = Company.normalize_domain(enriched[:website])
          domains_match = contact_domains.any? { |cd| cd == enriched_domain || cd.end_with?(".#{enriched_domain}") }

          if !domains_match
            @logger.info "  Domain mismatch: contacts use #{contact_domains.join(', ')} but enriched domain is #{enriched_domain}"
            enriched[:parent_company_name] ||= company.display_name
            company = nil
          end
        end

        @logger.info "  Matched existing company: #{company.display_name}" if company
      end
    else
      @logger.info "  Found by lookup: #{company.display_name} (id=#{company.id})"
    end

    # Create company if still not found
    was_new = company.nil?
    if was_new
      website_to_use = enriched[:website] || company_data[:website]
      if enriched[:parent_company_name].present? && contact_domains.any?
        website_to_use = "https://#{contact_domains.first}"
      end

      company = @user.companies.create!(
        legal_name: enriched[:legal_name] || company_data[:legal_name] || display_name,
        commercial_name: enriched[:commercial_name] || company_data[:commercial_name],
        website: website_to_use,
        description: enriched[:description],
        industry: enriched[:industry],
        location: enriched[:location],
        web_enriched_at: enriched.any? ? Time.current : nil
      )
      @stats[:companies_new] += 1
      @logger.info "  DB: CREATE company id=#{company.id} legal_name=#{company.legal_name.inspect}"
    end

    # Handle parent company
    if enriched[:parent_company_name].present? && company.parent_company_id.nil?
      parent = find_company_by_name(enriched[:parent_company_name])

      if parent.nil?
        @logger.info "  Web enriching parent: #{enriched[:parent_company_name]}..."
        parent_enriched = CompanyWebEnricher.new(enriched[:parent_company_name]).enrich

        if parent_enriched.any?
          @stats[:companies_web_enriched] += 1
          @logger.info "  Web enriched parent: #{parent_enriched[:legal_name] || parent_enriched[:commercial_name]}"

          parent = find_company_by_domain(parent_enriched[:website])
          parent ||= find_company_by_name(parent_enriched[:legal_name])
          parent ||= find_company_by_name(parent_enriched[:commercial_name])
        end

        if parent.nil?
          parent = @user.companies.create!(
            legal_name: parent_enriched[:legal_name] || enriched[:parent_company_name],
            commercial_name: parent_enriched[:commercial_name],
            website: parent_enriched[:website],
            description: parent_enriched[:description],
            industry: parent_enriched[:industry],
            location: parent_enriched[:location],
            web_enriched_at: parent_enriched.any? ? Time.current : nil
          )
          @stats[:companies_new] += 1
          @logger.info "  DB: CREATE parent company id=#{parent.id} legal_name=#{parent.legal_name.inspect}"
        else
          @logger.info "  Matched existing parent: #{parent.display_name} (id=#{parent.id})"
        end
      end

      company.update!(parent_company_id: parent.id)
      @logger.info "  DB: SET parent_company company_id=#{company.id} parent_id=#{parent.id}"
    end

    company
  end

  def process_contact(contact_data, company_map)
    contact = @user.contacts.find_or_initialize_by(email: contact_data[:email])

    was_new = contact.new_record?
    updates = {}

    if contact_data[:name].present? && contact.name.blank?
      updates[:name] = contact_data[:name]
    end

    if contact_data[:job_role].present? && contact.job_role.blank?
      updates[:job_role] = contact_data[:job_role]
    end

    if contact_data[:phone_numbers].present?
      existing_phones = contact.phone_numbers || []
      new_phones = (existing_phones + contact_data[:phone_numbers]).uniq
      updates[:phone_numbers] = new_phones if new_phones != existing_phones
    end

    if was_new
      contact.assign_attributes(updates)
      contact.save!
      @stats[:contacts_new] += 1
      @logger.info "  DB: CREATE contact id=#{contact.id} email=#{contact.email}"
    elsif updates.any?
      contact.update!(updates)
      @stats[:contacts_enriched] += 1
    else
      @stats[:contacts_skipped] += 1
    end

    # Link to company
    if contact_data[:company_name].present?
      company = company_map[contact_data[:company_name]]
      company ||= find_company_by_name(contact_data[:company_name])

      if company && !contact.companies.include?(company)
        contact.companies << company
        @logger.info "  DB: LINK contact_id=#{contact.id} company_id=#{company.id}"
      end
    end
  end
end
