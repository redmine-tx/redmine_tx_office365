require File.expand_path('../../test_helper', __FILE__)

class TxOffice365IssuePatchTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :issue_statuses, :issue_categories, :enumerations,
           :issues, :custom_fields, :custom_values

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    Office365Storage.delete_all
  end

  def teardown
    Office365Storage.delete_all
  end

  test "should have sharepoint helper methods" do
    issue = Issue.find(1)
    assert_respond_to issue, :sharepoint_guid
    assert_respond_to issue, :has_sharepoint_document?
    assert_respond_to issue, :sharepoint_embed_url
    assert_respond_to issue, :clear_sharepoint_guid
  end

  test "should return nil for sharepoint_guid when not set" do
    issue = Issue.find(1)
    assert_nil issue.sharepoint_guid
  end

  test "should return false for has_sharepoint_document? when not set" do
    issue = Issue.find(1)
    assert_equal false, issue.has_sharepoint_document?
  end

  test "should return sharepoint_guid when manually set" do
    issue = Issue.find(1)
    test_guid = "1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF"
    
    Office365Storage.set("DOC.#{issue.id}", test_guid)
    assert_equal test_guid, issue.sharepoint_guid
  end

  test "should return true for has_sharepoint_document? when guid is set" do
    issue = Issue.find(1)
    test_guid = "1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF"
    
    Office365Storage.set("DOC.#{issue.id}", test_guid)
    assert_equal true, issue.has_sharepoint_document?
  end

  test "should generate sharepoint_embed_url correctly" do
    issue = Issue.find(1)
    test_guid = "1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF"
    site_url = "https://supercreative.sharepoint.com/sites/TestSite"
    
    Office365Storage.set("DOC.#{issue.id}", test_guid)
    
    expected_url = "#{site_url}/_layouts/15/embed.aspx?uniqueid=#{test_guid}"
    assert_equal expected_url, issue.sharepoint_embed_url(site_url: site_url)
  end

  test "should return nil for sharepoint_embed_url when guid not set" do
    issue = Issue.find(1)
    assert_nil issue.sharepoint_embed_url(site_url: "https://example.com")
  end

  test "should clear sharepoint guid" do
    issue = Issue.find(1)
    test_guid = "1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF"
    
    Office365Storage.set("DOC.#{issue.id}", test_guid)
    assert_equal test_guid, issue.sharepoint_guid
    
    issue.clear_sharepoint_guid
    assert_nil issue.sharepoint_guid
  end

end

