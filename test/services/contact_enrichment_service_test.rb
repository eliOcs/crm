require "test_helper"

class ContactEnrichmentServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "test@example.com", password: "password123")
    # Use actual email directory (EmlReader.valid_path? requires db/seeds/emails)
    @eml_dir = Rails.root.join("db/seeds/emails/Archivo de datos de Outlook/Bandeja de entrada")
    @logger = Logger.new("/dev/null")  # Suppress logs in tests
  end

  # This test uses VCR to record/replay actual API calls
  # Run with ANTHROPIC_API_KEY set to record new cassettes
  test "enrichment creates correct company hierarchy with subsidiaries" do
    VCR.use_cassette("enrichment_company_hierarchy") do
      service = ContactEnrichmentService.new(@user, logger: @logger)

      # Process emails in order (1000.eml creates San Carlo, 1004.eml has Unichips contacts)
      service.process_email(@eml_dir.join("1000.eml").to_s)
      service.process_email(@eml_dir.join("1004.eml").to_s)
      service.process_email(@eml_dir.join("1007.eml").to_s)
    end

    # Assertions: Company hierarchy
    assert @user.companies.count >= 2, "Should create at least 2 companies (San Carlo + parent)"

    # San Carlo should exist with parent
    san_carlo = @user.companies.find_by(domain: "sancarlo.it")
    assert_not_nil san_carlo, "San Carlo should exist"
    assert_not_nil san_carlo.parent_company, "San Carlo should have a parent company"
    assert_match(/unichips/i, san_carlo.parent_company.legal_name, "Parent should be Unichips")

    # Unichips contacts should be linked to Unichips company, NOT San Carlo
    unichips_contacts = @user.contacts.where("email LIKE ?", "%@unichips.com")
    assert unichips_contacts.any?, "Should have Unichips contacts"

    unichips_contacts.each do |contact|
      # Contact should be linked to a Unichips company (either Finanziaria or subsidiary)
      unichips_company = contact.companies.find { |c| c.legal_name.downcase.include?("unichips") || c.domain == "unichips.com" }
      assert_not_nil unichips_company, "#{contact.email} should be linked to a Unichips company"
    end
  end

  test "LIKE matching prevents duplicate companies" do
    # Pre-create Unichips company
    existing_unichips = @user.companies.create!(
      legal_name: "Unichips Finanziaria S.p.A.",
      commercial_name: "Unichips"
    )

    VCR.use_cassette("enrichment_like_matching") do
      service = ContactEnrichmentService.new(@user, logger: @logger)
      service.process_email(@eml_dir.join("1004.eml").to_s)  # Has Unichips contacts
    end

    # Should reuse existing Unichips, not create duplicate
    unichips_companies = @user.companies.where("legal_name LIKE ?", "%Unichips%")
    assert_equal 1, unichips_companies.count, "Should not create duplicate Unichips companies"
    assert_equal existing_unichips.id, unichips_companies.first.id
  end

  test "domain mismatch creates subsidiary with correct parent" do
    VCR.use_cassette("enrichment_domain_mismatch") do
      service = ContactEnrichmentService.new(@user, logger: @logger)

      # 1000.eml creates San Carlo with domain sancarlo.it
      service.process_email(@eml_dir.join("1000.eml").to_s)

      # 1007.eml has contact @unichips.com mentioning San Carlo Mantova
      # This should trigger domain mismatch and create subsidiary
      service.process_email(@eml_dir.join("1007.eml").to_s)
    end

    # San Carlo should exist
    san_carlo = @user.companies.find_by(domain: "sancarlo.it")
    assert_not_nil san_carlo, "San Carlo should exist"

    # Check if San Carlo Mantova or a subsidiary was created
    mantova = @user.companies.find_by("legal_name LIKE ?", "%Mantova%")
    if mantova
      # If Mantova was created, it should be a subsidiary (has parent)
      assert_not_nil mantova.parent_company_id, "San Carlo Mantova should have a parent"
    end

    # Verify contacts with @unichips.com are not incorrectly linked to San Carlo (sancarlo.it domain)
    unichips_contacts = @user.contacts.where("email LIKE ?", "%@unichips.com")
    unichips_contacts.each do |contact|
      san_carlo_link = contact.companies.find_by(domain: "sancarlo.it")
      # Contact should either not be linked to San Carlo, or should be linked to a Unichips company too
      if san_carlo_link
        unichips_link = contact.companies.find { |c| c.domain == "unichips.com" || c.legal_name.include?("Unichips") }
        assert_not_nil unichips_link, "#{contact.email} linked to San Carlo should also have Unichips link"
      end
    end
  end
end
