class ContactsController < ApplicationController
  def index
    @contacts = Current.user.contacts.includes(:companies).order(:name)
  end

  def show
    @contact = Current.user.contacts.find(params[:id])
  end

  def update
    @contact = Current.user.contacts.find(params[:id])

    # Only allow updating specific fields
    permitted_fields = %w[name job_role department phone_numbers]
    field = (params.keys & permitted_fields).first
    return render json: { error: "Invalid field" }, status: :unprocessable_entity unless field

    old_value = @contact.send(field)
    new_value = params[field]

    # Handle phone_numbers as array
    if field == "phone_numbers"
      new_value = new_value.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    if @contact.update(field => new_value)
      # Create audit log
      @audit_log = @contact.audit_logs.create!(
        user: Current.user,
        action: "update",
        message: "Updated #{field.humanize.downcase} via UI",
        field_changes: { field => { "from" => format_value(old_value), "to" => format_value(new_value) } },
        metadata: { source: "ui" }
      )

      respond_to do |format|
        format.turbo_stream
        format.json { render json: { success: true, value: new_value } }
      end
    else
      render json: { error: @contact.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def format_value(value)
    return value.join(", ") if value.is_a?(Array)
    value.to_s
  end
end
