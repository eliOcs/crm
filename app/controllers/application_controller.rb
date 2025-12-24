class ApplicationController < ActionController::Base
  include Authentication
  include HttpAcceptLanguage::AutoLocale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_locale

  private

  def set_locale
    I18n.locale = current_locale
  end

  def current_locale
    if Current.user
      Current.user.locale.to_sym
    else
      http_accept_language.compatible_language_from(I18n.available_locales) || I18n.default_locale
    end
  end

  def detect_browser_locale
    http_accept_language.compatible_language_from(I18n.available_locales)&.to_s || "en"
  end
end
