class ContactsController < ApplicationController
  include InlineEditable
  include ActionView::Helpers::TextHelper

  inline_editable :name, :job_role, :department, :phone_numbers

  def index
    @contacts = Current.user.contacts.includes(:companies).order(:name)
    fresh_when @contacts
  end

  def show
    @contact = Current.user.contacts.includes(:companies).find(params[:id])
    fresh_when etag: [ @contact, @contact.companies.cache_key_with_version ]
  end

  def edit_notes
    @contact = Current.user.contacts.find(params[:id])
    render partial: "shared/notes_editor", locals: { record: @contact }
  end

  def update
    @contact = Current.user.contacts.find(params[:id])

    if params[:contact]&.key?(:notes)
      update_notes(@contact)
    else
      inline_update(@contact)
    end
  end

  private

  def transform_value(field, value)
    if field == "phone_numbers"
      value.to_s.split(",").map(&:strip).reject(&:blank?)
    else
      value
    end
  end

  def update_notes(record)
    old_text = record.notes&.to_plain_text.presence || ""

    if record.update(notes: params[:contact][:notes])
      new_text = record.notes&.to_plain_text.presence || ""

      record.audit_logs.create!(
        user: Current.user,
        action: "update",
        message: "Updated notes via UI",
        field_changes: { "notes" => { "from" => truncate(old_text, length: 100), "to" => truncate(new_text, length: 100) } },
        metadata: { source: "ui" }
      )

      redirect_to record
    else
      render partial: "shared/notes_editor", locals: { record: record }, status: :unprocessable_entity
    end
  end
end
