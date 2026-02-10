require_relative 'tx_graph'

class TxOffice365Hooks < Redmine::Hook::ViewListener
  include Office365Helper
  
  # 이슈 상세 페이지 - '설명' 헤더 바로 다음에 표시 (JavaScript로 위치 이동)
  def view_issues_show_description_bottom(context = {})
    issue = context[:issue]
    return '' unless issue&.has_sharepoint_document?
    
    # 플러그인 설정에서 SharePoint 사이트 URL 가져오기
    site_url = get_sharepoint_site_url
    return '' unless site_url.present?
    
    context[:controller].send(:render_to_string, {
      partial: 'hooks/office365/sharepoint_document',
      locals: { issue: issue, site_url: site_url }
    })
  end
  
  private
  
  def get_sharepoint_site_url
    # 플러그인 설정에서 사이트 URL을 가져오거나, 기본값 사용
    if defined?(Setting) && Setting.respond_to?(:plugin_redmine_tx_office365)
      settings = Setting.plugin_redmine_tx_office365 || {}
      settings['sharepoint_site_url'] || 'https://supercreative.sharepoint.com'
    else
      'https://supercreative.sharepoint.com'
    end
  end
  # 컨트롤러 훅은 Model callback으로 대체되었습니다.
  # Model callback (tx_office365_issue_patch.rb)이 모든 저장 경로를 커버합니다:
  # - 웹 UI 업데이트
  # - API 업데이트
  # - Console/Rake task
  # - 일괄 업데이트
  #
  # 따라서 컨트롤러 훅은 더 이상 필요하지 않으며, 중복 실행을 방지하기 위해 제거되었습니다.

  # 클래스 메소드로 변경하여 콘솔에서 직접 호출 가능하게 함
  class << self
    # 테스트용: 콘솔에서 직접 호출 가능
    # 사용법: TxOffice365Hooks.extract_and_store_sharepoint_guid(Issue.find(123))
    def extract_and_store_sharepoint_guid(issue)
      return unless issue
      Rails.logger.info("Office365: extract_and_store_sharepoint_guid 시작 - Issue ##{issue.id || 'NEW'}")
      return unless issue.description.present?

      # SharePoint URL 패턴 (*.sharepoint.com 도메인)
      sharepoint_urls = issue.description.scan(%r{https://[^/\s]+\.sharepoint\.com/[^\s]+})
      Rails.logger.info("Office365: SharePoint URL #{sharepoint_urls.count}개 발견")
      
      # URL이 없고 기존에 저장된 데이터가 있으면 삭제
      if sharepoint_urls.empty?
        if issue.id
          storage_key = "DOC.#{issue.id}"
          existing_data = Office365Storage.get(storage_key)
          if existing_data
            Office365Storage.delete(storage_key)
            Rails.logger.info("Office365: Issue ##{issue.id}에서 SharePoint URL이 제거되어 데이터 삭제됨")
          end
        end
        return
      end

      begin
        converter = TxGraph::SharePoint::LinkConverter.new
        
        # 첫 번째 URL만 처리 (여러 개가 있어도)
        url = sharepoint_urls.first
        
        # URL에서 사이트 ID 추출 (예: /sites/EpicSeven/)
        site_id = extract_site_id_from_url(url)
        
        # 이미 저장된 데이터 확인
        storage_key = "DOC.#{issue.id}" if issue.id
        existing_data = storage_key ? Office365Storage.get(storage_key) : nil
        
        # 기존 데이터가 문자열(GUID만)인 경우 호환성 처리
        existing_guid = if existing_data.is_a?(Hash)
          existing_data['guid']
        elsif existing_data.is_a?(String)
          existing_data
        else
          nil
        end
        
        # 기존 site_id 추출
        existing_site_id = existing_data.is_a?(Hash) ? existing_data['site_id'] : nil

        # GUID 추출 (1. URL에서 직접 추출 시도, 2. Graph API 호출)
        guid = extract_guid_from_url(url) || converter.get_guid_from_url(url)
        
        if guid
          # 새로운 이슈이거나 GUID 또는 site_id가 변경된 경우 저장
          if !existing_guid || existing_guid != guid || existing_site_id != site_id
            # GUID, 사이트 ID, 원본 URL, 파일 타입 정보를 JSON으로 저장
            data = { 'guid' => guid }
            data['site_id'] = site_id if site_id
            data['source_url'] = url
            data['file_type'] = extract_file_type_from_url(url)
            
            # 이슈가 아직 저장되지 않은 경우 (새 이슈)는 after_save 콜백 등록
            if issue.id
              save_sharepoint_data(issue, data)
            else
              # 새 이슈인 경우, 임시로 저장할 데이터를 인스턴스 변수에 보관
              issue.instance_variable_set(:@pending_sharepoint_data, data)
            end
            
            site_info = site_id ? " (사이트: #{site_id})" : ""
            Rails.logger.info("Office365: Issue ##{issue.id || 'NEW'}에서 SharePoint GUID 추출됨: #{guid}#{site_info}")
          end
        else
          Rails.logger.warn("Office365: Issue ##{issue.id || 'NEW'}에서 SharePoint URL의 GUID 추출 실패: #{url}")
        end
      rescue => e
        Rails.logger.error("Office365: Issue ##{issue.id || 'NEW'} SharePoint GUID 추출 중 오류: #{e.class} - #{e.message}")
      end
    end

    # URL에서 GUID 직접 추출 (sourcedoc 파라미터 또는 URL 경로에서)
    # 지원하는 형식:
    # 1. ?sourcedoc=%7BGUID%7D 또는 ?sourcedoc={GUID} (Office Online 에디터 링크)
    # 2. OneNote URL의 wd=target(...)에 포함된 GUID
    def extract_guid_from_url(url)
      require 'cgi'
      require 'uri'

      begin
        uri = URI.parse(url)

        # 1. sourcedoc 쿼리 파라미터에서 GUID 추출
        if uri.query
          params = CGI.parse(uri.query)
          if params['sourcedoc'] && params['sourcedoc'].any?
            sourcedoc = params['sourcedoc'].first
            # {GUID} 형식에서 GUID만 추출
            if match = sourcedoc.match(/\{?([a-fA-F0-9\-]{36})\}?/)
              return match[1].upcase
            end
          end

          # 2. OneNote URL의 wd=target(...)에 포함된 GUID 추출
          if params['wd'] && params['wd'].any?
            wd_param = params['wd'].first
            # target(...|GUID|...) 형식에서 GUID 추출
            guids = wd_param.scan(/([a-fA-F0-9\-]{36})/)
            if guids.any?
              # 첫 번째 GUID 반환 (OneNote 페이지 GUID)
              return guids.first.first.upcase
            end
          end
        end
      rescue => e
        Rails.logger.debug("URL 파싱 중 오류 (무시됨): #{e.message}")
      end

      nil
    end

    # URL에서 파일 타입 추출
    # SharePoint 공유 링크 형식: /:타입:/...
    # - :x: = Excel
    # - :p: = PowerPoint
    # - :w: = Word
    # - :b: = PDF
    # - :u: = 일반 파일
    # - :f: = 폴더
    def extract_file_type_from_url(url)
      if match = url.match(%r{/:([a-z]):/})
        case match[1]
        when 'x' then 'excel'
        when 'p' then 'powerpoint'
        when 'w' then 'word'
        when 'b' then 'pdf'
        when 'f' then 'folder'
        when 'u' then 'file'
        else match[1]
        end
      else
        nil
      end
    end

    # URL에서 사이트 ID 추출
    # 지원하는 형식:
    # 1. /:x:/s/SITE_ID/ 또는 /:p:/s/SITE_ID/ 또는 /:f:/s/SITE_ID/ 등 (모든 알파벳 접두사)
    # 2. /:p:/r/sites/SITE_ID/ 또는 /:f:/r/sites/SITE_ID/ 등
    # 3. /sites/SITE_ID/ (예: https://supercreative.sharepoint.com/sites/EpicSeven/...)
    def extract_site_id_from_url(url)
      # 패턴 1: /:x:/s/SITE_ID/ 또는 /:p:/s/SITE_ID/ 등 (모든 알파벳 접두사 허용)
      match = url.match(%r{/:([a-z]):/s/([^/?]+)})
      return match[2] if match
      
      # 패턴 2: /:p:/r/sites/SITE_ID/ 또는 /:f:/r/sites/SITE_ID/ 등
      match = url.match(%r{/:([a-z]):/r/sites/([^/?]+)})
      return match[2] if match
      
      # 패턴 3: /sites/SITE_ID/
      match = url.match(%r{/sites/([^/?]+)})
      return match[1] if match
      
      nil
    end

    def save_sharepoint_data(issue, data)
      storage_key = "DOC.#{issue.id}"
      
      # description에 한글이 있으면 MySQL 인코딩 에러가 날 수 있으므로 ASCII만 사용
      begin
        Office365Storage.set(
          storage_key,
          data,
          description: "Issue ##{issue.id}"
        )
      rescue => e
        # description 저장 실패 시 description 없이 저장
        Rails.logger.warn("Office365: description 저장 실패, 데이터만 저장 - #{e.message}")
        Office365Storage.set(storage_key, data)
      end
    end

    # 하위 호환성을 위한 메소드 (기존 코드에서 사용 가능)
    def save_guid(issue, guid)
      save_sharepoint_data(issue, { 'guid' => guid })
    end

    def save_pending_guid(issue)
      return unless issue && issue.id
      
      # 임시로 보관된 데이터가 있으면 저장
      pending_data = issue.instance_variable_get(:@pending_sharepoint_data)
      if pending_data
        save_sharepoint_data(issue, pending_data)
        issue.instance_variable_set(:@pending_sharepoint_data, nil)
        site_info = pending_data['site_id'] ? " (사이트: #{pending_data['site_id']})" : ""
        Rails.logger.info("Office365: Issue ##{issue.id}에 SharePoint GUID 저장 완료: #{pending_data['guid']}#{site_info}")
      end
    end
  end

end

