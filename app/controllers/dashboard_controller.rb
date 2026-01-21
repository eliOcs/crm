class DashboardController < ApplicationController
  allow_unauthenticated_access

  def show
    render "pages/home" unless authenticated?
  end
end
