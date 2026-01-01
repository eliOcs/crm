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
    assert_equal "incoming", task.status, "New tasks should have incoming status"

    # Task should be linked to contact/company if sender was extracted
    if task.contact
      assert_not_nil task.contact.email, "Linked contact should have email"
    end

    # Audit log should be created with source email reference
    audit_log = task.audit_logs.find_by(action: "create")
    assert_not_nil audit_log, "Should create audit log for task"
    assert_not_nil audit_log.source_email, "Audit log should reference source email"
    assert_equal imported_email.id, audit_log.source_email.id
  end
end
