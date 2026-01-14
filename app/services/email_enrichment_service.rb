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
      llm_skipped: 0,
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

    email_date = email_data[:date] || Time.current

    # Check if email has meaningful content for LLM processing
    if @source_email && !@source_email.has_meaningful_content?
      @stats[:llm_skipped] += 1
      @logger.info "  Skipping LLM (no meaningful content), extracting from headers only"
      extract_contacts_from_headers(@source_email)
      return
    end

    # Extract contacts and companies
    extractor = LlmEmailExtractor.new(eml_path)
    perform_extraction(extractor, email_date)
  end

  # Process an Email record directly (for Graph-imported emails)
  def process_email_record(email)
    @source_email = email
    email_date = email.sent_at || Time.current

    # Check if email has meaningful content for LLM processing
    unless email.has_meaningful_content?
      @stats[:llm_skipped] += 1
      @logger.info "  Skipping LLM (no meaningful content), extracting from headers only"
      extract_contacts_from_headers(email)
      return
    end

    # Extract contacts and companies using the Email record
    extractor = LlmEmailExtractor.from_email(email)
    perform_extraction(extractor, email_date)
  end

  private

  # Extract contacts from email headers without LLM
  # Used for emails with no meaningful content (calendar notifications, etc.)
  def extract_contacts_from_headers(email)
    email.header_addresses.each do |address|
      email_addr = address["email"]&.strip&.downcase
      next unless email_addr.present?

      contact = @user.contacts.find_or_initialize_by(email: email_addr)

      if contact.new_record?
        # Set name from header if available
        contact.name = address["name"]&.strip.presence
        contact.save!
        @stats[:contacts_new] += 1
        @logger.info "  DB: CREATE contact id=#{contact.id} email=#{contact.email} (from headers)"

        log_audit(
          record: contact,
          action: "create",
          message: "email headers",
          field_changes: build_field_changes(contact),
          source_email: email
        )

        # Link email to sender contact
        link_email_to_sender_contact(contact)

        # Link to existing company by domain
        link_contact_to_company_by_domain(contact)
      else
        @stats[:contacts_skipped] += 1
      end
    end
  end

  # Link a contact to an existing company based on email domain
  def link_contact_to_company_by_domain(contact)
    domain = contact.email.split("@").last&.downcase
    return unless domain.present?

    company = @user.companies.find_by(domain: domain)
    return unless company
    return if contact.companies.include?(company)

    contact.companies << company
    @logger.info "  DB: LINK contact_id=#{contact.id} company_id=#{company.id}"

    log_audit(
      record: contact,
      action: "link",
      message: "company link by domain",
      field_changes: { "company_id" => { "from" => nil, "to" => company.id } },
      source_email: @source_email
    )
  end

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
    # Only pass tasks related to contacts/companies in this email
    existing_tasks = find_related_tasks(contact_map, domain_map)
    tasks = extractor.extract_tasks(
      email_date: email_date,
      existing_tasks: existing_tasks,
      locale: @user.locale,
      user_email: @user.email_address
    )
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
    # Collect all contacts from this email
    contacts = contact_map.values.compact.uniq

    # Find associated company from sender or first contact with a company
    company = nil
    if task_data[:sender_email].present?
      domain = task_data[:sender_email].split("@").last&.downcase
      company = domain_map[domain] || @user.companies.find_by(domain: domain) if domain.present?
    end
    company ||= contacts.flat_map(&:companies).first

    if task_data[:id].present?
      update_existing_task(task_data, contacts, company, email_date)
    else
      create_new_task(task_data, contacts, company, email_date)
    end
  end

  def update_existing_task(task_data, contacts, company, email_date)
    task = @user.tasks.find_by(id: task_data[:id])

    unless task
      @logger.warn "  Task id=#{task_data[:id]} not found, creating new"
      create_new_task(task_data.merge(id: nil), contacts, company, email_date)
      return
    end

    updates = {}

    # Replace description with latest, most accurate information
    # (audit log preserves history of changes)
    if task_data[:description].present?
      updates[:description] = task_data[:description]
    end

    # Update due date if new one is more urgent
    if task_data[:due_date].present?
      if task.due_date.nil? || task_data[:due_date] < task.due_date
        updates[:due_date] = task_data[:due_date]
      end
    end

    # Link to company if not already linked
    updates[:company_id] = company.id if company && task.company_id.nil?

    # Update status if appropriate
    if task_data[:status].present? && should_update_status?(task, task_data[:status])
      updates[:status] = task_data[:status]
    end

    # Add any new contacts not already linked
    new_contacts = Array(contacts) - task.contacts.to_a
    task.contacts << new_contacts if new_contacts.any?

    if updates.any? || new_contacts.any?
      # Use email date as updated_at
      updates[:updated_at] = email_date if email_date

      task.update!(updates) if updates.any?
      @stats[:tasks_updated] += 1
      @logger.info "  DB: UPDATE task id=#{task.id} #{(updates.keys + (new_contacts.any? ? [ :contacts ] : [])).join(', ')}"

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

  def create_new_task(task_data, contacts, company, email_date)
    attrs = {
      name: task_data[:name],
      description: task_data[:description],
      status: task_data[:status] || "incoming",
      due_date: task_data[:due_date],
      company_id: company&.id
    }
    # Use email date as created_at/updated_at
    if email_date
      attrs[:created_at] = email_date
      attrs[:updated_at] = email_date
    end

    task = @user.tasks.create!(attrs)
    task.contacts << contacts if contacts.any?

    @stats[:tasks_new] += 1
    @logger.info "  DB: CREATE task id=#{task.id} name=#{task.name.truncate(40).inspect} contacts=#{contacts.count}"

    log_audit(
      record: task,
      action: "create",
      message: "email extraction",
      field_changes: build_field_changes(task),
      source_email: @source_email
    )
  end

  # Determine if status should be updated based on current and new status
  # - Always allow completion (done)
  # - Allow first triage (from incoming)
  # - Allow blocking a todo task
  def should_update_status?(task, new_status)
    return true if new_status == "done"
    return true if task.status == "incoming"
    return true if task.status == "todo" && new_status == "blocked"
    false
  end

  # Find active tasks related to contacts or companies in this email
  def find_related_tasks(contact_map, domain_map)
    contact_ids = contact_map.values.compact.map(&:id)
    company_ids = domain_map.values.compact.map(&:id)

    return [] if contact_ids.empty? && company_ids.empty?

    # Tasks linked to any of these contacts OR companies
    tasks = @user.tasks.active.includes(:contacts, :company).distinct

    conditions = []
    conditions << "contacts_tasks.contact_id IN (?)" if contact_ids.any?
    conditions << "tasks.company_id IN (?)" if company_ids.any?

    tasks = tasks.left_joins(:contacts)
                 .where(conditions.join(" OR "), *[ contact_ids, company_ids ].reject(&:empty?))
                 .to_a

    @logger.info "  Found #{tasks.count} related tasks for #{contact_ids.count} contacts, #{company_ids.count} companies"
    tasks
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
