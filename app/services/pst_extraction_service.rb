# frozen_string_literal: true

# Extracts emails from PST files using readpst (libpst).
#
# Usage:
#   service = PstExtractionService.new("/path/to/file.pst")
#   stats = service.extract
#   # => { eml_count: 150, attachment_count: 45 }
#
#   eml_files = service.eml_files  # Sorted by date, oldest first
#   eml_files.each { |path| process(path) }
#
class PstExtractionService
  class ExtractionError < StandardError; end

  attr_reader :pst_path, :output_dir, :stats, :logger

  def initialize(pst_path, output_dir: nil, logger: Rails.logger)
    @pst_path = pst_path
    @output_dir = output_dir || generate_temp_dir
    @logger = logger
    @stats = { eml_count: 0, attachment_count: 0 }
  end

  def extract
    validate_dependencies!
    validate_pst_file!

    FileUtils.mkdir_p(@output_dir)

    run_readpst
    add_eml_extensions
    fix_content_ids
    count_results

    @stats
  end

  # Returns EML files sorted by sent date (oldest first)
  # This ensures emails are processed chronologically for proper context building
  def eml_files
    @eml_files ||= begin
      files = Dir.glob(File.join(@output_dir, "**/*.eml"))
      sort_by_date(files)
    end
  end

  private

  def validate_dependencies!
    unless system("which readpst > /dev/null 2>&1")
      raise ExtractionError, "readpst not found. Install libpst package (pst-utils on Debian)."
    end
  end

  def validate_pst_file!
    unless File.exist?(@pst_path)
      raise ExtractionError, "PST file not found: #{@pst_path}"
    end
  end

  def run_readpst
    logger.info "[PstExtraction] Running readpst on #{@pst_path}"

    # -j 1: single thread to avoid segfaults
    # -e: output as EML format with extensions
    result = system("readpst", "-j", "1", "-e", "-o", @output_dir, @pst_path)

    unless result
      raise ExtractionError, "readpst failed with exit code #{$?.exitstatus}"
    end
  end

  def add_eml_extensions
    logger.info "[PstExtraction] Adding .eml extensions..."

    # Add .eml extension to files without extensions
    Dir.glob(File.join(@output_dir, "**/*")).each do |file|
      next if File.directory?(file)
      next if File.extname(file).present?
      File.rename(file, "#{file}.eml")
    end
  end

  def fix_content_ids
    logger.info "[PstExtraction] Fixing Content-ID references..."

    require_relative "../../lib/eml_cid_fixer"
    fixer = EmlCidFixer.new(@output_dir, logger: logger)
    fixer.fix_all
  end

  def count_results
    eml_files_list = Dir.glob(File.join(@output_dir, "**/*.eml"))
    all_files = Dir.glob(File.join(@output_dir, "**/*")).reject { |f| File.directory?(f) }

    @stats[:eml_count] = eml_files_list.count
    @stats[:attachment_count] = all_files.count - eml_files_list.count

    logger.info "[PstExtraction] Found #{@stats[:eml_count]} emails, #{@stats[:attachment_count]} attachments"
  end

  def sort_by_date(files)
    files_with_dates = files.map do |file|
      date = extract_date(file)
      [ file, date ]
    end

    files_with_dates
      .sort_by { |_file, date| date || Time.at(0) }
      .map(&:first)
  end

  def extract_date(eml_path)
    # Read only first 8KB to get headers (avoid loading large attachments)
    content = File.read(eml_path, 8192, encoding: "binary") rescue nil
    return nil unless content

    # Look for Date header
    if content =~ /^Date:\s*(.+)$/i
      begin
        Time.parse($1.strip)
      rescue ArgumentError
        nil
      end
    end
  end

  def generate_temp_dir
    File.join(Rails.root, "tmp", "pst_extractions", SecureRandom.uuid)
  end
end
