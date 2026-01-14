class HtmlToMarkdown
  # Convert HTML to Markdown for cleaner LLM processing
  # Preserves structure, links, and image references while removing noise

  def initialize(html)
    @html = html
  end

  def convert
    return "" if @html.blank?

    doc = Nokogiri::HTML.fragment(@html)
    clean_document(doc)

    # Process the document
    process_node(doc).strip.gsub(/\n{3,}/, "\n\n")
  end

  private

  # Use Nokogiri to remove elements instead of regex to avoid catastrophic backtracking
  def clean_document(doc)
    # Remove style, script, and other non-content elements
    doc.css("style, script, meta, link, title").each(&:remove)

    # Remove XML/VML namespace elements (Microsoft Office)
    doc.xpath("//*[starts-with(name(), 'v:') or starts-with(name(), 'o:') or starts-with(name(), 'w:')]").each(&:remove)

    # Remove comments (including VML conditionals)
    doc.xpath("//comment()").each(&:remove)

    doc
  end

  def process_node(node)
    result = []

    node.children.each do |child|
      case child.name
      when "text"
        text = child.text.gsub(/[\t ]+/, " ")
        result << text unless text.strip.empty? && result.last&.end_with?("\n")
      when "br"
        result << "\n"
      when "p", "div"
        content = process_node(child).strip
        result << "\n#{content}\n" unless content.empty?
      when "h1", "h2", "h3", "h4", "h5", "h6"
        level = child.name[1].to_i
        content = process_node(child).strip
        result << "\n#{"#" * level} #{content}\n" unless content.empty?
      when "a"
        href = unwrap_url(child["href"])
        text = process_node(child).strip
        if href.present? && href !~ /^(javascript:|#)/
          # Clean up mailto: links
          if href.start_with?("mailto:")
            email = href.sub("mailto:", "").split("&").first
            result << (text.present? && text != email ? "#{text} <#{email}>" : email)
          else
            result << (text.present? ? "[#{text}](#{href})" : href)
          end
        else
          result << text
        end
      when "img"
        src = child["src"]
        alt = child["alt"]&.gsub(/\n/, " ")&.strip || ""
        if src.present?
          # Preserve CID references for inline images
          if src.start_with?("cid:")
            cid = src.sub("cid:", "").split("@").first
            result << "![#{alt}](cid:#{cid})"
          else
            result << "![#{alt}](#{src})"
          end
        end
      when "table"
        table_content = process_table(child)
        result << "\n#{table_content}\n" unless table_content.strip.empty?
      when "tr", "td", "th", "thead", "tbody", "tfoot"
        # Handled by process_table
        result << process_node(child)
      when "ul"
        items = child.css("> li").map { |li| "- #{process_node(li).strip}" }
        result << "\n#{items.join("\n")}\n"
      when "ol"
        items = child.css("> li").map.with_index { |li, i| "#{i + 1}. #{process_node(li).strip}" }
        result << "\n#{items.join("\n")}\n"
      when "li"
        result << process_node(child)
      when "b", "strong"
        content = process_node(child).strip
        result << "**#{content}**" unless content.empty?
      when "i", "em"
        content = process_node(child).strip
        result << "*#{content}*" unless content.empty?
      when "span", "font"
        result << process_node(child)
      when "blockquote"
        content = process_node(child).strip
        quoted = content.lines.map { |l| "> #{l}" }.join
        result << "\n#{quoted}\n"
      when "hr"
        result << "\n---\n"
      when "head", "meta", "link", "title"
        # Skip non-content elements
      else
        # Default: process children
        result << process_node(child)
      end
    end

    result.join
  end

  def process_table(table)
    rows = []

    # Only get direct child rows (not from nested tables)
    # Account for tbody/thead/tfoot wrappers
    direct_rows = table.xpath("./tr | ./tbody/tr | ./thead/tr | ./tfoot/tr")

    direct_rows.each do |tr|
      # Only get direct child cells (not from nested tables within cells)
      cells = tr.xpath("./td | ./th").map do |cell|
        process_node(cell).strip.gsub(/\s+/, " ")
      end
      # Skip empty rows
      next if cells.all?(&:blank?)
      rows << "| #{cells.join(" | ")} |"
    end

    return "" if rows.empty?

    # Add markdown table separator after first row
    # Note: Markdown only supports single-row headers, multi-row headers
    # will have subsequent header rows treated as data rows
    if rows.length > 1
      col_count = rows.first.count("|") - 1
      separator = "| #{([ "---" ] * col_count).join(" | ")} |"
      rows.insert(1, separator)
    end

    rows.join("\n")
  end

  # Unwrap URLs from email security gateways (SonicWall, Proofpoint, etc.)
  # These services wrap links for click-time protection against phishing/malware
  def unwrap_url(url)
    return url if url.blank?

    # SonicWall URL Protection: sonicwall.url-protection.com/v1/url?o=<encoded_url>
    if url.include?("sonicwall.url-protection.com")
      if (match = url.match(/[?&]o=([^&]+)/))
        return CGI.unescape(match[1])
      end
    end

    # Add more unwrappers here as needed:
    # - Proofpoint: urldefense.proofpoint.com
    # - Mimecast: protect-xx.mimecast.com
    # - Microsoft SafeLinks: safelinks.protection.outlook.com

    url
  end
end
