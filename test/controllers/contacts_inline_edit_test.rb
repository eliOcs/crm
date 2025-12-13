require "test_helper"

class ContactsInlineEditTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contact = contacts(:one)
  end

  test "update name via turbo stream" do
    patch contact_path(@contact), as: :turbo_stream, params: { name: "Updated Name" }

    assert_response :success
    assert_equal "Updated Name", @contact.reload.name

    # Verify audit log was created
    audit_log = @contact.audit_logs.last
    assert_equal "update", audit_log.action
    assert_equal "Updated name via UI", audit_log.message
    assert_equal "ui", audit_log.metadata["source"]
    assert_equal({ "name" => { "from" => "John Doe", "to" => "Updated Name" } }, audit_log.field_changes)
  end

  test "update job_role via turbo stream" do
    patch contact_path(@contact), as: :turbo_stream, params: { job_role: "Senior Developer" }

    assert_response :success
    assert_equal "Senior Developer", @contact.reload.job_role

    audit_log = @contact.audit_logs.last
    assert_equal "job_role", audit_log.field_changes.keys.first
  end

  test "update department via turbo stream" do
    patch contact_path(@contact), as: :turbo_stream, params: { department: "Engineering" }

    assert_response :success
    assert_equal "Engineering", @contact.reload.department
  end

  test "update phone_numbers parses comma-separated values" do
    patch contact_path(@contact), as: :turbo_stream, params: { phone_numbers: "+1-555-1234, +1-555-5678" }

    assert_response :success
    assert_equal [ "+1-555-1234", "+1-555-5678" ], @contact.reload.phone_numbers
  end

  test "update with empty value clears field" do
    @contact.update!(job_role: "Developer")

    patch contact_path(@contact), as: :turbo_stream, params: { job_role: "" }

    assert_response :success
    assert_equal "", @contact.reload.job_role
  end

  test "update rejects invalid field" do
    patch contact_path(@contact), as: :json, params: { invalid_field: "value" }

    assert_response :unprocessable_entity
    response_json = JSON.parse(response.body)
    assert_equal "Invalid field", response_json["error"]
  end

  test "turbo stream response prepends audit log entry" do
    patch contact_path(@contact), as: :turbo_stream, params: { name: "New Name" }

    assert_response :success
    assert_match "turbo-stream", response.content_type
    assert_match "prepend", response.body
    assert_match "audit_log_entries", response.body
  end

  test "cannot update other user's contact" do
    other_contact = contacts(:two)

    patch contact_path(other_contact), as: :turbo_stream, params: { name: "Hacked" }

    assert_response :not_found
    assert_equal "Jane Smith", other_contact.reload.name
  end
end
