namespace :import do
  desc "Enrich contacts and extract companies using LLM from EML files"
  task enrich_contacts: :environment do
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

    extension_for = ->(content_type) {
      case content_type
      when "image/jpeg" then ".jpg"
      when "image/png" then ".png"
      when "image/gif" then ".gif"
      when "image/webp" then ".webp"
      when "image/svg+xml" then ".svg"
      else ".jpg"
      end
    }

    # Helper to download logo from URL (follows redirects)
    download_logo = ->(url, max_redirects = 3) do
      return nil unless url.present?
      return nil if max_redirects <= 0
      begin
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)

        case response
        when Net::HTTPRedirection
          download_logo.call(response["location"], max_redirects - 1)
        when Net::HTTPSuccess
          content_type = response["content-type"]&.split(";")&.first
          return nil unless content_type&.start_with?("image/")

          {
            data: response.body,
            content_type: content_type,
            filename: "logo#{extension_for.call(content_type)}"
          }
        else
          nil
        end
      rescue URI::InvalidURIError, SocketError, Errno::ECONNREFUSED,
             Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        logger.debug "  Failed to download logo: #{e.message}"
        nil
      end
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

    # Optional limit for testing
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

    stats = {
      contacts_new: 0,
      contacts_enriched: 0,
      contacts_skipped: 0,
      companies_new: 0,
      companies_enriched: 0,
      companies_web_enriched: 0,
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
      name_pattern = "%#{name.downcase}%"
      user.companies.find_by("LOWER(legal_name) LIKE ? OR LOWER(commercial_name) LIKE ?", name_pattern, name_pattern)
    }

    eml_files.each.with_index(1) do |eml_path, index|
      # Use relative path for cleaner logs
      eml_relative = eml_path.sub("#{eml_dir}/", "")
      logger.info "[#{index}/#{eml_files.count}] #{eml_relative}"

      begin
        logger.debug "  Calling LLM for extraction..."
        result = LlmEmailExtractor.new(eml_path).extract
        logger.info "  LLM: #{result[:contacts].count} contacts, #{result[:companies].count} companies"

        # Process companies first so we can link contacts to them
        company_map = {}
        result[:companies].each do |company_data|
          # Use legal_name or commercial_name for display/lookup
          display_name = company_data[:commercial_name] || company_data[:legal_name]
          next unless display_name

          # Step 1: Try to find existing company by domain or name from LLM data
          company = find_company_by_domain.call(company_data[:website])
          company ||= find_company_by_name.call(company_data[:legal_name])
          company ||= find_company_by_name.call(company_data[:commercial_name])

          if company
            logger.info "  Found by lookup: #{company.display_name} (id=#{company.id})"
          else
            logger.debug "  Not found by lookup, will web enrich..."
          end

          # Step 2: If not found, enrich with web search FIRST to get complete info
          enriched = {}
          if company.nil?
            # Collect email domains from contacts mentioning this company (case-insensitive match)
            display_name_lower = display_name.downcase
            contact_domains = result[:contacts]
              .select { |c| c[:company_name]&.downcase == display_name_lower }
              .map { |c| c[:email]&.split("@")&.last }
              .compact.uniq

            logger.info "  Web enriching: #{display_name}..."
            logger.debug "  Contact domains hint: #{contact_domains.join(', ')}" if contact_domains.any?
            enriched = CompanyWebEnricher.new(
              display_name,
              hint_domain: company_data[:website],
              contact_domains: contact_domains
            ).enrich

            if enriched.any?
              stats[:companies_web_enriched] += 1
              logger.info "  Web enriched: #{enriched[:legal_name] || enriched[:commercial_name]}"
              logger.debug "  Enriched data: website=#{enriched[:website]} parent=#{enriched[:parent_company_name]}"
              logger.debug "  Contact domains for mismatch check: #{contact_domains.inspect}"

              # Step 3: Re-check with enriched data (domain and legal_name)
              company = find_company_by_domain.call(enriched[:website])
              company ||= find_company_by_name.call(enriched[:legal_name])
              company ||= find_company_by_name.call(enriched[:commercial_name])

              # Check for domain mismatch: if contact_domains don't match enriched domain,
              # this might be a subsidiary with different email domain than parent
              if company && contact_domains.any?
                enriched_domain = Company.normalize_domain(enriched[:website])
                logger.debug "  Domain check: contact_domains=#{contact_domains.inspect} vs enriched_domain=#{enriched_domain}"
                domains_match = contact_domains.any? { |cd| cd == enriched_domain || cd.end_with?(".#{enriched_domain}") }

                if !domains_match
                  logger.info "  Domain mismatch: contacts use #{contact_domains.join(', ')} but enriched domain is #{enriched_domain}"
                  logger.info "  Creating subsidiary instead of using parent: #{company.display_name}"
                  # Don't use the matched company - create subsidiary with parent reference
                  enriched[:parent_company_name] ||= company.display_name
                  company = nil
                end
              end

              if company
                logger.info "  Matched existing company: #{company.display_name}"
              end
            else
              logger.info "  Web enrichment: no results"
            end
          else
            logger.debug "  Found existing company: #{company.display_name}"
          end

          # Step 4: Create new company only if still not found
          was_new = company.nil?
          if was_new
            company = user.companies.new(
              legal_name: enriched[:legal_name] || company_data[:legal_name] || display_name
            )
          end

          updates_made = false

          # Fill in fields from enriched data (for new companies)
          if enriched.any?
            company.commercial_name ||= enriched[:commercial_name]
            # If this is a subsidiary (parent_company_name set due to domain mismatch),
            # use contact_domains to set website instead of enriched website (parent's)
            if enriched[:parent_company_name].present? && contact_domains.any?
              company.website ||= "https://#{contact_domains.first}"
            else
              company.website ||= enriched[:website]
            end
            company.description ||= enriched[:description]
            company.industry ||= enriched[:industry]
            company.location ||= enriched[:location]
            company.web_enriched_at ||= Time.current if was_new
          end

          # Fill in commercial_name from LLM if missing
          if company_data[:commercial_name].present? && company.commercial_name.blank?
            company.commercial_name = company_data[:commercial_name]
            updates_made = true
          end

          # Fill in missing website from LLM data
          if company_data[:website].present? && company.website.blank?
            company.website = company_data[:website]
            updates_made = true
          end

          if was_new || updates_made || company.changed?
            changes_before = company.changes.dup
            company.save!
            if was_new
              stats[:companies_new] += 1
              logger.info "  DB: CREATE company id=#{company.id} legal_name=#{company.legal_name.inspect} source=#{eml_relative}"
            elsif company.saved_changes.any?
              stats[:companies_enriched] += 1
              changed_fields = company.saved_changes.keys - %w[updated_at]
              logger.info "  DB: UPDATE company id=#{company.id} fields=#{changed_fields.join(',')} source=#{eml_relative}"
            end
          end

          # Handle parent company relationship
          if enriched[:parent_company_name].present? && company.parent_company_id.nil?
            parent = find_company_by_name.call(enriched[:parent_company_name])

            if parent.nil?
              # Enrich parent company to get domain for deduplication
              logger.info "  Web enriching parent: #{enriched[:parent_company_name]}..."
              parent_enriched = CompanyWebEnricher.new(enriched[:parent_company_name]).enrich

              if parent_enriched.any?
                stats[:companies_web_enriched] += 1
                logger.info "  Web enriched parent: #{parent_enriched[:legal_name] || parent_enriched[:commercial_name]}"

                # Re-check with enriched data (domain and names)
                parent = find_company_by_domain.call(parent_enriched[:website])
                parent ||= find_company_by_name.call(parent_enriched[:legal_name])
                parent ||= find_company_by_name.call(parent_enriched[:commercial_name])
              end

              # Create parent if still not found
              if parent.nil?
                parent = user.companies.create!(
                  legal_name: parent_enriched[:legal_name] || enriched[:parent_company_name],
                  commercial_name: parent_enriched[:commercial_name],
                  website: parent_enriched[:website],
                  description: parent_enriched[:description],
                  industry: parent_enriched[:industry],
                  location: parent_enriched[:location],
                  web_enriched_at: parent_enriched.any? ? Time.current : nil
                )
                stats[:companies_new] += 1
                logger.info "  DB: CREATE parent company id=#{parent.id} legal_name=#{parent.legal_name.inspect} source=#{eml_relative}"
              else
                logger.info "  Matched existing parent: #{parent.display_name} (id=#{parent.id})"
              end
            end

            company.update!(parent_company_id: parent.id)
            logger.info "  DB: SET parent_company company_id=#{company.id} parent_id=#{parent.id} source=#{eml_relative}"
          end

          # Attach logo: prefer web-enriched URL, fall back to email attachment
          unless company.logo.attached?
            logo_attached = false

            # First try web-enriched logo URL
            if enriched[:logo_url].present?
              logger.debug "  Downloading logo from: #{enriched[:logo_url]}"
              web_logo = download_logo.call(enriched[:logo_url])
              if web_logo
                company.logo.attach(
                  io: StringIO.new(web_logo[:data]),
                  filename: web_logo[:filename],
                  content_type: web_logo[:content_type]
                )
                stats[:logos_attached] += 1
                logger.info "  DB: ATTACH logo company_id=#{company.id} logo_source=web url=#{enriched[:logo_url]} source=#{eml_relative}"
                logo_attached = true
              end
            end

            # Fall back to email attachment logo
            if !logo_attached && company_data[:logo_content_id].present?
              image_data = result[:image_data][company_data[:logo_content_id]]
              if image_data
                company.logo.attach(
                  io: StringIO.new(image_data[:raw_data]),
                  filename: "logo#{extension_for.call(image_data[:content_type])}",
                  content_type: image_data[:content_type]
                )
                stats[:logos_attached] += 1
                logger.info "  DB: ATTACH logo company_id=#{company.id} logo_source=email cid=#{company_data[:logo_content_id]} source=#{eml_relative}"
              end
            end
          end

          # Map both names to this company for contact linking
          company_map[company_data[:legal_name]] = company if company_data[:legal_name]
          company_map[company_data[:commercial_name]] = company if company_data[:commercial_name]
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

          if was_new
            contact.assign_attributes(updates)
            contact.save!
            stats[:contacts_new] += 1
            logger.info "  DB: CREATE contact id=#{contact.id} email=#{contact.email} source=#{eml_relative}"
          elsif updates.any?
            contact.update!(updates)
            stats[:contacts_enriched] += 1
            logger.info "  DB: UPDATE contact id=#{contact.id} fields=#{updates.keys.join(',')} source=#{eml_relative}"
          else
            stats[:contacts_skipped] += 1
          end

          # Link to company (many-to-many, can have multiple)
          if contact_data[:company_name].present?
            company = company_map[contact_data[:company_name]]
            company ||= find_company_by_name.call(contact_data[:company_name])

            if company && !contact.companies.include?(company)
              contact.companies << company
              logger.info "  DB: LINK contact_id=#{contact.id} company_id=#{company.id} source=#{eml_relative}"
            end
          end
        end

        # Small delay to avoid rate limiting
        sleep(0.1) if index % 10 == 0
      rescue => e
        stats[:errors] += 1
        logger.error "  ERROR: #{e.message} source=#{eml_relative}"
        logger.debug "  #{e.backtrace.first}"
      end
    end

    logger.info ""
    logger.info "Enrichment complete!"
    logger.info "  Contacts:"
    logger.info "    New:        #{stats[:contacts_new]}"
    logger.info "    Enriched:   #{stats[:contacts_enriched]}"
    logger.info "    Skipped:    #{stats[:contacts_skipped]}"
    logger.info "  Companies:"
    logger.info "    New:        #{stats[:companies_new]}"
    logger.info "    Enriched:   #{stats[:companies_enriched]}"
    logger.info "    Web search: #{stats[:companies_web_enriched]}"
    logger.info "    Logos:      #{stats[:logos_attached]}"
    logger.info "  Errors:       #{stats[:errors]}"
    logger.info ""
    logger.info "  Total contacts:  #{user.contacts.count}"
    logger.info "  Total companies: #{user.companies.count}"
  end
end
