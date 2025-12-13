class ContactsController < ApplicationController
  include InlineEditable

  inline_editable :name, :job_role, :department, :phone_numbers

  def index
    @contacts = Current.user.contacts.includes(:companies).order(:name)
  end

  def show
    @contact = Current.user.contacts.find(params[:id])
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
