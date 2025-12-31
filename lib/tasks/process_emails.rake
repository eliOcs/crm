namespace :import do
  desc "Process emails: import to database and extract contacts, companies, and tasks using LLM"
  task process_emails: :environment do
    # Ensure output is flushed immediately for real-time logging
    $stdout.sync = true

    # Configure logger to output to STDOUT for rake task visibility
    logger = Logger.new($stdout)
    logger.formatter = proc { |severity, time, _progname, msg| "[#{time.strftime('%H:%M:%S')}] #{msg}\n" }
    logger.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO

    # Enable ActiveRecord SQL logging in DEBUG mode
    if ENV["DEBUG"]
      ActiveRecord::Base.logger = Logger.new($stdout)
      ActiveRecord::Base.logger.level = Logger::DEBUG
    end

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

    # Sort files numerically by filename (assumes numeric filenames like 59.eml, 60.eml)
    eml_files = eml_files.sort_by { |path| File.basename(path, ".eml").to_i }

    # Optional limit for testing (applied after sorting)
    if ENV["LIMIT"].present?
      limit = ENV["LIMIT"].to_i
      eml_files = eml_files.first(limit)
      logger.info "Found #{Dir.glob(eml_dir.join('**/*.eml')).count} EML files (limited to #{limit})"
    else
      logger.info "Found #{eml_files.count} EML files"
    end
    logger.info "Processing emails for user: #{user.email_address}"
    logger.info "Using Claude 3.5 Haiku for extraction"
    logger.info ""

    import_service = EmailImportService.new(user, logger: logger)
    enrichment_service = EmailEnrichmentService.new(user, logger: logger)

    eml_files.each.with_index(1) do |eml_path, index|
      eml_relative = eml_path.sub("#{eml_dir}/", "")
      logger.info "[#{index}/#{eml_files.count}] #{eml_relative}"

      begin
        # Step 1: Import email to database
        db_email = import_service.import_from_eml(eml_path)

        # Step 2: Run LLM enrichment (creates contacts, companies, tasks)
        # Process even if email was skipped (duplicate) - contacts may still need enrichment
        enrichment_service.process_email(eml_path)

        sleep(0.1) if index % 10 == 0  # Small delay to avoid rate limiting
      rescue => e
        enrichment_service.stats[:errors] += 1
        logger.error "  ERROR: #{e.message}"
        logger.debug "  #{e.backtrace.first}"
      end
    end

    import_stats = import_service.stats
    enrich_stats = enrichment_service.stats

    logger.info ""
    logger.info "Processing complete!"
    logger.info "  Emails:"
    logger.info "    Imported:   #{import_stats[:imported]}"
    logger.info "    Skipped:    #{import_stats[:skipped]}"
    logger.info "    Errors:     #{import_stats[:errors]}"
    logger.info "  Contacts:"
    logger.info "    New:        #{enrich_stats[:contacts_new]}"
    logger.info "    Enriched:   #{enrich_stats[:contacts_enriched]}"
    logger.info "    Skipped:    #{enrich_stats[:contacts_skipped]}"
    logger.info "  Companies:"
    logger.info "    New:        #{enrich_stats[:companies_new]}"
    logger.info "    Logos:      #{enrich_stats[:logos_attached]}"
    logger.info "  Tasks:"
    logger.info "    New:        #{enrich_stats[:tasks_new]}"
    logger.info "    Updated:    #{enrich_stats[:tasks_updated]}"
    logger.info "    Skipped:    #{enrich_stats[:tasks_skipped]}"
    logger.info "  Errors:       #{enrich_stats[:errors]}"
    logger.info ""
    logger.info "  Total emails:    #{user.emails.count}"
    logger.info "  Total contacts:  #{user.contacts.count}"
    logger.info "  Total companies: #{user.companies.count}"
    logger.info "  Total tasks:     #{user.tasks.count}"
  end
end
