class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    redirect_to root_path if authenticated?
  end

  def privacy
  end

  def terms
  end
end
