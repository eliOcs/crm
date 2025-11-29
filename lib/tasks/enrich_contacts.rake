namespace :import do
  desc "Enrich contacts and extract companies using LLM from EML files"
  task enrich_contacts: :environment do
    extension_for = ->(content_type) {
      case content_type
      when "image/jpeg" then ".jpg"
      when "image/png" then ".png"
      when "image/gif" then ".gif"
      when "image/webp" then ".webp"
      else ".jpg"
      end
    }

    unless ENV["ANTHROPIC_API_KEY"].present?
      puts "Error: ANTHROPIC_API_KEY environment variable is not set"
      exit 1
    end

    print "Enter user email address: "
    email = $stdin.gets.chomp

    user = User.find_by(email_address: email)
    if user.nil?
      puts "Error: User not found with email '#{email}'"
      exit 1
    end

    eml_dir = Rails.root.join("db/seeds/emails")
    unless Dir.exist?(eml_dir)
      puts "Error: EML directory not found at #{eml_dir}"
      exit 1
    end

    eml_files = Dir.glob(eml_dir.join("**/*.eml"))
    if eml_files.empty?
      puts "Error: No EML files found in #{eml_dir}"
      exit 1
    end

    puts "Found #{eml_files.count} EML files"
    puts "Enriching contacts and companies for user: #{user.email_address}"
    puts "Using Claude 3.5 Haiku for extraction"
    puts

    stats = {
      contacts_new: 0,
      contacts_enriched: 0,
      contacts_skipped: 0,
      companies_new: 0,
      companies_enriched: 0,
      logos_attached: 0,
      errors: 0
    }

    # Helper to find company by domain or name
    find_company_by_domain = ->(website) {
      return nil unless website.present?
      domain = Company.normalize_domain(website)
      return nil unless domain.present?
      user.companies.find_by(domain: domain)
    }

    find_company_by_name = ->(name) {
      return nil unless name.present?
      user.companies.find_by("LOWER(name) = ?", name.downcase)
    }

    eml_files.each.with_index(1) do |eml_path, index|
      print "\rProcessing #{index}/#{eml_files.count}..."

      begin
        result = LlmEmailExtractor.new(eml_path).extract

        # Process companies first so we can link contacts to them
        company_map = {}
        result[:companies].each do |company_data|
          # Find by domain first, then by name
          company = find_company_by_domain.call(company_data[:website])
          company ||= find_company_by_name.call(company_data[:name])
          company ||= user.companies.new(name: company_data[:name])

          was_new = company.new_record?
          updates_made = false

          # Fill in missing website (only for new companies or those without)
          if company_data[:website].present? && company.website.blank?
            company.website = company_data[:website]
            updates_made = true
          end

          if was_new || updates_made
            company.save!
            if was_new
              stats[:companies_new] += 1
            else
              stats[:companies_enriched] += 1
            end
          end

          # Attach logo if identified and not already attached
          if company_data[:logo_content_id].present? && !company.logo.attached?
            image_data = result[:image_data][company_data[:logo_content_id]]
            if image_data
              company.logo.attach(
                io: StringIO.new(image_data[:raw_data]),
                filename: "logo#{extension_for.call(image_data[:content_type])}",
                content_type: image_data[:content_type]
              )
              stats[:logos_attached] += 1
            end
          end

          company_map[company_data[:name]] = company
        end

        # Process contacts
        result[:contacts].each do |contact_data|
          contact = user.contacts.find_or_initialize_by(email: contact_data[:email])

          was_new = contact.new_record?
          updates = {}

          # Fill in missing name
          if contact_data[:name].present? && contact.name.blank?
            updates[:name] = contact_data[:name]
          end

          # Fill in missing job role
          if contact_data[:job_role].present? && contact.job_role.blank?
            updates[:job_role] = contact_data[:job_role]
          end

          # Merge phone numbers
          if contact_data[:phone_numbers].present?
            existing_phones = contact.phone_numbers || []
            new_phones = (existing_phones + contact_data[:phone_numbers]).uniq
            updates[:phone_numbers] = new_phones if new_phones != existing_phones
          end

          # Link to company if not already linked
          if contact.company.nil? && contact_data[:company_name].present?
            # First check company_map from current email
            company = company_map[contact_data[:company_name]]
            # Then try to find existing company in database by name
            company ||= find_company_by_name.call(contact_data[:company_name])

            updates[:company] = company if company
          end

          if was_new
            contact.assign_attributes(updates)
            contact.save!
            stats[:contacts_new] += 1
          elsif updates.any?
            contact.update!(updates)
            stats[:contacts_enriched] += 1
          else
            stats[:contacts_skipped] += 1
          end
        end

        # Small delay to avoid rate limiting
        sleep(0.1) if index % 10 == 0
      rescue => e
        stats[:errors] += 1
        # Uncomment for debugging:
        # puts "\nError processing #{eml_path}: #{e.message}"
        # puts e.backtrace.first(5).join("\n")
      end
    end

    puts "\n\nEnrichment complete!"
    puts "  Contacts:"
    puts "    New:        #{stats[:contacts_new]}"
    puts "    Enriched:   #{stats[:contacts_enriched]}"
    puts "    Skipped:    #{stats[:contacts_skipped]}"
    puts "  Companies:"
    puts "    New:        #{stats[:companies_new]}"
    puts "    Enriched:   #{stats[:companies_enriched]}"
    puts "    Logos:      #{stats[:logos_attached]}"
    puts "  Errors:       #{stats[:errors]}"
    puts
    puts "  Total contacts:  #{user.contacts.count}"
    puts "  Total companies: #{user.companies.count}"
  end
end
