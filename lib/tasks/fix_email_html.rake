namespace :import do
  desc "Fix email HTML by re-reading from original EML files (restores stripped src attributes)"
  task fix_email_html: :environment do
    emails_dir = Pathname.new(ENV.fetch("EMAILS_DIR", Rails.root.join("db/seeds/emails")))

    updated = 0
    skipped = 0
    errors = 0

    Email.find_each do |email|
      next if email.source_path.blank?

      path = emails_dir.join(email.source_path)
      unless path.exist?
        puts "SKIP: #{email.id} - source file not found: #{email.source_path}"
        skipped += 1
        next
      end

      begin
        reader = EmlReader.new(path)
        data = reader.read

        if data && data[:html_body].present?
          email.update!(body_html: data[:html_body])
          updated += 1
          print "."
        else
          skipped += 1
        end
      rescue => e
        puts "\nERROR: #{email.id} - #{e.message}"
        errors += 1
      end
    end

    puts "\n\nDone!"
    puts "  Updated: #{updated}"
    puts "  Skipped: #{skipped}"
    puts "  Errors:  #{errors}"
  end
end
