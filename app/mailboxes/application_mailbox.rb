class ApplicationMailbox < ActionMailbox::Base
  # Route all emails to our inbound domain to the inbound mailbox
  routing /@inbox\.mercuriocrm\.es\z/i => :inbound

  # Catch-all for any other addresses (shouldn't happen with proper config)
  routing all: :inbound
end
