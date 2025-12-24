class DashboardController < ApplicationController
  allow_unauthenticated_access

  def show
    redirect_to landing_path unless authenticated?
  end
end
