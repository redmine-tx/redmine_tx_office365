require 'redmine'

Redmine::Plugin.register :redmine_tx_office365 do
  name 'Redmine Tx Office365 plugin'
  author 'KiHyun Kang'
  description 'Microsoft Graph API integration for SharePoint and Outlook Calendar'
  version '0.0.1'
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'

  settings default: {
    'tenant_id' => '',
    'client_id' => '',
    'client_secret' => '',
    'sharepoint_site_url' => 'https://supercreative.sharepoint.com'
  }, partial: 'settings/redmine_tx_office365'
end

Rails.application.config.after_initialize do
  # Controller Hooks 로드
  require_relative 'lib/tx_office365_hooks'

  # Issue 헬퍼 메소드 패치 로드
  require_relative 'lib/tx_office365_issue_patch'
end
