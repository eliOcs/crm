class MicrosoftGraphClient
  BASE_URL = "https://graph.microsoft.com/v1.0"

  class TokenExpiredError < StandardError; end
  class GraphApiError < StandardError; end

  def initialize(access_token)
    @access_token = access_token
  end

  # User profile
  def me
    get("/me")
  end

  # Email messages
  def messages(options = {})
    query = build_query(options)
    get("/me/messages", query)
  end

  # Get messages from a specific folder (inbox, sentitems, etc.)
  def folder_messages(folder, options = {})
    query = build_query(options)
    query["$count"] = "true" if options[:count]
    get("/me/mailFolders/#{folder}/messages", query, headers: options[:count] ? { "ConsistencyLevel" => "eventual" } : {})
  end

  # Count messages in a folder with filter
  def count_folder_messages(folder, filter:)
    response = folder_messages(folder, filter: filter, top: 1, count: true)
    response["@odata.count"] || 0
  end

  # Follow @odata.nextLink for pagination
  def get_next_page(next_link)
    uri = URI(next_link)
    request = Net::HTTP::Get.new(uri)
    set_headers(request)
    execute(uri, request)
  end

  def message(id, options = {})
    query = {}
    query["$select"] = options[:select].join(",") if options[:select]
    get("/me/messages/#{id}", query)
  end

  def attachments(message_id)
    get("/me/messages/#{message_id}/attachments")
  end

  def attachment(message_id, attachment_id)
    get("/me/messages/#{message_id}/attachments/#{attachment_id}")
  end

  # Webhook subscriptions
  def create_subscription(change_type:, notification_url:, resource:, expiration_date_time:, client_state:)
    post("/subscriptions", {
      changeType: change_type,
      notificationUrl: notification_url,
      resource: resource,
      expirationDateTime: expiration_date_time,
      clientState: client_state
    })
  end

  def renew_subscription(subscription_id, new_expiration)
    patch("/subscriptions/#{subscription_id}", {
      expirationDateTime: new_expiration.iso8601
    })
  end

  def delete_subscription(subscription_id)
    delete("/subscriptions/#{subscription_id}")
  end

  def list_subscriptions
    get("/subscriptions")
  end

  private

  def get(path, query = {}, headers: {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) if query.any?

    request = Net::HTTP::Get.new(uri)
    set_headers(request)
    headers.each { |key, value| request[key] = value }

    execute(uri, request)
  end

  def post(path, body)
    request_with_body(Net::HTTP::Post, path, body)
  end

  def patch(path, body)
    request_with_body(Net::HTTP::Patch, path, body)
  end

  def delete(path)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Delete.new(uri)
    set_headers(request)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    # DELETE returns 204 No Content on success
    return true if response.code.to_i == 204

    handle_response(response)
  end

  def request_with_body(http_method, path, body)
    uri = URI("#{BASE_URL}#{path}")
    request = http_method.new(uri)
    set_headers(request)
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    execute(uri, request)
  end

  def set_headers(request)
    request["Authorization"] = "Bearer #{@access_token}"
    request["Accept"] = "application/json"
  end

  def execute(uri, request)
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
      body = response.body
      body.present? ? JSON.parse(body) : {}
    when 401
      raise TokenExpiredError, "Access token expired or invalid"
    else
      raise GraphApiError, "Graph API error: #{response.code} - #{response.body}"
    end
  end
end
