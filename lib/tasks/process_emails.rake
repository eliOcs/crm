namespace :import do
  desc "Process emails: extract contacts, companies, and tasks using LLM"
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
    logger.info "Enriching contacts and companies for user: #{user.email_address}"
    logger.info "Using Claude 3.5 Haiku for extraction"
    logger.info ""

    service = EmailEnrichmentService.new(user, logger: logger)

    eml_files.each.with_index(1) do |eml_path, index|
      eml_relative = eml_path.sub("#{eml_dir}/", "")
      logger.info "[#{index}/#{eml_files.count}] #{eml_relative}"

      begin
        service.process_email(eml_path)
        sleep(0.1) if index % 10 == 0  # Small delay to avoid rate limiting
      rescue => e
        service.stats[:errors] += 1
        logger.error "  ERROR: #{e.message}"
        logger.debug "  #{e.backtrace.first}"
      end
    end

    stats = service.stats
    logger.info ""
    logger.info "Enrichment complete!"
    logger.info "  Contacts:"
    logger.info "    New:        #{stats[:contacts_new]}"
    logger.info "    Enriched:   #{stats[:contacts_enriched]}"
    logger.info "    Skipped:    #{stats[:contacts_skipped]}"
    logger.info "  Companies:"
    logger.info "    New:        #{stats[:companies_new]}"
    logger.info "    Logos:      #{stats[:logos_attached]}"
    logger.info "  Tasks:"
    logger.info "    New:        #{stats[:tasks_new]}"
    logger.info "    Updated:    #{stats[:tasks_updated]}"
    logger.info "    Skipped:    #{stats[:tasks_skipped]}"
    logger.info "  Errors:       #{stats[:errors]}"
    logger.info ""
    logger.info "  Total contacts:  #{user.contacts.count}"
    logger.info "  Total companies: #{user.companies.count}"
    logger.info "  Total tasks:     #{user.tasks.count}"
  end
end
