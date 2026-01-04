class InboundMailbox < ApplicationMailbox
  def process
    # Log receipt for debugging
    Rails.logger.info "[InboundMailbox] Received email from: #{mail.from}, to: #{mail.to}, subject: #{mail.subject}"

    # TODO: Look up user by inbound email address
    # TODO: Import email via EmailImportService
    # TODO: Queue for enrichment processing

    # For now, just acknowledge receipt
    Rails.logger.info "[InboundMailbox] Email processed successfully"
  end
end
