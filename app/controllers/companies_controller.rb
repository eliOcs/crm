class CompaniesController < ApplicationController
  include InlineEditable

  inline_editable :legal_name, :commercial_name, :domain, :location, :website, :vat_id

  def index
    @companies = Current.user.companies.order(Arel.sql("COALESCE(commercial_name, legal_name)"))
  end

  def show
    @company = Current.user.companies.find(params[:id])
    @contacts = @company.contacts.order(:name)
  end

  def update
    @company = Current.user.companies.find(params[:id])
    inline_update(@company)
  end
end
