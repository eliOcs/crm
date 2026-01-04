class CompaniesController < ApplicationController
  include InlineEditable
  include ActionView::Helpers::TextHelper

  inline_editable :legal_name, :commercial_name, :domain, :location, :website, :vat_id

  def index
    @companies = Current.user.companies.order(Arel.sql("COALESCE(commercial_name, legal_name)"))
    fresh_when @companies
  end

  def show
    @company = Current.user.companies.find(params[:id])
    @contacts = @company.contacts.order(:name)
    fresh_when etag: [ @company, @contacts.cache_key_with_version ]
  end

  def edit_notes
    @company = Current.user.companies.find(params[:id])
    render partial: "shared/notes_editor", locals: { record: @company }
  end

  def update
    @company = Current.user.companies.find(params[:id])

    if params[:company]&.key?(:notes)
      update_notes(@company)
    else
      inline_update(@company)
    end
  end

  private

  def update_notes(record)
    old_text = record.notes&.to_plain_text.presence || ""

    if record.update(notes: params[:company][:notes])
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
