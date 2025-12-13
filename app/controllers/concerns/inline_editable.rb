module InlineEditable
  extend ActiveSupport::Concern

  included do
    class_attribute :inline_editable_fields, default: []
  end

  class_methods do
    def inline_editable(*fields)
      self.inline_editable_fields = fields.map(&:to_s)
    end
  end

  def inline_update(record)
    field = (params.keys & inline_editable_fields).first
    return render json: { error: "Invalid field" }, status: :unprocessable_entity unless field

    old_value = record.send(field)
    new_value = transform_value(field, params[field])

    if record.update(field => new_value)
      @audit_log = record.audit_logs.create!(
        user: Current.user,
        action: "update",
        message: "Updated #{field.humanize.downcase} via UI",
        field_changes: { field => { "from" => format_value(old_value), "to" => format_value(new_value) } },
        metadata: { source: "ui" }
      )

      respond_to do |format|
        format.turbo_stream { render "shared/inline_update" }
        format.json { render json: { success: true, value: new_value } }
      end
    else
      render json: { error: record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def transform_value(field, value)
    # Override in controller for custom transformations (e.g., arrays)
    value
  end

  def format_value(value)
    return value.join(", ") if value.is_a?(Array)
    value.to_s
  end
end
