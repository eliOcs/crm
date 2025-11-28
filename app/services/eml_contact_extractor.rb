class EmlContactExtractor
  def initialize(eml_path)
    @eml_path = eml_path
  end

  def extract
    mail = Mail.read(@eml_path)
    contacts = []

    # Extract from From, To, Cc, Bcc fields
    contacts.concat(extract_addresses(mail.from, mail[:from]))
    contacts.concat(extract_addresses(mail.to, mail[:to]))
    contacts.concat(extract_addresses(mail.cc, mail[:cc]))
    contacts.concat(extract_addresses(mail.bcc, mail[:bcc]))

    contacts.uniq { |c| c[:email].downcase }
  end

  private

  def extract_addresses(addresses, field)
    return [] if addresses.blank?

    addresses.filter_map do |email|
      next if email.blank?

      name = extract_name(field, email)
      { email: email.strip.downcase, name: name }
    end
  end

  def extract_name(field, email)
    return nil unless field.respond_to?(:addrs)

    addr = field.addrs.find { |a| a.address&.downcase == email.downcase }
    name = addr&.display_name || addr&.name
    name.presence
  end
end
