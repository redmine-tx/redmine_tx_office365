module TxOffice365IssuePatch
  def self.included(base)
    base.class_eval do
      # SharePoint 관련 헬퍼 메소드만 추가
    end
  end

  # 이슈에 연결된 SharePoint 문서 데이터 조회 (GUID와 사이트 ID 포함)
  def sharepoint_data
    return nil unless id
    data = Office365Storage.get("DOC.#{id}") rescue nil
    return nil unless data
    
    # 기존 호환성: 문자열(GUID만)인 경우 Hash로 변환
    if data.is_a?(String)
      { 'guid' => data }
    else
      data
    end
  end

  # 이슈에 연결된 SharePoint 문서의 GUID 조회 (하위 호환성)
  def sharepoint_guid
    data = sharepoint_data
    return nil unless data
    data.is_a?(Hash) ? data['guid'] : data
  end

  # 이슈에 연결된 SharePoint 문서의 사이트 ID 조회
  def sharepoint_site_id
    data = sharepoint_data
    return nil unless data.is_a?(Hash)
    data['site_id']
  end

  # 이슈에 연결된 SharePoint 문서가 있는지 확인
  def has_sharepoint_document?
    sharepoint_guid.present?
  rescue
    false
  end

  # 이슈에 연결된 SharePoint Embed URL 생성
  # site_url: 예) "https://supercreative.sharepoint.com"
  def sharepoint_embed_url(site_url:)
    guid = sharepoint_guid
    return nil unless guid
    
    # 사이트 ID가 있으면 URL에 포함
    site_id = sharepoint_site_id
    base_url = site_id ? "#{site_url}/sites/#{site_id}" : site_url
    
    # SharePoint iframe용 URL 형식
    # sourcedoc는 URL 인코딩된 중괄호 안에 GUID 포함: %7B{GUID}%7D
    encoded_guid = "%7B#{guid}%7D"
    "#{base_url}/_layouts/15/Doc.aspx?sourcedoc=#{encoded_guid}&action=embedview"
  end

  # 저장된 SharePoint GUID 삭제
  def clear_sharepoint_guid
    return unless id
    Office365Storage.delete("DOC.#{id}")
  rescue
    false
  end
end

# Issue 모델에 패치 적용
if defined?(Issue)
  Issue.send(:include, TxOffice365IssuePatch) unless Issue.included_modules.include?(TxOffice365IssuePatch)
end

# Rails 환경이 준비되면 다시 한번 확인
Rails.application.config.to_prepare do
  if defined?(Issue)
    Issue.send(:include, TxOffice365IssuePatch) unless Issue.included_modules.include?(TxOffice365IssuePatch)
  end
end

