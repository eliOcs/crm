require "test_helper"

class ContactEnrichmentServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "test@example.com", password: "password123")
    @eml_dir = Rails.root.join("db/seeds/emails/Archivo de datos de Outlook/Bandeja de entrada")
    @logger = Logger.new("/dev/null")  # Suppress logs in tests
  end

  test "domain matching prevents duplicate companies" do
    # Pre-create company with domain
    existing_company = @user.companies.create!(
      legal_name: "Existing Company S.A.",
      domain: "itpsa.com"
    )

    VCR.use_cassette("enrichment_domain_matching") do
      service = ContactEnrichmentService.new(@user, logger: @logger)
      service.process_email(@eml_dir.join("11.eml").to_s)  # Has ITPSA contacts
    end

    # Should reuse existing company by domain, not create duplicate
    itpsa_companies = @user.companies.where(domain: "itpsa.com")
    assert_equal 1, itpsa_companies.count, "Should not create duplicate companies with same domain"
    assert_equal existing_company.id, itpsa_companies.first.id
  end

  test "contacts are linked to companies by email domain" do
    VCR.use_cassette("enrichment_contact_domain_linking") do
      service = ContactEnrichmentService.new(@user, logger: @logger)
      service.process_email(@eml_dir.join("Webmail/1.eml").to_s)
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
end
