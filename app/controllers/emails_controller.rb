class EmailsController < ApplicationController
  include Pagy::Backend

  before_action :set_email, only: [ :show, :attachment, :download ]

  def index
    @pagy, @emails = pagy(
      Current.user.emails.includes(:email_attachments, :contact).ordered,
      limit: 50
    )
  end

  def show
    fresh_when(@email)
  end

  def attachment
    att = @email.email_attachments.find_by(content_id: params[:cid])

    if att.nil?
      head :not_found
      return
    end

    send_data att.file.download,
              type: att.content_type,
              disposition: "inline",
              filename: att.filename
  end

  def download
    att = @email.file_attachments[params[:index].to_i]

    if att.nil?
      head :not_found
      return
    end

    send_data att.file.download,
              type: att.content_type,
              disposition: "attachment",
              filename: att.filename
  end

  private

  def set_email
    @email = Current.user.emails.find(params[:id])
  end
end
