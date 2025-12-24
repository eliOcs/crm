class EmailsController < ApplicationController
  def index
    page = (params[:page] || 1).to_i
    result = EmlReader.paginate(page: page, per_page: 50)

    @emails = result[:emails].map do |path|
      email = EmlReader.new(path).read
      email&.merge(encoded_path: EmlReader.encode_path(path))
    end.compact

    @page = result[:page]
    @total_pages = result[:total_pages]
    @total = result[:total]
  end

  def show
    path = EmlReader.decode_path(params[:id])

    if path.nil?
      redirect_to emails_path, alert: "Email not found"
      return
    end

    return unless stale?(last_modified: File.mtime(path))

    @email = EmlReader.new(path).read
    @encoded_path = params[:id]

    if @email.nil?
      redirect_to emails_path, alert: "Email not found"
    end
  end

  def attachment
    path = EmlReader.decode_path(params[:id])
    content_id = params[:cid]

    if path.nil?
      head :not_found
      return
    end

    return unless stale?(last_modified: File.mtime(path))

    attachment = EmlReader.new(path).attachment(content_id)

    if attachment.nil?
      head :not_found
      return
    end

    send_data attachment[:data],
              type: attachment[:content_type],
              disposition: "inline",
              filename: attachment[:filename]
  end

  def download
    path = EmlReader.decode_path(params[:id])
    index = params[:index].to_i

    if path.nil?
      head :not_found
      return
    end

    return unless stale?(last_modified: File.mtime(path))

    attachment = EmlReader.new(path).attachment_by_index(index)

    if attachment.nil?
      head :not_found
      return
    end

    send_data attachment[:data],
              type: attachment[:content_type],
              disposition: "attachment",
              filename: attachment[:filename]
  end
end
