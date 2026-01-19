require File.expand_path('../../test_helper', __FILE__)

class TxOffice365HooksTest < ActiveSupport::TestCase
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

  test "should extract sharepoint url pattern" do
    description = "Check this document: https://supercreative.sharepoint.com/:p:/g/IQB1z6Udy4jnSZWW5PSr3HbPAULbh0gcOxAePDOuglzWHcE?e=I7OJwS"
    
    urls = description.scan(%r{https://[^/\s]+\.sharepoint\.com/[^\s]+})
    assert_equal 1, urls.length
    assert_includes urls.first, 'supercreative.sharepoint.com'
  end

  test "should extract multiple sharepoint urls" do
    description = <<~DESC
      First doc: https://supercreative.sharepoint.com/:p:/g/ABC123
      Second doc: https://example.sharepoint.com/:f:/r/DEF456
      Third: https://another.sharepoint.com/sites/test/documents
    DESC
    
    urls = description.scan(%r{https://[^/\s]+\.sharepoint\.com/[^\s]+})
    assert_equal 3, urls.length
  end

  test "should not extract non-sharepoint urls" do
    description = "Check https://google.com and https://github.com"
    
    urls = description.scan(%r{https://[^/\s]+\.sharepoint\.com/[^\s]+})
    assert_equal 0, urls.length
  end

  test "should handle nil description" do
    issue = Issue.new(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test Issue',
      description: nil
    )
    
    assert_nothing_raised do
      TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)
    end
  end

  test "should handle empty description" do
    issue = Issue.new(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test Issue',
      description: ""
    )
    
    assert_nothing_raised do
      TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)
    end
  end

  test "should handle description without sharepoint urls" do
    issue = Issue.new(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test Issue',
      description: "This is a simple description without any SharePoint URLs"
    )
    
    assert_nothing_raised do
      TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)
    end
    
    # GUID가 저장되지 않아야 함
    assert_nil issue.instance_variable_get(:@pending_sharepoint_guid)
  end

  test "should store pending guid for new issue" do
    skip "Requires TxGraph API to be properly configured"
    
    issue = Issue.new(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test Issue',
      description: "Document: https://supercreative.sharepoint.com/:p:/g/test123"
    )
    
    # Mock TxGraph::SharePoint::LinkConverter
    converter = Minitest::Mock.new
    converter.expect(:get_guid_from_url, 'TEST-GUID-123', [String])
    
    TxGraph::SharePoint::LinkConverter.stub(:new, converter) do
      TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)
      
      # 새 이슈이므로 pending GUID가 설정되어야 함
      assert_equal 'TEST-GUID-123', issue.instance_variable_get(:@pending_sharepoint_guid)
    end
    
    converter.verify
  end

  test "should save guid for existing issue" do
    skip "Requires TxGraph API to be properly configured"
    
    issue = Issue.find(1)
    issue.description = "Document: https://supercreative.sharepoint.com/:p:/g/test123"
    
    # Mock TxGraph::SharePoint::LinkConverter
    converter = Minitest::Mock.new
    converter.expect(:get_guid_from_url, 'TEST-GUID-AAA', [String])
    
    TxGraph::SharePoint::LinkConverter.stub(:new, converter) do
      TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)
      
      # 기존 이슈이므로 바로 저장되어야 함
      assert_equal 'TEST-GUID-AAA', Office365Storage.get("DOC.#{issue.id}")
    end
    
    converter.verify
  end

  test "should save pending guid" do
    issue = Issue.find(1)
    issue.instance_variable_set(:@pending_sharepoint_guid, 'PENDING-GUID-BBB')
    
    TxOffice365Hooks.save_pending_guid(issue)
    
    # pending GUID가 저장되어야 함
    assert_equal 'PENDING-GUID-BBB', Office365Storage.get("DOC.#{issue.id}")
    
    # pending GUID가 제거되어야 함
    assert_nil issue.instance_variable_get(:@pending_sharepoint_guid)
  end
end

