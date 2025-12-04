class ContactEnrichmentService
  include Auditable

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
      logos_attached: 0,
      errors: 0
    }
  end

  def process_email(eml_path)
    @source_email = eml_path
    result = LlmEmailExtractor.new(eml_path).extract
    @logger.info "  LLM: #{result[:contacts].count} contacts, #{result[:companies].count} companies"

    # Build domain map for company lookup
    domain_map = {}

    result[:companies].each do |company_data|
      company = process_company(company_data, result)
      next unless company

      domain_map[company.domain] = company if company.domain.present?
    end

    result[:contacts].each do |contact_data|
      process_contact(contact_data, domain_map)
    end
  end

  private

  def process_company(company_data, result)
    display_name = company_data[:commercial_name] || company_data[:legal_name]
    return nil unless display_name

    domain = company_data[:domain]
    company = @user.companies.find_by(domain: domain) if domain.present?
    company ||= @user.companies.find_by(legal_name: company_data[:legal_name]) if company_data[:legal_name].present?
    company ||= @user.companies.find_by(commercial_name: company_data[:commercial_name]) if company_data[:commercial_name].present?

    if company
      @logger.info "  Found existing: #{company.display_name} (id=#{company.id})"
    else
      company = @user.companies.create!(
        legal_name: company_data[:legal_name],
        commercial_name: company_data[:commercial_name],
        domain: domain,
        website: company_data[:website],
        location: company_data[:location],
        vat_id: company_data[:vat_id]
      )
      @stats[:companies_new] += 1
      @logger.info "  DB: CREATE company id=#{company.id} legal_name=#{company.legal_name.inspect} domain=#{domain}"

      log_audit(
        record: company,
        action: "create",
        message: "email extraction",
        field_changes: build_field_changes(company),
        metadata: { source_email: @source_email }
      )
    end

    attach_logo(company, company_data, result)

    company
  end

  def attach_logo(company, company_data, result)
    return if company.logo.attached?
    return unless company_data[:logo_content_id].present?

    image_data = result[:image_data][company_data[:logo_content_id]]
    return unless image_data

    extension = case image_data[:content_type]
    when "image/jpeg" then ".jpg"
    when "image/png" then ".png"
    when "image/gif" then ".gif"
    when "image/webp" then ".webp"
    else ".jpg"
    end

    company.logo.attach(
      io: StringIO.new(image_data[:raw_data]),
      filename: "logo#{extension}",
      content_type: image_data[:content_type]
    )
    @stats[:logos_attached] += 1
    @logger.info "  DB: ATTACH logo company_id=#{company.id} cid=#{company_data[:logo_content_id]}"
  end

  def process_contact(contact_data, domain_map)
    contact = @user.contacts.find_or_initialize_by(email: contact_data[:email])

    was_new = contact.new_record?
    updates = {}

    if contact_data[:name].present? && contact.name.blank?
      updates[:name] = contact_data[:name]
    end

    if contact_data[:job_role].present? && contact.job_role.blank?
      updates[:job_role] = contact_data[:job_role]
    end

    if contact_data[:department].present? && contact.department.blank?
      updates[:department] = contact_data[:department]
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

      log_audit(
        record: contact,
        action: "create",
        message: "email extraction",
        field_changes: build_field_changes(contact),
        metadata: { source_email: @source_email }
      )
    elsif updates.any?
      contact.update!(updates)
      @stats[:contacts_enriched] += 1

      log_audit(
        record: contact,
        action: "update",
        message: "email extraction",
        field_changes: build_field_changes(contact),
        metadata: { source_email: @source_email }
      )
    else
      @stats[:contacts_skipped] += 1
    end

    # Link to company by email domain
    return unless contact_data[:email].present?

    domain = contact_data[:email].split("@").last&.downcase
    return unless domain.present?

    company = domain_map[domain]
    company ||= @user.companies.find_by(domain: domain)

    if company && !contact.companies.include?(company)
      contact.companies << company
      @logger.info "  DB: LINK contact_id=#{contact.id} company_id=#{company.id}"

      log_audit(
        record: contact,
        action: "link",
        message: "company link",
        field_changes: { "company_id" => { "from" => nil, "to" => company.id } },
        metadata: { source_email: @source_email }
      )
    end
  end
end
