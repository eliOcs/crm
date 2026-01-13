require "test_helper"

class EmailEnrichmentServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "test@example.com", password: "password123")
    @logger = Logger.new("/dev/null")  # Suppress logs in tests
  end

  test "domain matching prevents duplicate companies" do
    # Pre-create company with domain
    existing_company = @user.companies.create!(
      legal_name: "Existing Company S.A.",
      domain: "itpsa.com"
    )

    VCR.use_cassette("enrichment_domain_matching") do
      service = EmailEnrichmentService.new(@user, logger: @logger)
      service.process_email(file_fixture("emails/itpsa_11.eml").to_s)
    end

    # Should reuse existing company by domain, not create duplicate
    itpsa_companies = @user.companies.where(domain: "itpsa.com")
    assert_equal 1, itpsa_companies.count, "Should not create duplicate companies with same domain"
    assert_equal existing_company.id, itpsa_companies.first.id
  end

  test "contacts are linked to companies by email domain" do
    VCR.use_cassette("enrichment_contact_domain_linking") do
      service = EmailEnrichmentService.new(@user, logger: @logger)
      service.process_email(file_fixture("emails/webmail_1.eml").to_s)
    end

    # Contacts with @itpsa.com should be linked to ITPSA company
    itpsa = @user.companies.find_by(domain: "itpsa.com")
    assert_not_nil itpsa, "Should create ITPSA company"

    itpsa_contacts = @user.contacts.where("email LIKE ?", "%@itpsa.com")
    assert itpsa_contacts.count >= 1, "Should have ITPSA contacts"

    itpsa_contacts.each do |contact|
      assert contact.companies.include?(itpsa), "#{contact.email} should be linked to ITPSA"
    end
  end

  test "name matching prevents duplicate companies without domain" do
    VCR.use_cassette("enrichment_name_matching") do
      service = EmailEnrichmentService.new(@user, logger: @logger)

      # Process first email - should create Belagrolex company
      service.process_email(file_fixture("emails/belagrolex_1.eml").to_s)

      # Process second email - should find existing Belagrolex by name, not create duplicate
      service.process_email(file_fixture("emails/belagrolex_2.eml").to_s)
    end

    # Should have only one Belagrolex company (matched by name since no domain)
    belagrolex_companies = @user.companies.where(legal_name: "Belagrolex")
                                          .or(@user.companies.where(commercial_name: "Belagrolex"))
    assert_equal 1, belagrolex_companies.count, "Should not create duplicate companies - name matching should work"
  end

  test "creates company with commercial_name as legal_name fallback" do
    # Pre-create ITPSA so it's found and doesn't trigger the error
    @user.companies.create!(legal_name: "Industrial Técnica Pecuaria, S.A.", domain: "itpsa.com")

    VCR.use_cassette("enrichment_commercial_name_fallback") do
      service = EmailEnrichmentService.new(@user, logger: @logger)
      # This email mentions "Idealsa" which LLM extracts with only commercial_name
      service.process_email(file_fixture("emails/idealsa_47.eml").to_s)
    end

    # Should create company using commercial_name as legal_name
    idealsa = @user.companies.find_by("legal_name LIKE ? OR commercial_name LIKE ?", "%Idealsa%", "%Idealsa%")
    assert_not_nil idealsa, "Should create Idealsa company"
    assert_not_nil idealsa.legal_name, "Company must have legal_name (required field)"
  end

  test "skips LLM for calendar notification emails and extracts contacts from headers" do
    eml_path = file_fixture("emails/itpsa_11.eml").to_s

    # First import the email to the database
    import_service = EmailImportService.new(@user, logger: @logger)
    imported_email = import_service.import_from_eml(eml_path)

    # Verify the email is detected as no meaningful content
    assert_not imported_email.has_meaningful_content?, "Empty email should not have meaningful content"

    # Run enrichment - should NOT call LLM
    service = EmailEnrichmentService.new(@user, logger: @logger)
    service.process_email(eml_path)

    # Should have created contacts from headers (From + To)
    assert_equal 1, service.stats[:llm_skipped], "Should skip LLM"
    assert @user.contacts.exists?(email: "moparaira@itpsa.com"), "Should create contact from From header"
    assert @user.contacts.exists?(email: "mmoreno@itpsa.com"), "Should create contact from To header"

    # Check contact has name from header
    monica = @user.contacts.find_by(email: "moparaira@itpsa.com")
    assert_equal "Monica Paraira", monica.name
  end

  test "calendar notification contact is linked to existing company by domain" do
    # Pre-create ITPSA company
    itpsa = @user.companies.create!(legal_name: "ITPSA S.A.", domain: "itpsa.com")

    eml_path = file_fixture("emails/itpsa_11.eml").to_s
    import_service = EmailImportService.new(@user, logger: @logger)
    import_service.import_from_eml(eml_path)

    service = EmailEnrichmentService.new(@user, logger: @logger)
    service.process_email(eml_path)

    # Contacts should be linked to ITPSA
    monica = @user.contacts.find_by(email: "moparaira@itpsa.com")
    assert monica.companies.include?(itpsa), "Contact should be linked to ITPSA by domain"
  end

  test "extracts tasks from emails requesting action" do
    eml_path = file_fixture("emails/webmail_1.eml").to_s

    # First import the email to the database
    import_service = EmailImportService.new(@user, logger: @logger)
    imported_email = import_service.import_from_eml(eml_path)

    VCR.use_cassette("enrichment_task_extraction") do
      service = EmailEnrichmentService.new(@user, logger: @logger)
      service.process_email(eml_path)
    end

    # Should have created at least one task
    assert @user.tasks.count >= 1, "Should extract tasks from email"

    task = @user.tasks.first
    assert_not_nil task.name, "Task should have a name"
    assert_includes LlmEmailExtractor::EXTRACTABLE_STATUSES, task.status,
                    "Task status should be one of: #{LlmEmailExtractor::EXTRACTABLE_STATUSES.join(', ')}"

    # Task should be linked to contacts if sender was extracted
    if task.contacts.any?
      assert_not_nil task.contacts.first.email, "Linked contact should have email"
    end

    # Audit log should be created with source email reference
    audit_log = task.audit_logs.find_by(action: "create")
    assert_not_nil audit_log, "Should create audit log for task"
    assert_not_nil audit_log.source_email, "Audit log should reference source email"
    assert_equal imported_email.id, audit_log.source_email.id
  end

  test "task description is replaced, not appended, on update" do
    # Create initial task with description
    task = @user.tasks.create!(
      name: "Test Task",
      description: "Original description from first email",
      status: "incoming"
    )

    # Simulate enrichment service updating an existing task
    service = EmailEnrichmentService.new(@user, logger: @logger)

    # Call the private method directly to test the replacement behavior
    task_data = {
      id: task.id,
      description: "Updated description with latest info"
    }

    service.send(:update_existing_task, task_data, nil, nil, Time.current)

    task.reload
    description_text = task.description.to_plain_text

    # Description should be replaced, not appended
    assert_equal "Updated description with latest info", description_text
    assert_not_includes description_text, "Original description"
    assert_not_includes description_text, "---"  # No separator from old appending behavior
  end

  # === Multiple Contacts Tests ===

  test "tasks are linked to multiple contacts from email" do
    # Create contacts that would appear in an email
    contact1 = @user.contacts.create!(email: "sender@example.com", name: "Sender")
    contact2 = @user.contacts.create!(email: "recipient@example.com", name: "Recipient")
    company = @user.companies.create!(legal_name: "Test Company", domain: "example.com")

    service = EmailEnrichmentService.new(@user, logger: @logger)

    # Build contact_map as enrichment would
    contact_map = {
      "sender@example.com" => contact1,
      "recipient@example.com" => contact2
    }

    task_data = {
      name: "Test task",
      status: "todo",
      sender_email: "sender@example.com"
    }

    # Call create_new_task with multiple contacts
    service.send(:create_new_task, task_data, contact_map.values, company, Time.current)

    task = @user.tasks.last
    assert_equal 2, task.contacts.count, "Task should be linked to both contacts"
    assert_includes task.contacts, contact1
    assert_includes task.contacts, contact2
  end

  test "updating task adds new contacts without removing existing" do
    # Create initial task with one contact
    contact1 = @user.contacts.create!(email: "first@example.com", name: "First")
    task = @user.tasks.create!(name: "Test Task", status: "incoming")
    task.contacts << contact1

    # Create another contact to add
    contact2 = @user.contacts.create!(email: "second@example.com", name: "Second")

    service = EmailEnrichmentService.new(@user, logger: @logger)
    task_data = { id: task.id, description: "Updated" }

    service.send(:update_existing_task, task_data, [ contact2 ], nil, Time.current)

    task.reload
    assert_equal 2, task.contacts.count, "Task should have both contacts"
    assert_includes task.contacts, contact1, "Original contact should still be linked"
    assert_includes task.contacts, contact2, "New contact should be added"
  end

  # === Related Tasks Filtering Tests ===

  test "find_related_tasks returns only tasks linked to given contacts" do
    contact1 = @user.contacts.create!(email: "related@example.com", name: "Related")
    contact2 = @user.contacts.create!(email: "other@example.com", name: "Other")

    # Create related task
    related_task = @user.tasks.create!(name: "Related task", status: "todo")
    related_task.contacts << contact1

    # Create unrelated task
    unrelated_task = @user.tasks.create!(name: "Unrelated task", status: "todo")
    unrelated_task.contacts << contact2

    service = EmailEnrichmentService.new(@user, logger: @logger)
    contact_map = { "related@example.com" => contact1 }
    domain_map = {}

    tasks = service.send(:find_related_tasks, contact_map, domain_map)

    assert_includes tasks, related_task, "Should include task linked to contact"
    assert_not_includes tasks, unrelated_task, "Should not include task linked to other contact"
  end

  test "find_related_tasks returns tasks linked to given companies" do
    company1 = @user.companies.create!(legal_name: "Related Co", domain: "related.com")
    company2 = @user.companies.create!(legal_name: "Other Co", domain: "other.com")

    related_task = @user.tasks.create!(name: "Related task", status: "todo", company: company1)
    unrelated_task = @user.tasks.create!(name: "Unrelated task", status: "todo", company: company2)

    service = EmailEnrichmentService.new(@user, logger: @logger)
    contact_map = {}
    domain_map = { "related.com" => company1 }

    tasks = service.send(:find_related_tasks, contact_map, domain_map)

    assert_includes tasks, related_task, "Should include task linked to company"
    assert_not_includes tasks, unrelated_task, "Should not include task linked to other company"
  end

  test "find_related_tasks returns empty array when no contacts or companies" do
    @user.tasks.create!(name: "Some task", status: "todo")

    service = EmailEnrichmentService.new(@user, logger: @logger)
    tasks = service.send(:find_related_tasks, {}, {})

    assert_empty tasks, "Should return empty when no contacts or companies"
  end

  # === Status Update Tests ===

  test "should_update_status allows done from any status" do
    service = EmailEnrichmentService.new(@user, logger: @logger)

    %w[incoming todo in_progress blocked].each do |status|
      task = @user.tasks.create!(name: "Task", status: status)
      assert service.send(:should_update_status?, task, "done"),
             "Should allow updating to done from #{status}"
    end
  end

  test "should_update_status allows any status from incoming" do
    service = EmailEnrichmentService.new(@user, logger: @logger)
    task = @user.tasks.create!(name: "Task", status: "incoming")

    %w[todo blocked done].each do |new_status|
      assert service.send(:should_update_status?, task, new_status),
             "Should allow updating from incoming to #{new_status}"
    end
  end

  test "should_update_status allows blocked from todo" do
    service = EmailEnrichmentService.new(@user, logger: @logger)
    task = @user.tasks.create!(name: "Task", status: "todo")

    assert service.send(:should_update_status?, task, "blocked"),
           "Should allow updating from todo to blocked"
  end

  test "should_update_status rejects regression from in_progress to todo" do
    service = EmailEnrichmentService.new(@user, logger: @logger)
    task = @user.tasks.create!(name: "Task", status: "in_progress")

    assert_not service.send(:should_update_status?, task, "todo"),
               "Should not allow updating from in_progress to todo"
  end

  test "create_new_task uses extracted status" do
    service = EmailEnrichmentService.new(@user, logger: @logger)

    task_data = { name: "Urgent task", status: "todo" }
    service.send(:create_new_task, task_data, [], nil, Time.current)

    task = @user.tasks.last
    assert_equal "todo", task.status, "Should use extracted status, not default"
  end

  test "create_new_task defaults to incoming when no status" do
    service = EmailEnrichmentService.new(@user, logger: @logger)

    task_data = { name: "Task without status" }
    service.send(:create_new_task, task_data, [], nil, Time.current)

    task = @user.tasks.last
    assert_equal "incoming", task.status, "Should default to incoming"
  end
end
