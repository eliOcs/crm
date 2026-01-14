namespace :import do
  desc "Import from PST files with two-phase processing: INBOX_PST (required), SENT_PST (optional)"
  task pst: :environment do
    $stdout.sync = true

    logger = Logger.new($stdout)
    logger.formatter = proc { |severity, time, _progname, msg| "[#{time.strftime('%H:%M:%S')}] #{msg}\n" }
    logger.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO

    unless ENV["ANTHROPIC_API_KEY"].present?
      puts "Error: ANTHROPIC_API_KEY environment variable is not set"
      exit 1
    end

    inbox_pst = ENV["INBOX_PST"]
    sent_pst = ENV["SENT_PST"]

    unless inbox_pst.present?
      puts "Error: INBOX_PST environment variable is required"
      puts "Usage: INBOX_PST=path/to/inbox.pst SENT_PST=path/to/sent.pst bin/rails import:pst"
      exit 1
    end

    unless File.exist?(inbox_pst)
      puts "Error: Inbox PST file not found: #{inbox_pst}"
      exit 1
    end

    if sent_pst.present? && !File.exist?(sent_pst)
      puts "Error: Sent PST file not found: #{sent_pst}"
      exit 1
    end

    print "Enter user email address: "
    user_email = $stdin.gets.chomp

    user = User.find_by(email_address: user_email)
    if user.nil?
      puts "Error: User not found with email '#{user_email}'"
      exit 1
    end

    # Create temp directory for extraction
    temp_dir = Rails.root.join("tmp", "pst_import_#{Time.now.to_i}")
    FileUtils.mkdir_p(temp_dir)

    logger.info "=" * 60
    logger.info "PST Import - Two Phase Processing"
    logger.info "=" * 60
    logger.info "User: #{user.email_address}"
    logger.info "Inbox PST: #{inbox_pst}"
    logger.info "Sent PST: #{sent_pst || '(not provided)'}"
    logger.info ""

    begin
      # Phase 0: Extract PST files
      logger.info "PHASE 0: Extracting PST files"
      logger.info "-" * 40

      inbox_dir = temp_dir.join("inbox")
      inbox_service = PstExtractionService.new(inbox_pst, output_dir: inbox_dir.to_s, logger: logger)
      inbox_stats = inbox_service.extract
      logger.info "  Inbox: #{inbox_stats[:eml_count]} emails extracted"

      sent_stats = { eml_count: 0 }
      if sent_pst.present?
        sent_dir = temp_dir.join("sent")
        sent_service = PstExtractionService.new(sent_pst, output_dir: sent_dir.to_s, logger: logger)
        sent_stats = sent_service.extract
        logger.info "  Sent: #{sent_stats[:eml_count]} emails extracted"
      end

      # Get all EML files sorted by date
      eml_files = collect_and_sort_eml_files(temp_dir, logger)

      # Apply limit if specified
      total_available = eml_files.count
      if ENV["LIMIT"].present?
        limit = ENV["LIMIT"].to_i
        eml_files = eml_files.first(limit)
        logger.info "  Total: #{total_available} emails (limited to #{limit})"
      else
        logger.info "  Total: #{eml_files.count} emails"
      end
      logger.info ""

      # Phase 1: Import all emails (no enrichment)
      logger.info "PHASE 1: Importing emails to database (no enrichment)"
      logger.info "-" * 40

      import_service = EmailImportService.new(user, logger: logger)

      eml_files.each.with_index(1) do |eml_path, index|
        logger.info "[#{index}/#{eml_files.count}] #{File.basename(eml_path)}"
        import_service.import_from_eml(eml_path)
      end

      logger.info ""
      logger.info "  Imported: #{import_service.stats[:imported]}"
      logger.info "  Skipped:  #{import_service.stats[:skipped]}"
      logger.info "  Errors:   #{import_service.stats[:errors]}"
      logger.info ""

      # Phase 2: Enrich in chronological order
      logger.info "PHASE 2: Enriching emails chronologically"
      logger.info "-" * 40

      total_emails = user.emails.count
      enrichment_service = EmailEnrichmentService.new(user, logger: logger)

      # Use find_each with cursor for memory-efficient chronological iteration
      index = 0
      user.emails.find_each(batch_size: 50, cursor: [ :sent_at, :id ]) do |email|
        index += 1
        logger.info "[#{index}/#{total_emails}] #{email.subject&.truncate(50)}"
        enrichment_service.process_email_record(email)
      end

      enrich_stats = enrichment_service.stats
      logger.info ""
      logger.info "=" * 60
      logger.info "Import Complete!"
      logger.info "=" * 60
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
      logger.info ""
      logger.info "  Total emails:    #{user.emails.count}"
      logger.info "  Total contacts:  #{user.contacts.count}"
      logger.info "  Total companies: #{user.companies.count}"
      logger.info "  Total tasks:     #{user.tasks.count}"

    ensure
      # Cleanup temp directory
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end
  end

  # Helper method for PST import task
  def collect_and_sort_eml_files(temp_dir, logger)
    inbox_dir = temp_dir.join("inbox")
    sent_dir = temp_dir.join("sent")

    inbox_files = Dir.exist?(inbox_dir) ? Dir.glob(inbox_dir.join("**/*.eml")) : []
    sent_files = Dir.exist?(sent_dir) ? Dir.glob(sent_dir.join("**/*.eml")) : []

    all_files = inbox_files + sent_files

    # Sort by date extracted from email headers
    files_with_dates = all_files.map do |file|
      date = extract_email_date(file)
      [ file, date ]
    end

    files_with_dates
      .sort_by { |_file, date| date || Time.at(0) }
      .map(&:first)
  end

  def extract_email_date(eml_path)
    content = File.read(eml_path, 8192, encoding: "binary") rescue nil
    return nil unless content

    if content =~ /^Date:\s*(.+)$/i
      begin
        Time.parse($1.strip)
      rescue ArgumentError
        nil
      end
    end
  end

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

    # Use unified service for import + enrichment
    processing_service = EmailProcessingService.new(user, logger: logger)
    import_service = EmailImportService.new(user, logger: logger)  # For stats tracking
    enrichment_service = EmailEnrichmentService.new(user, logger: logger)  # For stats tracking

    eml_files.each.with_index(1) do |eml_path, index|
      eml_relative = eml_path.sub("#{eml_dir}/", "")
      logger.info "[#{index}/#{eml_files.count}] #{eml_relative}"

      begin
        # Import and enrich in a single call (sync enrichment for correct ordering)
        result = processing_service.process_eml(eml_path, enrich: :sync)

        if result.created?
          import_service.stats[:imported] += 1
        elsif result.skipped?
          import_service.stats[:skipped] += 1
        end
      rescue => e
        import_service.stats[:errors] += 1
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
