class ContactsController < ApplicationController
  def index
    @contacts = Current.user.contacts.includes(:companies).order(:name)
  end

  def show
    @contact = Current.user.contacts.find(params[:id])
  end
end
