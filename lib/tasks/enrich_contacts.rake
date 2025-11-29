namespace :import do
  desc "Enrich contacts using LLM extraction from EML files"
  task enrich_contacts: :environment do
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
    puts "Enriching contacts for user: #{user.email_address}"
    puts "Using Claude 3.5 Haiku for extraction"
    puts

    stats = { new: 0, enriched: 0, skipped: 0, errors: 0 }

    eml_files.each.with_index(1) do |eml_path, index|
      print "\rProcessing #{index}/#{eml_files.count}..."

      begin
        contacts = LlmContactExtractor.new(eml_path).extract

        contacts.each do |contact_data|
          contact = user.contacts.find_or_initialize_by(email: contact_data[:email])

          if contact.new_record?
            contact.assign_attributes(
              name: contact_data[:name],
              job_role: contact_data[:job_role],
              phone_numbers: contact_data[:phone_numbers]
            )
            contact.save!
            stats[:new] += 1
          else
            # Enrich existing contact with missing data
            updates = {}
            updates[:name] = contact_data[:name] if contact_data[:name].present? && contact.name.blank?
            updates[:job_role] = contact_data[:job_role] if contact_data[:job_role].present? && contact.job_role.blank?

            if contact_data[:phone_numbers].present?
              existing_phones = contact.phone_numbers || []
              new_phones = (existing_phones + contact_data[:phone_numbers]).uniq
              updates[:phone_numbers] = new_phones if new_phones != existing_phones
            end

            if updates.any?
              contact.update!(updates)
              stats[:enriched] += 1
            else
              stats[:skipped] += 1
            end
          end
        end

        # Small delay to avoid rate limiting
        sleep(0.1) if index % 10 == 0
      rescue => e
        stats[:errors] += 1
        # Uncomment for debugging:
        # puts "\nError processing #{eml_path}: #{e.message}"
      end
    end

    puts "\n\nEnrichment complete!"
    puts "  New contacts:      #{stats[:new]}"
    puts "  Enriched:          #{stats[:enriched]}"
    puts "  Skipped:           #{stats[:skipped]}"
    puts "  Errors:            #{stats[:errors]}"
    puts "  Total contacts:    #{user.contacts.count}"
  end
end
