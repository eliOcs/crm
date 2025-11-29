namespace :import do
  desc "Deduplicate companies using LLM analysis"
  task dedup_companies: :environment do
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

    companies = user.companies.includes(:contacts, logo_attachment: :blob).order(:name)
    logos_count = companies.count { |c| c.logo.attached? }

    puts "Found #{companies.count} companies (#{logos_count} with logos)"
    puts "Sending to Claude for analysis..."
    puts

    duplicate_groups = LlmCompanyDeduplicator.new(companies).find_duplicates

    if duplicate_groups.empty?
      puts "No duplicates found!"
      exit 0
    end

    puts "Found #{duplicate_groups.size} duplicate group(s):"
    puts

    merges = []
    duplicate_groups.each do |group|
      group_companies = companies.select { |c| group[:company_ids].include?(c.id) }
      next if group_companies.size < 2

      winner = pick_winner(group_companies)
      losers = group_companies - [ winner ]

      puts "  #{group_companies.map { |c| "[#{c.id}] #{c.name}" }.join(' + ')}"
      puts "    → Keeping \"#{winner.name}\" (#{winner_reason(winner)})"
      puts "    Reason: #{group[:reason]}"
      puts

      merges << { winner: winner, losers: losers }
    end

    puts "Merging..."
    stats = { contacts_moved: 0, companies_deleted: 0 }

    merges.each do |merge|
      winner = merge[:winner]
      merge[:losers].each do |loser|
        # Move contacts to winner (many-to-many)
        loser.contacts.each do |contact|
          unless contact.companies.include?(winner)
            contact.companies << winner
            stats[:contacts_moved] += 1
          end
          contact.companies.delete(loser)
        end

        # Copy missing data from loser to winner
        winner.website ||= loser.website
        winner.domain ||= loser.domain

        # Copy logo if winner doesn't have one
        if !winner.logo.attached? && loser.logo.attached?
          winner.logo.attach(loser.logo.blob)
        end

        winner.save! if winner.changed?

        # Delete the duplicate
        loser.destroy!
        stats[:companies_deleted] += 1
      end
    end

    puts "  Moved #{stats[:contacts_moved]} contact links, deleted #{stats[:companies_deleted]} companies"
    puts
    puts "Done! #{user.companies.count} companies remaining."
  end

  def pick_winner(companies)
    companies.max_by do |c|
      [
        c.domain.present? ? 1 : 0,
        c.logo.attached? ? 1 : 0,
        c.contacts.count,
        -c.id
      ]
    end
  end

  def winner_reason(company)
    reasons = []
    reasons << "has domain" if company.domain.present?
    reasons << "has logo" if company.logo.attached?
    reasons << "#{company.contacts.count} contacts" if company.contacts.count > 0
    reasons << "first created" if reasons.empty?
    reasons.join(", ")
  end
end
