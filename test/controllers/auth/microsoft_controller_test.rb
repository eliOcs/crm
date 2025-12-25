require "test_helper"

class Auth::MicrosoftControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "connect redirects to Microsoft authorization URL" do
    get connect_auth_microsoft_url

    assert_response :redirect
    assert_match "login.microsoftonline.com", response.location
    assert_match "oauth2/v2.0/authorize", response.location
    assert_match ENV["MICROSOFT_CLIENT_ID"], response.location
    assert_match "Mail.Read", response.location
    assert_match "offline_access", response.location
  end

  test "connect stores state in session for CSRF protection" do
    get connect_auth_microsoft_url

    # State should be in the redirect URL
    assert_match /state=[\w-]+/, response.location
  end

  test "callback with valid code creates microsoft credential" do
    # Start OAuth flow to get a valid state in session
    get connect_auth_microsoft_url
    recorded_state = response.location.match(/state=([\w-]+)/)[1]

    VCR.use_cassette("microsoft_oauth_callback") do
      get callback_auth_microsoft_url, params: {
        code: "test-authorization-code",
        state: recorded_state
      }
    end

    # Should redirect to settings with success message
    assert_redirected_to edit_settings_url
    assert_equal I18n.t("settings.microsoft.connected"), flash[:notice]

    # Should have created a credential
    @user.reload
    assert @user.microsoft_connected?
    assert_equal "dcb75d6e-5dbf-4ed5-b82e-be9243b006b2", @user.microsoft_credential.microsoft_user_id
    assert_equal "admin@eliocapella.onmicrosoft.com", @user.microsoft_credential.email
  end

  test "callback with invalid state redirects with error" do
    get callback_auth_microsoft_url, params: {
      code: "some-code",
      state: "invalid-state"
    }

    assert_redirected_to edit_settings_url
    assert_equal I18n.t("settings.microsoft.invalid_state"), flash[:alert]
  end

  test "callback with error param redirects with error message" do
    # First set up a valid state
    get connect_auth_microsoft_url
    state = response.location.match(/state=([\w-]+)/)[1]

    get callback_auth_microsoft_url, params: {
      error: "access_denied",
      error_description: "User denied access",
      state: state
    }

    assert_redirected_to edit_settings_url
    assert_equal I18n.t("settings.microsoft.auth_failed"), flash[:alert]
  end

  test "disconnect removes microsoft credential" do
    # First create a credential
    @user.create_microsoft_credential!(
      microsoft_user_id: "test-user-id",
      email: "test@example.com",
      access_token: "test-token",
      refresh_token: "test-refresh",
      expires_at: 1.hour.from_now
    )

    assert @user.microsoft_connected?

    delete disconnect_auth_microsoft_url

    assert_redirected_to edit_settings_url
    assert_equal I18n.t("settings.microsoft.disconnected"), flash[:notice]

    @user.reload
    assert_not @user.microsoft_connected?
  end

  test "disconnect when not connected still succeeds" do
    assert_not @user.microsoft_connected?

    delete disconnect_auth_microsoft_url

    assert_redirected_to edit_settings_url
    assert_equal I18n.t("settings.microsoft.disconnected"), flash[:notice]
  end
end
