require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @subscription = @user.microsoft_subscriptions.create!(
      subscription_id: "sub-123",
      resource: "me/mailFolders/inbox/messages",
      folder: "inbox",
      expires_at: 1.day.from_now,
      client_state: "secret-state-123"
    )
  end

  test "responds to validation request with token" do
    post webhooks_microsoft_url, params: { validationToken: "abc123" }

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_equal "abc123", response.body
  end

  test "processes notification and enqueues job" do
    notification = {
      value: [ {
        subscriptionId: "sub-123",
        clientState: "secret-state-123",
        resourceData: { id: "msg-456" }
      } ]
    }

    assert_enqueued_with(job: FetchMicrosoftEmailJob, args: [ { user_id: @user.id, graph_id: "msg-456" } ]) do
      post webhooks_microsoft_url, params: notification, as: :json
    end

    assert_response :accepted
  end

  test "rejects notification with invalid client_state" do
    notification = {
      value: [ {
        subscriptionId: "sub-123",
        clientState: "wrong-state",
        resourceData: { id: "msg-456" }
      } ]
    }

    assert_no_enqueued_jobs do
      post webhooks_microsoft_url, params: notification, as: :json
    end

    assert_response :accepted
  end

  test "ignores unknown subscription" do
    notification = {
      value: [ {
        subscriptionId: "unknown-sub",
        clientState: "secret-state-123",
        resourceData: { id: "msg-456" }
      } ]
    }

    assert_no_enqueued_jobs do
      post webhooks_microsoft_url, params: notification, as: :json
    end

    assert_response :accepted
  end
end
