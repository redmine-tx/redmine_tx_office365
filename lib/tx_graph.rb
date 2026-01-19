require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'cgi'
require 'thread'

module TxGraph
  module Auth
    # 토큰을 캐시하고, 만료 시각이 임박하면(기본 60초 이내) 자동으로 갱신해서 제공
    # 레드마인 멀티 프로세스 환경을 위해 Rails.cache를 사용하여 프로세스 간 토큰 공유
    class TokenManager
      DEFAULT_SCOPE = 'https://graph.microsoft.com/.default'
      CACHE_PREFIX = 'tx_graph_token'

      def initialize(tenant_id: nil, client_id: nil, client_secret: nil, scope: DEFAULT_SCOPE, refresh_skew: 60)
        # 레드마인 플러그인 설정에서 기본값 가져오기
        settings = get_plugin_settings
        
        @tenant_id = tenant_id || settings['tenant_id']
        @client_id = client_id || settings['client_id']
        @client_secret = client_secret || settings['client_secret']
        @scope = scope
        @refresh_skew = refresh_skew
        @mutex = Mutex.new # 프로세스 내 동시 요청 방지용
        @cache_key = "#{CACHE_PREFIX}:#{@tenant_id}:#{@client_id}"

        validate_credentials!
      end

      # 현재 토큰 반환(필요 시 자동 갱신). 실패하면 nil
      def token
        @mutex.synchronize do
          refresh_if_needed!
          get_cached_token
        end
      end

      # 현재 토큰의 남은 유효시간(초). 없으면 nil
      def expires_in
        @mutex.synchronize do
          expires_at = get_cached_expires_at
          return nil unless expires_at
          remaining = (expires_at - Time.now).to_i
          remaining < 0 ? 0 : remaining
        end
      end

      # 마지막 갱신 실패 이유(있으면 String)
      def last_error
        @mutex.synchronize { get_cached_error }
      end

      # 강제 갱신(401 발생 시 안전장치용). 성공 시 token(String), 실패 시 nil
      def force_refresh!
        @mutex.synchronize { refresh!(force: true) }
      end

      private

      def get_plugin_settings
        if defined?(Setting) && Setting.respond_to?(:plugin_redmine_tx_office365)
          Setting.plugin_redmine_tx_office365 || {}
        else
          {}
        end
      rescue
        {}
      end

      def validate_credentials!
        if @tenant_id.nil? || @tenant_id.to_s.strip.empty?
          raise ArgumentError, 'tenant_id가 설정되지 않았습니다. 플러그인 설정 또는 초기화 파라미터를 확인하세요.'
        end
        if @client_id.nil? || @client_id.to_s.strip.empty?
          raise ArgumentError, 'client_id가 설정되지 않았습니다. 플러그인 설정 또는 초기화 파라미터를 확인하세요.'
        end
        if @client_secret.nil? || @client_secret.to_s.strip.empty?
          raise ArgumentError, 'client_secret가 설정되지 않았습니다. 플러그인 설정 또는 초기화 파라미터를 확인하세요.'
        end
      end

      def get_cached_token
        cache_read("#{@cache_key}:token")
      end

      def get_cached_expires_at
        cache_read("#{@cache_key}:expires_at")
      end

      def get_cached_error
        cache_read("#{@cache_key}:error")
      end

      def set_cached_token(token, expires_at)
        # 토큰이 만료되기 전까지만 캐시에 유지
        ttl = expires_at ? [(expires_at - Time.now).to_i, 0].max : 3600
        cache_write("#{@cache_key}:token", token, expires_in: ttl)
        cache_write("#{@cache_key}:expires_at", expires_at, expires_in: ttl)
      end

      def set_cached_error(error)
        # 에러는 5분간만 캐시
        cache_write("#{@cache_key}:error", error, expires_in: 300)
      end

      def clear_cached_token
        cache_delete("#{@cache_key}:token")
        cache_delete("#{@cache_key}:expires_at")
      end

      def cache_read(key)
        Rails.cache.read(key) rescue nil
      end

      def cache_write(key, value, options = {})
        Rails.cache.write(key, value, options) rescue nil
      end

      def cache_delete(key)
        Rails.cache.delete(key) rescue nil
      end

      def refresh_if_needed!
        token = get_cached_token
        expires_at = get_cached_expires_at
        
        return refresh!(force: true) if token.nil? || expires_at.nil?

        # 만료 임박이면 갱신 (기본 60초 이내)
        if (expires_at - Time.now) <= @refresh_skew
          refresh!(force: true)
        end
      end

      def refresh!(force:)
        new_token, expires_in, err = fetch_access_token_or_error
        if new_token
          expires_at = expires_in ? (Time.now + expires_in) : (Time.now + 3600)
          set_cached_token(new_token, expires_at)
          cache_delete("#{@cache_key}:error")
          return new_token
        end

        set_cached_error(err)

        # 갱신 실패 시에도 기존 토큰이 아직 살아있으면(만료 전이면) 일단 반환
        cached_token = get_cached_token
        cached_expires_at = get_cached_expires_at
        if cached_token && cached_expires_at && (cached_expires_at > Time.now)
          Rails.logger.warn("토큰 갱신 실패(기존 토큰 유지): #{err}")
          return cached_token
        end

        clear_cached_token
        nil
      rescue => e
        error_msg = "#{e.class}: #{e.message}"
        set_cached_error(error_msg)
        
        cached_token = get_cached_token
        cached_expires_at = get_cached_expires_at
        clear_cached_token unless cached_token && cached_expires_at && (cached_expires_at > Time.now)
        nil
      end

      # 성공: [access_token(String), expires_in(Integer|nil), nil]
      # 실패: [nil, nil, error(String)]
      def fetch_access_token_or_error
        url = URI("https://login.microsoftonline.com/#{@tenant_id}/oauth2/v2.0/token")

        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(url)
        request.set_form_data(
          'client_id' => @client_id,
          'scope' => @scope,
          'client_secret' => @client_secret,
          'grant_type' => 'client_credentials'
        )

        response = http.request(request)
        if response.code == '200'
          json_response = JSON.parse(response.body)
          expires_in = json_response['expires_in']
          expires_in = expires_in.to_i if expires_in
          return [json_response['access_token'], expires_in, nil]
        end

        [nil, nil, response.body]
      rescue => e
        [nil, nil, "#{e.class}: #{e.message}"]
      end
    end
  end

  module Http
    class Error < StandardError
      attr_reader :status, :body

      def initialize(message, status:, body:)
        super(message)
        @status = status
        @body = body
      end
    end

    # Bearer 토큰 기반의 간단한 Graph HTTP 클라이언트
    class Client
      def initialize(access_token: nil, token_manager: nil, base_url: 'https://graph.microsoft.com/v1.0')
        # token_manager가 없으면 플러그인 설정으로 자동 생성
        @token_manager = token_manager || (access_token.nil? ? TxGraph::Auth::TokenManager.new : nil)
        @access_token = access_token
        @base_url = base_url
      end

      def set_access_token(access_token)
        @access_token = access_token
      end

      def get(path, headers: {})
        uri = URI.join(@base_url + '/', path.sub(%r{^/}, ''))
        do_request(label: 'GET') do
          request = Net::HTTP::Get.new(uri)
          apply_default_headers!(request, headers)
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
        end
      rescue => e
        # 호출자가 예외로 중단되지 않도록 에러를 "가짜 status"로 내려줍니다.
        ['EXCEPTION', "#{e.class}: #{e.message}"]
      end

      def post(path, json_body:, headers: {}, label: nil)
        uri = URI.join(@base_url + '/', path.sub(%r{^/}, ''))
        do_request(label: label || 'POST') do
          request = Net::HTTP::Post.new(uri)
          apply_default_headers!(request, headers)
          request.body = JSON.generate(json_body)
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
        end
      rescue => e
        ['EXCEPTION', "#{e.class}: #{e.message}"]
      end

      def delete(path, headers: {}, label: nil)
        uri = URI.join(@base_url + '/', path.sub(%r{^/}, ''))
        do_request(label: label || 'DELETE') do
          request = Net::HTTP::Delete.new(uri)
          apply_default_headers!(request, headers)
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
        end
      rescue => e
        ['EXCEPTION', "#{e.class}: #{e.message}"]
      end

      private

      def current_access_token
        return @token_manager.token if @token_manager
        @access_token
      end

      def do_request(label:)
        response = yield
        code = response.code
        body = response.body

        # 최후 안전장치: 401이면 토큰 강제 갱신 후 1회 재시도
        if code == '401' && @token_manager
          Rails.logger.warn("401 Unauthorized 감지(#{label}): 토큰 강제 갱신 후 1회 재시도합니다.")
          @token_manager.force_refresh!
          response = yield
          code = response.code
          body = response.body

          if code == '401' || code == '403'
            details = summarize_graph_error(body)
            reason = code == '401' ? '인증 실패(만료/잘못된 토큰/테넌트 불일치 등)' : '권한 부족/정책 차단(Admin consent/Access Policy 등)'
            Rails.logger.error("재시도 실패(#{label}): #{code} - #{reason}#{details.empty? ? '' : ' - ' + details}")
          end
        end

        [code, body]
      rescue => e
        ['EXCEPTION', "#{e.class}: #{e.message}"]
      end

      def apply_default_headers!(request, headers)
        token = current_access_token
        if token
          request['Authorization'] = "Bearer #{token}"
        else
          Rails.logger.error('Access Token이 없어 Authorization 헤더를 설정할 수 없습니다.')
        end
        request['Content-Type'] = 'application/json'
        headers.each { |k, v| request[k] = v }
      end

      # Graph 표준 에러 바디에서 핵심을 뽑아 한 줄로 요약
      def summarize_graph_error(body)
        return '' unless body && body.is_a?(String) && !body.empty?

        begin
          parsed = JSON.parse(body)
          err = parsed.is_a?(Hash) ? parsed['error'] : nil
          return '' unless err.is_a?(Hash)

          code = err['code']
          msg = err['message']
          inner = err['innerError'].is_a?(Hash) ? err['innerError'] : {}
          req_id = inner['request-id'] || inner['requestId']
          date = inner['date']

          parts = []
          parts << "code=#{code}" if code
          parts << "message=#{msg.inspect}" if msg
          parts << "request-id=#{req_id}" if req_id
          parts << "date=#{date}" if date
          parts.join(' ')
        rescue
          ''
        end
      end
    end
  end

  module Outlook
    module Calendar
      # 특정 사용자 일정(Event) 생성기
      # - Application permission(앱 권한) 기준: POST /users/{id}/events
      class EventService
        def initialize(access_token = nil, graph_base: 'https://graph.microsoft.com/v1.0', token_manager: nil)
          # token_manager가 없으면 플러그인 설정으로 자동 생성
          token_manager ||= TxGraph::Auth::TokenManager.new if access_token.nil?
          @client = TxGraph::Http::Client.new(access_token: access_token, token_manager: token_manager, base_url: graph_base)
        end

        # 성공 시 event(Hash) 반환, 실패 시 nil
        #
        # 리턴값 예시(일부 필드):
        #   {
        #     "id" => "AAMkAGI2TAAA=",            # delete_event에 넣을 event_id
        #     "subject" => "Redmine 자동 등록 일정",
        #     "start" => { "dateTime" => "2025-12-24T10:00:00.0000000", "timeZone" => "Asia/Seoul" },
        #     "end"   => { "dateTime" => "2025-12-24T10:30:00.0000000", "timeZone" => "Asia/Seoul" },
        #     "webLink" => "https://outlook.office.com/calendar/item/...",
        #     ...
        #   }
        #
        # user_id: UPN(email) 또는 user object id
        # start_at/end_at: ISO8601 문자열 또는 Time/DateTime 객체
        # time_zone: 예) "Asia/Seoul"
        #
        # attendees 예시:
        #   [{ email: "a@b.com", name: "A", type: "required" }]
        def create_event(user_id:, subject:, start_at:, end_at:, time_zone: 'Asia/Seoul', body: nil, location: nil, attendees: [])
          path = "/users/#{CGI.escape(user_id)}/events"
          payload = build_event_payload(
            subject: subject,
            start_at: start_at,
            end_at: end_at,
            time_zone: time_zone,
            body: body,
            location: location,
            attendees: attendees
          )

          status, resp_body = @client.post(path, json_body: payload, label: '일정 생성')

          if status == '201' || status == '200'
            JSON.parse(resp_body)
          else
            Rails.logger.error("API Error(일정 생성): #{status} - #{resp_body}")
            nil
          end
        rescue => e
          Rails.logger.error("API Error(일정 생성): EXCEPTION - #{e.class}: #{e.message}")
          nil
        end

        # 특정 사용자 일정 삭제
        # - 성공 시 true, 실패 시 false
        # - Application permission(앱 권한) 기준: DELETE /users/{id}/events/{event-id}
        def delete_event(user_id:, event_id:)
          path = "/users/#{CGI.escape(user_id)}/events/#{CGI.escape(event_id)}"
          status, resp_body = @client.delete(path, label: '일정 삭제')

          # 성공 시 204 No Content (또는 일부 케이스에서 202/200)
          if status == '204' || status == '202' || status == '200'
            true
          else
            Rails.logger.error("API Error(일정 삭제): #{status} - #{resp_body}")
            false
          end
        rescue => e
          Rails.logger.error("API Error(일정 삭제): EXCEPTION - #{e.class}: #{e.message}")
          false
        end

        private

        def build_event_payload(subject:, start_at:, end_at:, time_zone:, body:, location:, attendees:)
          payload = {
            'subject' => subject,
            'start' => { 'dateTime' => normalize_datetime(start_at), 'timeZone' => time_zone },
            'end' => { 'dateTime' => normalize_datetime(end_at), 'timeZone' => time_zone }
          }

          if body
            payload['body'] = { 'contentType' => 'HTML', 'content' => body }
          end

          if location
            payload['location'] = { 'displayName' => location }
          end

          if attendees && !attendees.empty?
            payload['attendees'] = attendees.map do |a|
              {
                'type' => (a[:type] || a['type'] || 'required'),
                'emailAddress' => {
                  'address' => (a[:email] || a['email']),
                  'name' => (a[:name] || a['name'])
                }
              }
            end
          end

          payload
        end

        def normalize_datetime(value)
          return value.iso8601 if value.respond_to?(:iso8601)
          value.to_s
        end
      end
    end
  end

  module SharePoint
    # Share 링크(…sharepoint.com/:p:/… 혹은 …/:f:/… 등)를 Graph /shares/{encoded}/driveItem으로 조회하고
    # webUrl/eTag에서 GUID를 추출하는 변환기
    class LinkConverter
      # token_manager를 주면, 요청 직전 "만료 임박(기본 60초)" 여부를 보고 Auth가 알아서 갱신한 토큰을 사용합니다.
      def initialize(access_token = nil, graph_base: 'https://graph.microsoft.com/v1.0', token_manager: nil)
        # token_manager가 없으면 플러그인 설정으로 자동 생성
        token_manager ||= TxGraph::Auth::TokenManager.new if access_token.nil?
        @client = TxGraph::Http::Client.new(access_token: access_token, token_manager: token_manager, base_url: graph_base)
      end

      def get_guid_from_url(sharing_url)
        encoded_url = encode_sharing_url(sharing_url)
        status, body = @client.get("/shares/#{encoded_url}/driveItem")

        if status == '200'
          data = JSON.parse(body)
          item = data['remoteItem'] ? data['remoteItem'] : data

          guid = extract_guid_from_web_url(item)
          return guid if guid

          guid = extract_guid_from_etag(item)
          return guid if guid

          Rails.logger.error("Error: webUrl 또는 eTag에서 GUID를 찾을 수 없습니다.")
          return nil
        end

        Rails.logger.error("API Error: #{status} - #{body}")
        nil
      rescue => e
        Rails.logger.error("API Error: EXCEPTION - #{e.class}: #{e.message}")
        nil
      end

      private

      def extract_guid_from_web_url(item)
        return nil unless item['webUrl']

        begin
          web_uri = URI.parse(item['webUrl'])
          # query가 nil이면 쿼리 파라미터가 없는 URL
          return nil unless web_uri.query
          
          query_params = CGI.parse(web_uri.query)
          if query_params['sourcedoc'] && query_params['sourcedoc'].any?
            # 값은 "{GUID}" 형태입니다. (URL 디코딩은 CGI가 자동으로 처리)
            return normalize_guid(query_params['sourcedoc'].first)
          end
        rescue => e
          Rails.logger.error("webUrl 파싱 중 오류 발생: #{e.message}")
        end

        nil
      end

      def extract_guid_from_etag(item)
        return nil unless item['eTag']

        # 제공해주신 JSON의 eTag: "{1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF},534"
        match = item['eTag'].match(/\{([a-fA-F0-9\-]+)\}/)
        return nil unless match

        # 순수 GUID만 반환(중괄호 제외)
        normalize_guid(match[1])
      end

      # MS Graph API 요구사항에 맞춘 Base64 인코딩 로직
      def encode_sharing_url(url)
        base64 = Base64.strict_encode64(url)
        base64 = base64.tr('+/', '-_')
        base64 = base64.chomp('=')
        "u!#{base64}"
      end

      # "{GUID}" / "GUID" 어떤 형태가 들어와도 "GUID"로 정규화
      def normalize_guid(value)
        return nil if value.nil?
        str = value.to_s.strip
        # 중괄호가 앞뒤로 감싸져 있으면 제거(중첩된 경우도 처리)
        while str.start_with?('{') && str.end_with?('}')
          str = str[1..-2].to_s.strip
        end
        str.empty? ? nil : str
      end
    end
  end
end