module EmailsHelper
  ALLOWED_TAGS = %w[p br div span a b i u strong em h1 h2 h3 h4 h5 h6 ul ol li table tr td th thead tbody img hr blockquote pre code].freeze
  ALLOWED_ATTRIBUTES = %w[href src alt style class].freeze

  def render_email_html(email)
    if email.body_html.present?
      html = email.body_html.dup

      # Remove embedded styles (they can break page layout)
      html.gsub!(/<style[^>]*>.*?<\/style>/mi, "")

      # Remove HTML comments (often contain CSS from Outlook)
      # Handle both raw comments and escaped ones (from previously sanitized imports)
      html.gsub!(/<!--.*?-->/m, "")
      html.gsub!(/&lt;!--.*?--&gt;/m, "")

      # Replace CID references with attachment URLs
      email.inline_attachments.each do |att|
        next unless att.content_id.present?

        # CID format can be "image001.png@01DA..." or just "image001.png"
        # Match both the full CID and just the filename prefix
        url = attachment_email_path(email, cid: att.content_id)
        html.gsub!("cid:#{att.content_id}", url)

        # Also try matching just the filename prefix (before @)
        filename_prefix = att.content_id.split("@").first
        if filename_prefix != att.content_id
          html.gsub!("cid:#{filename_prefix}", url)
        end
      end

      sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES).html_safe
    elsif email.body_plain.present?
      content_tag(:pre, email.body_plain)
    else
      content_tag(:p, t("emails.no_body"), class: "txt-subtle")
    end
  end
end
