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
