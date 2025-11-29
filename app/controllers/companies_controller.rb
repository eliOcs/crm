class CompaniesController < ApplicationController
  def index
    @companies = Current.user.companies.order(:name)
  end

  def show
    @company = Current.user.companies.find(params[:id])
    @contacts = @company.contacts.order(:name)
  end
end
