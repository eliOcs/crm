class ContactsController < ApplicationController
  include InlineEditable

  inline_editable :name, :job_role, :department, :phone_numbers

  def index
    @contacts = Current.user.contacts.includes(:companies).order(:name)
    fresh_when @contacts
  end

  def show
    @contact = Current.user.contacts.includes(:companies).find(params[:id])
    fresh_when etag: [ @contact, @contact.companies.cache_key_with_version ]
  end

  def update
    @contact = Current.user.contacts.find(params[:id])
    inline_update(@contact)
  end

  private

  def transform_value(field, value)
    if field == "phone_numbers"
      value.to_s.split(",").map(&:strip).reject(&:blank?)
    else
      value
    end
  end
end
