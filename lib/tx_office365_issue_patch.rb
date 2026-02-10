module TxOffice365IssuePatch
  def self.included(base)
    base.class_eval do
      # SharePoint URL 추출 및 저장 콜백
      before_save :extract_and_cache_sharepoint_guid
      after_save :save_cached_sharepoint_guid
    end
  end

  # description이 변경되었을 때 SharePoint URL 추출
  def extract_and_cache_sharepoint_guid
    # description이 변경되지 않았으면 스킵
    return unless description_changed?

    # 훅 메소드 호출 (새 이슈이거나 description이 변경된 경우)
    TxOffice365Hooks.extract_and_store_sharepoint_guid(self)
  end

  # 새 이슈가 저장된 후 pending GUID 저장
  def save_cached_sharepoint_guid
    TxOffice365Hooks.save_pending_guid(self) if id
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

  # 원본 SharePoint URL 조회
  def sharepoint_source_url
    data = sharepoint_data
    return nil unless data.is_a?(Hash)
    data['source_url']
  end

  # SharePoint 파일 타입 조회
  def sharepoint_file_type
    data = sharepoint_data
    return nil unless data.is_a?(Hash)
    data['file_type']
  end

  # Embed 지원 여부 확인
  # Excel, PowerPoint만 완전히 지원
  # Word, PDF는 제한적이거나 미지원
  def sharepoint_supports_embed?
    file_type = sharepoint_file_type
    return false unless file_type

    # Excel, PowerPoint만 embed 완전 지원
    ['excel', 'powerpoint'].include?(file_type)
  end

  # 이슈에 연결된 SharePoint Embed URL 생성
  # site_url: 기본 사이트 URL (예: "https://supercreative.sharepoint.com")
  #           OneDrive URL의 경우 원본 URL에서 자동 추출하므로 무시됨
  def sharepoint_embed_url(site_url: nil)
    guid = sharepoint_guid
    return nil unless guid

    # 원본 URL이 있으면 해당 URL의 도메인과 경로 사용
    source_url = sharepoint_source_url
    if source_url
      base_url = extract_base_url_from_source(source_url)
    else
      # 하위 호환성: 원본 URL이 없으면 기존 방식 사용
      site_id = sharepoint_site_id
      base_url = site_id ? "#{site_url}/sites/#{site_id}" : site_url
    end

    return nil unless base_url

    # SharePoint iframe용 URL 형식
    # sourcedoc는 URL 인코딩된 중괄호 안에 GUID 포함: %7B{GUID}%7D
    encoded_guid = "%7B#{guid}%7D"
    "#{base_url}/_layouts/15/Doc.aspx?sourcedoc=#{encoded_guid}&action=embedview"
  end

  private

  # 원본 URL에서 base URL 추출
  # 예시:
  # - https://supercreative.sharepoint.com/:p:/g/... → https://supercreative.sharepoint.com
  # - https://supercreative.sharepoint.com/:p:/s/SiteName/... → https://supercreative.sharepoint.com/sites/SiteName
  # - https://supercreative-my.sharepoint.com/:w:/g/personal/user/... → https://supercreative-my.sharepoint.com/personal/user
  def extract_base_url_from_source(source_url)
    require 'uri'
    uri = URI.parse(source_url)

    # 기본 도메인
    base = "#{uri.scheme}://#{uri.host}"

    # 경로 분석
    path = uri.path

    # OneDrive Personal: /personal/사용자명/
    if match = path.match(%r{/personal/([^/]+)})
      return "#{base}/personal/#{match[1]}"
    end

    # 팀 사이트 (/:x:/s/SiteName/ 형식)
    if match = path.match(%r{/:([a-z]):/s/([^/]+)})
      return "#{base}/sites/#{match[2]}"
    end

    # 팀 사이트 (/:x:/r/sites/SiteName/ 형식)
    if match = path.match(%r{/:([a-z]):/r/sites/([^/]+)})
      return "#{base}/sites/#{match[2]}"
    end

    # 일반 사이트 (/sites/SiteName/ 형식)
    if match = path.match(%r{/sites/([^/]+)})
      return "#{base}/sites/#{match[1]}"
    end

    # 기타: 도메인만 반환
    base
  rescue => e
    Rails.logger.error("Base URL 추출 실패: #{e.message}")
    nil
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

