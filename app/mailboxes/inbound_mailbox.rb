class InboundMailbox < ApplicationMailbox
  def process
    user = find_user_by_recipient
    unless user
      Rails.logger.warn "[InboundMailbox] No user found for recipient: #{mail.to}"
      # Return 204 but don't process - email is silently discarded
      return
    end

    unless user.inbound_email_enabled?
      Rails.logger.info "[InboundMailbox] Inbound email disabled for user #{user.id}, discarding"
      return
    end

    # Use unified service for email storage and enrichment
    service = EmailProcessingService.new(user)
    result = service.process_mail(mail, source_type: "forwarded", enrich: :async)

    if result.created?
      Rails.logger.info "[InboundMailbox] Imported email id=#{result.email.id} for user=#{user.id}"
    elsif result.skipped?
      Rails.logger.debug "[InboundMailbox] Skipped duplicate email for user=#{user.id}"
    end
  rescue => e
    Rails.logger.error "[InboundMailbox] Error processing email: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    # Re-raise to return 500 and trigger Postfix retry
    raise
  end

  private

  def find_user_by_recipient
    # Check all possible recipient sources:
    # 1. Delivered-To header (envelope recipient from Postfix, needed for BCC)
    # 2. X-Original-To header (fallback for some mail servers)
    # 3. To header (normal forwarded emails)
    recipients = []
    recipients << mail["Delivered-To"]&.decoded
    recipients << mail["X-Original-To"]&.decoded
    recipients.concat(Array(mail.to))

    recipients.compact.uniq.each do |recipient|
      user = User.find_by_inbound_email(recipient)
      return user if user
    end
    nil
  end
end
