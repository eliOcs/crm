require "test_helper"

class CompaniesInlineEditTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @company = companies(:one)
  end

  test "update legal_name via turbo stream" do
    patch company_path(@company), as: :turbo_stream, params: { legal_name: "New Legal Name Inc" }

    assert_response :success
    assert_equal "New Legal Name Inc", @company.reload.legal_name

    audit_log = @company.audit_logs.last
    assert_equal "update", audit_log.action
    assert_equal "Updated legal name via UI", audit_log.message
    assert_equal "ui", audit_log.metadata["source"]
  end

  test "update commercial_name via turbo stream" do
    patch company_path(@company), as: :turbo_stream, params: { commercial_name: "ACME" }

    assert_response :success
    assert_equal "ACME", @company.reload.commercial_name
  end

  test "update domain via turbo stream" do
    patch company_path(@company), as: :turbo_stream, params: { domain: "newdomain.com" }

    assert_response :success
    assert_equal "newdomain.com", @company.reload.domain
  end

  test "update location via turbo stream" do
    patch company_path(@company), as: :turbo_stream, params: { location: "New York, USA" }

    assert_response :success
    assert_equal "New York, USA", @company.reload.location
  end

  test "update website via turbo stream" do
    patch company_path(@company), as: :turbo_stream, params: { website: "https://newsite.com" }

    assert_response :success
    assert_equal "https://newsite.com", @company.reload.website
  end

  test "update vat_id via turbo stream" do
    patch company_path(@company), as: :turbo_stream, params: { vat_id: "US123456789" }

    assert_response :success
    assert_equal "US123456789", @company.reload.vat_id
  end

  test "update rejects invalid field" do
    patch company_path(@company), as: :json, params: { invalid_field: "value" }

    assert_response :unprocessable_entity
  end

  test "turbo stream response prepends audit log entry" do
    patch company_path(@company), as: :turbo_stream, params: { legal_name: "Updated Inc" }

    assert_response :success
    assert_match "turbo-stream", response.content_type
    assert_match "prepend", response.body
    assert_match "audit_log_entries", response.body
  end

  test "cannot update other user's company" do
    other_company = companies(:two)

    patch company_path(other_company), as: :turbo_stream, params: { legal_name: "Hacked" }

    assert_response :not_found
    assert_equal "Globex Corp", other_company.reload.legal_name
  end
end
