class CompaniesController < ApplicationController
  def index
    @companies = Current.user.companies.order(Arel.sql("COALESCE(commercial_name, legal_name)"))
  end

  def show
    @company = Current.user.companies.find(params[:id])
    @contacts = @company.contacts.order(:name)
  end

  def update
    @company = Current.user.companies.find(params[:id])

    # Only allow updating specific fields
    permitted_fields = %w[legal_name commercial_name domain location website vat_id]
    field = (params.keys & permitted_fields).first
    return render json: { error: "Invalid field" }, status: :unprocessable_entity unless field

    old_value = @company.send(field)
    new_value = params[field].presence

    if @company.update(field => new_value)
      # Create audit log
      @audit_log = @company.audit_logs.create!(
        user: Current.user,
        action: "update",
        message: "Updated #{field.humanize.downcase} via UI",
        field_changes: { field => { "from" => old_value.to_s, "to" => new_value.to_s } },
        metadata: { source: "ui" }
      )

      respond_to do |format|
        format.turbo_stream
        format.json { render json: { success: true, value: new_value } }
      end
    else
      render json: { error: @company.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end
end
