class ContactsController < ApplicationController
  def index
    @contacts = Current.user.contacts.includes(:companies).order(:name)
  end
end
