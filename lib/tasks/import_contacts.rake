namespace :import do
  desc "Import contacts from EML files in db/seeds/emails"
  task contacts: :environment do
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
    puts "Importing contacts for user: #{user.email_address}"
    puts

    imported_count = 0
    skipped_count = 0
    error_count = 0

    eml_files.each.with_index(1) do |eml_path, index|
      print "\rProcessing #{index}/#{eml_files.count}..."

      begin
        contacts = EmlContactExtractor.new(eml_path).extract

        contacts.each do |contact_data|
          contact = user.contacts.find_or_initialize_by(email: contact_data[:email])

          if contact.new_record?
            contact.name = contact_data[:name]
            contact.save!
            imported_count += 1
          elsif contact_data[:name].present? && contact.name.blank?
            contact.update!(name: contact_data[:name])
          else
            skipped_count += 1
          end
        end
      rescue => e
        error_count += 1
        # Uncomment for debugging:
        # puts "\nError processing #{eml_path}: #{e.message}"
      end
    end

    puts "\n\nImport complete!"
    puts "  Imported: #{imported_count} new contacts"
    puts "  Skipped:  #{skipped_count} existing contacts"
    puts "  Errors:   #{error_count} files"
    puts "  Total contacts for user: #{user.contacts.count}"
  end
end
