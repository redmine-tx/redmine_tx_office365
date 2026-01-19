module Office365Helper
  # SharePoint 문서 임베드 iframe 생성
  # 
  # @param issue [Issue] 이슈 객체
  # @param site_url [String] SharePoint 사이트 URL (예: "https://supercreative.sharepoint.com/sites/YourSite")
  # @param options [Hash] iframe 옵션
  #   - width: iframe 너비 (기본: "100%")
  #   - height: iframe 높이 (기본: "600px")
  #   - frameborder: 테두리 (기본: "0")
  #   - class: CSS 클래스
  def sharepoint_document_iframe(issue, site_url:, **options)
    return nil unless issue.has_sharepoint_document?
    
    embed_url = issue.sharepoint_embed_url(site_url: site_url)
    return nil unless embed_url
    
    iframe_options = {
      width: options[:width] || '100%',
      height: options[:height] || '600px',
      frameborder: options[:frameborder] || '0',
      class: options[:class]
    }.compact
    
    content_tag(:iframe, '', { src: embed_url }.merge(iframe_options))
  end
  
  # SharePoint 문서 아이콘 표시
  # 
  # @param issue [Issue] 이슈 객체
  # @param options [Hash] 아이콘 옵션
  #   - title: 툴팁 텍스트 (기본: "SharePoint 문서 연결됨")
  #   - class: CSS 클래스 (기본: "icon icon-file")
  def sharepoint_document_icon(issue, **options)
    return nil unless issue.has_sharepoint_document?
    
    title = options[:title] || l(:label_sharepoint_document_attached, default: 'SharePoint 문서 연결됨')
    css_class = options[:class] || 'icon icon-file'
    
    content_tag(:span, '', class: css_class, title: title)
  end
  
  # SharePoint 문서 정보 박스 렌더링
  # 
  # @param issue [Issue] 이슈 객체
  # @param site_url [String] SharePoint 사이트 URL
  # @param options [Hash] 박스 옵션
  #   - show_guid: GUID 표시 여부 (기본: false)
  #   - show_iframe: iframe 표시 여부 (기본: true)
  #   - iframe_height: iframe 높이 (기본: "600px")
  def sharepoint_document_box(issue, site_url:, **options)
    return nil unless issue.has_sharepoint_document?
    
    show_guid = options.fetch(:show_guid, false)
    show_iframe = options.fetch(:show_iframe, true)
    iframe_height = options.fetch(:iframe_height, '600px')
    
    content_tag(:div, class: 'box sharepoint-document-box') do
      html = content_tag(:h3, l(:label_sharepoint_document, default: '연결된 SharePoint 문서'))
      
      if show_iframe
        html += content_tag(:div, class: 'sharepoint-embed') do
          sharepoint_document_iframe(issue, site_url: site_url, height: iframe_height)
        end
      end
      
      if show_guid
        html += content_tag(:p) do
          content_tag(:strong, "#{l(:label_document_guid, default: '문서 GUID')}: ") +
          content_tag(:code, issue.sharepoint_guid)
        end
      end
      
      html
    end
  end
  
  # SharePoint 문서 링크 생성
  # 
  # @param issue [Issue] 이슈 객체
  # @param site_url [String] SharePoint 사이트 URL
  # @param text [String] 링크 텍스트 (기본: "SharePoint에서 열기")
  def sharepoint_document_link(issue, site_url:, text: nil)
    return nil unless issue.has_sharepoint_document?
    
    embed_url = issue.sharepoint_embed_url(site_url: site_url)
    return nil unless embed_url
    
    link_text = text || l(:label_open_in_sharepoint, default: 'SharePoint에서 열기')
    link_to link_text, embed_url, target: '_blank', class: 'icon icon-file'
  end
end

