class MicrosoftGraphClient
  BASE_URL = "https://graph.microsoft.com/v1.0"

  class TokenExpiredError < StandardError; end
  class GraphApiError < StandardError; end

  def initialize(access_token)
    @access_token = access_token
  end

  def me
    get("/me")
  end

  def messages(options = {})
    query = build_query(options)
    get("/me/messages", query)
  end

  def message(id)
    get("/me/messages/#{id}")
  end

  private

  def get(path, query = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) if query.any?

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@access_token}"
    request["Accept"] = "application/json"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    handle_response(response)
  end

  def build_query(options)
    query = {}
    query["$top"] = options[:top] if options[:top]
    query["$skip"] = options[:skip] if options[:skip]
    query["$filter"] = options[:filter] if options[:filter]
    query["$select"] = options[:select].join(",") if options[:select]
    query["$orderby"] = options[:orderby] if options[:orderby]
    query
  end

  def handle_response(response)
    case response.code.to_i
    when 200..299
      JSON.parse(response.body)
    when 401
      raise TokenExpiredError, "Access token expired or invalid"
    else
      raise GraphApiError, "Graph API error: #{response.code} - #{response.body}"
    end
  end
end
