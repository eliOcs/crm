require "test_helper"

class MicrosoftWebhookFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)

    # Create Microsoft credential for the user
    @user.create_microsoft_credential!(
      microsoft_user_id: "dcb75d6e-5dbf-4ed5-b82e-be9243b006b2",
      email: "admin@eliocapella.onmicrosoft.com",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      expires_at: 1.hour.from_now
    )

    # Create webhook subscription
    @subscription = @user.microsoft_subscriptions.create!(
      subscription_id: "test-subscription-id",
      resource: "me/mailFolders/inbox/messages",
      folder: "inbox",
      expires_at: 1.day.from_now,
      client_state: "test-client-state"
    )

    @graph_id = "AAMkAGQyN2YwZjEyLTA4YTYtNGUzNS05ZjRiLWFjZjE3ZThmNmEyMQBGAAAAAAB8L27KsQb5QbFNIxRaPgmzBwCsDrxp0draSoKqIjnY3vwLAAAAAAEMAACsDrxp0draSoKqIjnY3vwLAAABrdlnAAA="
  end

  test "full webhook flow: receive notification, fetch email, and enrich with contacts and tasks" do
    # Initial counts
    initial_email_count = @user.emails.count
    initial_contact_count = @user.contacts.count
    initial_task_count = @user.tasks.count

    # Step 1: Simulate webhook notification
    notification = {
      value: [ {
        subscriptionId: @subscription.subscription_id,
        clientState: @subscription.client_state,
        resourceData: { id: @graph_id }
      } ]
    }

    # Post webhook notification - this enqueues FetchMicrosoftEmailJob
    assert_enqueued_with(job: FetchMicrosoftEmailJob) do
      post webhooks_microsoft_url, params: notification, as: :json
    end
    assert_response :accepted

    # Step 2: Process the fetch job with VCR cassette for Microsoft Graph API
    email = nil
    VCR.use_cassette("microsoft_graph_fetch_email") do
      perform_enqueued_jobs only: FetchMicrosoftEmailJob
      email = @user.emails.order(:created_at).last
    end

    # Verify email was fetched before enrichment
    assert_not_nil email, "Email should be created by FetchMicrosoftEmailJob"

    # Step 3: Process the enrichment job with VCR cassette for Anthropic API
    VCR.use_cassette("microsoft_email_enrichment") do
      perform_enqueued_jobs only: EnrichEmailJob
    end

    # Verify email was created
    assert_equal initial_email_count + 1, @user.emails.count
    email = @user.emails.order(:created_at).last

    assert_equal @graph_id, email.graph_id
    assert_equal "graph", email.source_type
    assert_equal "Aquí va un nuevo correo", email.subject
    assert_equal "eliocapella@gmail.com", email.from_address["email"]
    assert_includes email.body_html, "Por favor envía la factura del pedido 22211"

    # Verify contacts were created (at least 1 contact from email)
    # The LLM extracts 2 contacts but one might already exist or be filtered
    sender_contact = @user.contacts.find_by(email: "eliocapella@gmail.com")
    assert_not_nil sender_contact, "Sender contact should be created"
    assert_equal "Elio Capella", sender_contact.name

    # Verify email is linked to sender contact
    email.reload
    assert_equal sender_contact, email.contact

    # Verify task was created
    assert_equal initial_task_count + 1, @user.tasks.count
    task = @user.tasks.find_by(name: "Enviar factura pedido 22211")

    assert_not_nil task, "Task should be created"
    assert_includes task.description, "financiero"
    assert_equal sender_contact, task.contact
  end

  test "webhook validation token response" do
    post webhooks_microsoft_url, params: { validationToken: "test-validation-token" }

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_equal "test-validation-token", response.body
  end

  test "webhook rejects invalid client state" do
    notification = {
      value: [ {
        subscriptionId: @subscription.subscription_id,
        clientState: "invalid-state",
        resourceData: { id: @graph_id }
      } ]
    }

    assert_no_enqueued_jobs do
      post webhooks_microsoft_url, params: notification, as: :json
    end

    assert_response :accepted
  end

  test "webhook ignores unknown subscription" do
    notification = {
      value: [ {
        subscriptionId: "unknown-subscription-id",
        clientState: "some-state",
        resourceData: { id: @graph_id }
      } ]
    }

    assert_no_enqueued_jobs do
      post webhooks_microsoft_url, params: notification, as: :json
    end

    assert_response :accepted
  end

  test "skips duplicate emails by graph_id" do
    # Create existing email with same graph_id
    @user.emails.create!(
      graph_id: @graph_id,
      source_type: "graph",
      subject: "Existing email",
      sent_at: Time.current,
      from_address: { "email" => "test@test.com" },
      to_addresses: []
    )

    initial_email_count = @user.emails.count

    notification = {
      value: [ {
        subscriptionId: @subscription.subscription_id,
        clientState: @subscription.client_state,
        resourceData: { id: @graph_id }
      } ]
    }

    post webhooks_microsoft_url, params: notification, as: :json
    assert_response :accepted

    VCR.use_cassette("microsoft_graph_fetch_email") do
      perform_enqueued_jobs only: FetchMicrosoftEmailJob
    end

    # No new email should be created
    assert_equal initial_email_count, @user.emails.count
  end
end
