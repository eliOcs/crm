class ContactsController < ApplicationController
  def index
    @contacts = Current.user.contacts.order(:name)
  end
end
