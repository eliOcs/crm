class MicrosoftOauthService
  SCOPES = %w[User.Read Mail.Read Mail.Send offline_access].freeze

  def initialize(redirect_uri:)
    @client_id = ENV.fetch("MICROSOFT_CLIENT_ID")
    @client_secret = ENV.fetch("MICROSOFT_CLIENT_SECRET")
    @redirect_uri = redirect_uri
    @client = build_oauth_client
  end

  def authorization_url(state:)
    @client.auth_code.authorize_url(
      redirect_uri: @redirect_uri,
      scope: SCOPES.join(" "),
      state: state,
      response_type: "code",
      response_mode: "query"
    )
  end

  def exchange_code(code)
    token = @client.auth_code.get_token(
      code,
      redirect_uri: @redirect_uri
    )
    token_to_hash(token)
  end

  def refresh_token(credential)
    token = OAuth2::AccessToken.from_hash(@client, {
      access_token: credential.access_token,
      refresh_token: credential.refresh_token,
      expires_at: credential.expires_at.to_i
    })
    new_token = token.refresh!
    token_to_hash(new_token)
  end

  private

  def build_oauth_client
    OAuth2::Client.new(
      @client_id,
      @client_secret,
      site: "https://login.microsoftonline.com",
      authorize_url: "/common/oauth2/v2.0/authorize",
      token_url: "/common/oauth2/v2.0/token"
    )
  end

  def token_to_hash(token)
    {
      access_token: token.token,
      refresh_token: token.refresh_token,
      expires_at: Time.at(token.expires_at),
      scope: token.params["scope"]
    }
  end
end
