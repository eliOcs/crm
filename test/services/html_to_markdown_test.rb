require "test_helper"

class HtmlToMarkdownTest < ActiveSupport::TestCase
  setup do
    @eml_path = Rails.root.join("db/seeds/emails/Archivo de datos de Outlook/Bandeja de entrada/Webmail/1.eml")
    skip "Test email not found" unless File.exist?(@eml_path)

    email_data = EmlReader.new(@eml_path).read
    @html = email_data[:html_body]
    @markdown = HtmlToMarkdown.new(@html).convert
  end

  test "removes CSS style definitions" do
    assert_no_match(/@font-face/, @markdown)
    assert_no_match(/font-family:/, @markdown)
    assert_no_match(/mso-/, @markdown)
  end

  test "removes VML markup" do
    assert_no_match(/<v:/, @markdown)
    assert_no_match(/<o:/, @markdown)
    assert_no_match(/v:shape/, @markdown)
  end

  test "preserves image CID references in markdown format" do
    # Should have markdown image syntax with cid: references
    assert_match(/!\[.*\]\(cid:image002\.png\)/, @markdown)
    assert_match(/!\[.*\]\(cid:image008\.jpg\)/, @markdown)
  end

  test "preserves ITPSA signature content" do
    assert_includes @markdown, "Anna Puchal"
    assert_includes @markdown, "Food Division Manager"
    assert_includes @markdown, "+34 93 452 03 30"
    assert_includes @markdown, "apuchal@itpsa.com"
    assert_includes @markdown, "INDUSTRIAL TECNICA PECUARIA"
  end

  test "preserves Royal Protein signature from forwarded email" do
    assert_includes @markdown, "Irene Taberner i Felip"
    assert_includes @markdown, "R & D Department"
    assert_includes @markdown, "RP ROYAL DISTRIBUTION"
    assert_includes @markdown, "irene@royalprotein.com"
    assert_includes @markdown, "+34 972 57 14 04"
  end

  test "preserves Ana Alcaraz signature" do
    assert_includes @markdown, "Ana Alcaraz"
    assert_includes @markdown, "R+D+s Laboratory Technician"
    assert_includes @markdown, "aalcaraz@itpsa.com"
  end

  test "converts links to markdown format" do
    # Website links should be in markdown format
    assert_match(/\[.*itpsa.*\]\(http/, @markdown)
    assert_match(/\[.*royalprotein.*\]\(http/, @markdown)
  end

  test "preserves email forwarding headers" do
    assert_match(/\*\*De:\*\*.*Ana Alcaraz/, @markdown)
    assert_match(/\*\*De:\*\*.*Irene/, @markdown)
  end

  test "output is significantly smaller than input HTML" do
    # Markdown should be much more compact than raw HTML
    assert @markdown.length < @html.length / 5, "Markdown should be at least 5x smaller than HTML"
  end

  test "handles empty HTML gracefully" do
    assert_equal "", HtmlToMarkdown.new(nil).convert
    assert_equal "", HtmlToMarkdown.new("").convert
  end

  test "handles HTML without body" do
    simple_html = "<html><head><style>body{}</style></head></html>"
    result = HtmlToMarkdown.new(simple_html).convert
    assert_not_includes result, "body{}"
  end

  test "preserves table data from email" do
    # The email contains a table with sample data
    assert_includes @markdown, "080125PCD/01"
    assert_includes @markdown, "T25"
  end

  test "unwraps SonicWall protected URLs" do
    # URLs should be unwrapped from SonicWall protection
    assert_includes @markdown, "](https://itpsa.com/)"
    assert_includes @markdown, "](http://www.royalprotein.com/)"

    # Should not contain sonicwall wrapper URLs
    assert_no_match(/sonicwall\.url-protection\.com/, @markdown)
  end

  test "unwrap_url handles various cases" do
    converter = HtmlToMarkdown.new("")

    # SonicWall URL
    sonicwall = "https://sonicwall.url-protection.com/v1/url?o=https%3A//example.com/&g=abc"
    assert_equal "https://example.com/", converter.send(:unwrap_url, sonicwall)

    # Regular URL (unchanged)
    regular = "https://example.com"
    assert_equal "https://example.com", converter.send(:unwrap_url, regular)

    # Nil/blank (unchanged)
    assert_nil converter.send(:unwrap_url, nil)
    assert_equal "", converter.send(:unwrap_url, "")
  end
end
