class EmailEnrichmentService
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
      tasks_new: 0,
      tasks_updated: 0,
      tasks_skipped: 0,
      errors: 0
    }
  end

  def process_email(eml_path)
    # Store path relative to EMAILS_DIR for portability across environments
    source_path = eml_path.to_s.sub("#{EmlReader::EMAILS_DIR}/", "")
    @source_email = @user.emails.find_by(source_path: source_path)

    # Read email data for date
    email_data = EmlReader.new(eml_path).read
    return unless email_data

    email_date = email_data[:date] || Date.current

    # Extract contacts and companies
    extractor = LlmEmailExtractor.new(eml_path)
    perform_extraction(extractor, email_date)
  end

  # Process an Email record directly (for Graph-imported emails)
  def process_email_record(email)
    @source_email = email
    email_date = email.sent_at&.to_date || Date.current

    # Extract contacts and companies using the Email record
    extractor = LlmEmailExtractor.from_email(email)
    perform_extraction(extractor, email_date)
  end

  private

  def perform_extraction(extractor, email_date)
    result = extractor.extract
    @logger.info "  LLM: #{result[:contacts].count} contacts, #{result[:companies].count} companies"

    # Build domain map for company lookup
    domain_map = {}

    result[:companies].each do |company_data|
      company = process_company(company_data, result)
      next unless company

      domain_map[company.domain] = company if company.domain.present?
    end

    # Build contact map for task linking
    contact_map = {}

    result[:contacts].each do |contact_data|
      contact = process_contact(contact_data, domain_map)
      contact_map[contact_data[:email]&.downcase] = contact if contact
    end

    # Extract and process tasks (separate LLM call)
    existing_tasks = @user.tasks.active.includes(:contact, :company).to_a
    tasks = extractor.extract_tasks(email_date: email_date, existing_tasks: existing_tasks, locale: @user.locale)
    @logger.info "  LLM: #{tasks.count} tasks extracted"

    tasks.each do |task_data|
      process_task(task_data, contact_map, domain_map, email_date)
    end
  end

  def process_company(company_data, result)
    # Use commercial_name as legal_name fallback if legal_name is blank
    legal_name = company_data[:legal_name].presence || company_data[:commercial_name].presence
    return nil unless legal_name

    domain = company_data[:domain]
    company = @user.companies.find_by(domain: domain) if domain.present?
    company ||= @user.companies.find_by(legal_name: legal_name)
    company ||= @user.companies.find_by(commercial_name: company_data[:commercial_name]) if company_data[:commercial_name].present?

    if company
      @logger.info "  Found existing: #{company.display_name} (id=#{company.id})"
    else
      company = @user.companies.create!(
        legal_name: legal_name,
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
        source_email: @source_email
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
        source_email: @source_email
      )

      # Link source email to sender contact if this is the sender
      link_email_to_sender_contact(contact)
    elsif updates.any?
      contact.update!(updates)
      @stats[:contacts_enriched] += 1

      log_audit(
        record: contact,
        action: "update",
        message: "email extraction",
        field_changes: build_field_changes(contact),
        source_email: @source_email
      )
    else
      @stats[:contacts_skipped] += 1
    end

    # Link to company by email domain
    if contact_data[:email].present?
      domain = contact_data[:email].split("@").last&.downcase

      if domain.present?
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
            source_email: @source_email
          )
        end
      end
    end

    contact
  end

  def process_task(task_data, contact_map, domain_map, email_date)
    # Find associated contact from sender
    contact = contact_map[task_data[:sender_email]]
    contact ||= @user.contacts.find_by(email: task_data[:sender_email]) if task_data[:sender_email].present?

    # Find associated company from contact or sender domain
    company = contact&.companies&.first
    if company.nil? && task_data[:sender_email].present?
      domain = task_data[:sender_email].split("@").last&.downcase
      company = domain_map[domain] || @user.companies.find_by(domain: domain) if domain.present?
    end

    if task_data[:id].present?
      update_existing_task(task_data, contact, company, email_date)
    else
      create_new_task(task_data, contact, company, email_date)
    end
  end

  def update_existing_task(task_data, contact, company, email_date)
    task = @user.tasks.find_by(id: task_data[:id])

    unless task
      @logger.warn "  Task id=#{task_data[:id]} not found, creating new"
      create_new_task(task_data.merge(id: nil), contact, company, email_date)
      return
    end

    updates = {}

    # Append new context to description
    if task_data[:description].present?
      existing_desc = task.description || ""
      new_context = "\n\n---\nUpdate from #{@source_email&.source_path || 'unknown'}:\n#{task_data[:description]}"
      updates[:description] = existing_desc + new_context
    end

    # Update due date if new one is more urgent
    if task_data[:due_date].present?
      if task.due_date.nil? || task_data[:due_date] < task.due_date
        updates[:due_date] = task_data[:due_date]
      end
    end

    # Link to contact/company if not already linked
    updates[:contact_id] = contact.id if contact && task.contact_id.nil?
    updates[:company_id] = company.id if company && task.company_id.nil?

    if updates.any?
      # Use email date as updated_at
      updates[:updated_at] = email_date if email_date

      task.update!(updates)
      @stats[:tasks_updated] += 1
      @logger.info "  DB: UPDATE task id=#{task.id} #{updates.keys.join(', ')}"

      log_audit(
        record: task,
        action: "update",
        message: "email extraction",
        field_changes: build_field_changes(task),
        source_email: @source_email
      )
    else
      @stats[:tasks_skipped] += 1
    end
  end

  def create_new_task(task_data, contact, company, email_date)
    attrs = {
      name: task_data[:name],
      description: task_data[:description],
      status: "incoming",
      due_date: task_data[:due_date],
      contact_id: contact&.id,
      company_id: company&.id
    }
    # Use email date as created_at/updated_at
    if email_date
      attrs[:created_at] = email_date
      attrs[:updated_at] = email_date
    end

    task = @user.tasks.create!(attrs)

    @stats[:tasks_new] += 1
    @logger.info "  DB: CREATE task id=#{task.id} name=#{task.name.truncate(40).inspect}"

    log_audit(
      record: task,
      action: "create",
      message: "email extraction",
      field_changes: build_field_changes(task),
      source_email: @source_email
    )
  end

  # Link the source email to the newly created contact if this contact is the sender
  def link_email_to_sender_contact(contact)
    return unless @source_email
    return if @source_email.contact_id.present?

    sender_email = @source_email.from_address&.dig("email")&.downcase
    return unless sender_email == contact.email

    @source_email.update!(contact: contact)
    @logger.info "  DB: LINK email_id=#{@source_email.id} contact_id=#{contact.id}"
  end
end
