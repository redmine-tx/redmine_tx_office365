# TxGraph API 레퍼런스

TxGraph는 Microsoft Graph API를 쉽게 사용하기 위한 Ruby 라이브러리입니다.

**주요 기능:**
- ✅ 자동 토큰 관리 (발급, 캐싱, 자동 갱신)
- ✅ 멀티 프로세스 환경 지원 (Rails.cache 기반 토큰 공유)
- ✅ Outlook 일정 관리 (생성/삭제)
- ✅ SharePoint 링크에서 GUID 추출
- ✅ 401 자동 재시도 (토큰 갱신 후 재요청)

---

## 목차

1. [TxGraph::Auth::TokenManager](#1-txgraphauthtokenmanager) - 토큰 관리
2. [TxGraph::Http::Client](#2-txgraphhttpclient) - HTTP 클라이언트
3. [TxGraph::Outlook::Calendar::EventService](#3-txgraphoutlookcalendareventservice) - 일정 관리
4. [TxGraph::SharePoint::LinkConverter](#4-txgraphsharepointlinkconverter) - SharePoint 링크 변환

---

## 1. TxGraph::Auth::TokenManager

Microsoft Entra ID(Azure AD)에서 Client Credentials Flow로 Access Token을 발급하고 관리합니다.

### 특징

- 🔄 **자동 갱신**: 토큰 만료 60초 전에 자동으로 새 토큰 발급
- 💾 **캐싱**: `Rails.cache`를 사용하여 모든 프로세스가 토큰 공유
- 🔒 **Thread-safe**: Mutex를 사용하여 동시 요청 방지
- 🔌 **플러그인 연동**: Redmine 플러그인 설정에서 자동으로 인증 정보 로드

### 생성자 (initialize)

```ruby
TokenManager.new(
  tenant_id: nil,
  client_id: nil,
  client_secret: nil,
  scope: 'https://graph.microsoft.com/.default',
  refresh_skew: 60
)
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `tenant_id` | String | nil | Azure Tenant ID (플러그인 설정에서 자동 로드) |
| `client_id` | String | nil | Azure Application (Client) ID |
| `client_secret` | String | nil | Azure Client Secret |
| `scope` | String | `.default` | OAuth 2.0 Scope |
| `refresh_skew` | Integer | 60 | 만료 몇 초 전에 갱신할지 (초) |

#### 예외

- `ArgumentError`: `tenant_id`, `client_id`, `client_secret` 중 하나라도 없으면 발생

#### 예제

```ruby
# 방법 1: 플러그인 설정 자동 사용 (권장)
token_manager = TxGraph::Auth::TokenManager.new

# 방법 2: 수동 설정
token_manager = TxGraph::Auth::TokenManager.new(
  tenant_id: ENV['TENANT_ID'],
  client_id: ENV['CLIENT_ID'],
  client_secret: ENV['CLIENT_SECRET'],
  refresh_skew: 120  # 만료 2분 전에 갱신
)
```

---

### token

현재 유효한 Access Token을 반환합니다. 토큰이 없거나 만료 임박 시 자동으로 갱신합니다.

```ruby
token() → String | nil
```

#### 리턴값

- **String**: 유효한 Access Token
- **nil**: 토큰 발급 실패

#### 예제

```ruby
token_manager = TxGraph::Auth::TokenManager.new
access_token = token_manager.token

if access_token
  puts "Access Token: #{access_token[0..50]}..."
else
  puts "토큰 발급 실패: #{token_manager.last_error}"
end
```

---

### expires_in

현재 토큰의 남은 유효시간을 초 단위로 반환합니다.

```ruby
expires_in() → Integer | nil
```

#### 리턴값

- **Integer**: 남은 유효시간 (초)
- **nil**: 토큰이 없음

#### 예제

```ruby
remaining = token_manager.expires_in
if remaining
  puts "토큰 유효시간: #{remaining}초 (약 #{remaining / 60}분)"
else
  puts "토큰이 없습니다."
end
```

---

### last_error

마지막 토큰 발급/갱신 실패 이유를 반환합니다.

```ruby
last_error() → String | nil
```

#### 리턴값

- **String**: 에러 메시지
- **nil**: 에러 없음

#### 예제

```ruby
token = token_manager.token
unless token
  puts "토큰 발급 실패: #{token_manager.last_error}"
end
```

---

### force_refresh!

강제로 새 토큰을 발급받습니다. 401 에러 발생 시 안전장치로 사용됩니다.

```ruby
force_refresh!() → String | nil
```

#### 리턴값

- **String**: 새로 발급받은 Access Token
- **nil**: 발급 실패

#### 예제

```ruby
# API 호출 중 401 발생 시
if response.code == '401'
  puts "401 에러 발생, 토큰 강제 갱신..."
  new_token = token_manager.force_refresh!
  if new_token
    # 동일 요청 재시도
  end
end
```

---

## 2. TxGraph::Http::Client

Microsoft Graph API를 호출하는 HTTP 클라이언트입니다.

### 특징

- 🔐 **자동 인증**: Bearer Token 자동 추가
- 🔄 **401 자동 재시도**: 토큰 갱신 후 1회 자동 재시도
- 📝 **상세 로깅**: 에러 발생 시 원인 분석 로그 출력
- 🛡️ **예외 안전**: 예외 발생 시 `['EXCEPTION', error_message]` 반환

### 생성자 (initialize)

```ruby
Client.new(
  access_token: nil,
  token_manager: nil,
  base_url: 'https://graph.microsoft.com/v1.0'
)
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `access_token` | String | nil | 수동으로 지정할 Access Token |
| `token_manager` | TokenManager | nil | TokenManager 인스턴스 (자동 생성됨) |
| `base_url` | String | v1.0 | Graph API Base URL |

#### 예제

```ruby
# 방법 1: 자동 토큰 관리 (권장)
client = TxGraph::Http::Client.new

# 방법 2: 수동 토큰 지정
client = TxGraph::Http::Client.new(access_token: 'your-token-here')

# 방법 3: 커스텀 TokenManager 사용
token_manager = TxGraph::Auth::TokenManager.new(refresh_skew: 120)
client = TxGraph::Http::Client.new(token_manager: token_manager)
```

---

### get

GET 요청을 보냅니다.

```ruby
get(path, headers: {}) → [String, String]
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `path` | String | (필수) | API 엔드포인트 경로 (예: `/me`) |
| `headers` | Hash | `{}` | 추가 HTTP 헤더 |

#### 리턴값

`[status_code, response_body]` 배열

- **status_code** (String): HTTP 상태 코드 (`'200'`, `'404'`, `'EXCEPTION'` 등)
- **response_body** (String): 응답 본문 (JSON 문자열 또는 에러 메시지)

#### 예제

```ruby
client = TxGraph::Http::Client.new

# 현재 사용자 정보 조회
status, body = client.get('/me')
if status == '200'
  user = JSON.parse(body)
  puts "사용자: #{user['displayName']}"
  puts "이메일: #{user['mail']}"
else
  puts "에러: #{status} - #{body}"
end

# 특정 사용자 조회
status, body = client.get('/users/user@example.com')

# 사용자 목록 조회 (페이지네이션)
status, body = client.get('/users?$top=10&$select=displayName,mail')
```

---

### post

POST 요청을 보냅니다.

```ruby
post(path, json_body:, headers: {}, label: nil) → [String, String]
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `path` | String | (필수) | API 엔드포인트 경로 |
| `json_body` | Hash | (필수) | 요청 본문 (Hash, 자동으로 JSON 변환) |
| `headers` | Hash | `{}` | 추가 HTTP 헤더 |
| `label` | String | `'POST'` | 로그에 표시할 레이블 |

#### 리턴값

`[status_code, response_body]` 배열

#### 예제

```ruby
client = TxGraph::Http::Client.new

# 메일 발송
status, body = client.post(
  '/users/sender@example.com/sendMail',
  json_body: {
    message: {
      subject: '테스트 메일',
      body: {
        contentType: 'Text',
        content: '안녕하세요!'
      },
      toRecipients: [
        { emailAddress: { address: 'recipient@example.com' } }
      ]
    },
    saveToSentItems: true
  },
  label: '메일 발송'
)

if status == '202' || status == '200'
  puts "메일 발송 성공"
else
  puts "메일 발송 실패: #{status} - #{body}"
end
```

---

### delete

DELETE 요청을 보냅니다.

```ruby
delete(path, headers: {}, label: nil) → [String, String]
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `path` | String | (필수) | API 엔드포인트 경로 |
| `headers` | Hash | `{}` | 추가 HTTP 헤더 |
| `label` | String | `'DELETE'` | 로그에 표시할 레이블 |

#### 리턴값

`[status_code, response_body]` 배열

#### 예제

```ruby
client = TxGraph::Http::Client.new

# 일정 삭제
event_id = 'AAMkAGI2TAAA='
status, body = client.delete(
  "/users/user@example.com/events/#{event_id}",
  label: '일정 삭제'
)

if status == '204'
  puts "일정 삭제 성공"
else
  puts "일정 삭제 실패: #{status} - #{body}"
end
```

---

### set_access_token

Access Token을 수동으로 설정합니다.

```ruby
set_access_token(access_token) → nil
```

#### 파라미터

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `access_token` | String | 새로운 Access Token |

#### 예제

```ruby
client = TxGraph::Http::Client.new
client.set_access_token('new-token-here')
```

---

## 3. TxGraph::Outlook::Calendar::EventService

Outlook 일정(Event)을 생성하고 삭제하는 서비스입니다.

### 특징

- 📅 **일정 생성**: 제목, 시간, 장소, 참석자 등 설정
- 🗑️ **일정 삭제**: Event ID로 일정 삭제
- 🌏 **타임존 지원**: 한국, 미국, 일본 등 모든 타임존 지원
- 👥 **참석자 관리**: 필수/선택 참석자 설정
- 📝 **HTML 본문**: 일정 본문에 HTML 사용 가능

### 생성자 (initialize)

```ruby
EventService.new(
  access_token = nil,
  graph_base: 'https://graph.microsoft.com/v1.0',
  token_manager: nil
)
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `access_token` | String | nil | 수동으로 지정할 Access Token |
| `graph_base` | String | v1.0 | Graph API Base URL |
| `token_manager` | TokenManager | nil | TokenManager 인스턴스 (자동 생성) |

#### 예제

```ruby
# 방법 1: 자동 토큰 관리 (권장)
event_service = TxGraph::Outlook::Calendar::EventService.new

# 방법 2: 수동 토큰 지정
event_service = TxGraph::Outlook::Calendar::EventService.new('your-token-here')
```

---

### create_event

새로운 일정을 생성합니다.

```ruby
create_event(
  user_id:,
  subject:,
  start_at:,
  end_at:,
  time_zone: 'Asia/Seoul',
  body: nil,
  location: nil,
  attendees: []
) → Hash | nil
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `user_id` | String | (필수) | 사용자 UPN (이메일) 또는 User Object ID |
| `subject` | String | (필수) | 일정 제목 |
| `start_at` | String/Time/DateTime | (필수) | 시작 시각 (ISO8601 형식) |
| `end_at` | String/Time/DateTime | (필수) | 종료 시각 (ISO8601 형식) |
| `time_zone` | String | `'Asia/Seoul'` | 타임존 ([IANA 형식](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)) |
| `body` | String | nil | 일정 본문 (HTML 가능) |
| `location` | String | nil | 장소 |
| `attendees` | Array | `[]` | 참석자 목록 (아래 참조) |

#### attendees 형식

```ruby
[
  { email: 'user1@example.com', name: '홍길동', type: 'required' },
  { email: 'user2@example.com', name: '김철수', type: 'optional' }
]
```

- **email** (String): 참석자 이메일 (필수)
- **name** (String): 참석자 이름 (선택)
- **type** (String): `'required'` (필수) 또는 `'optional'` (선택), 기본값 `'required'`

#### 리턴값

- **Hash**: 생성된 일정 정보 (Microsoft Graph Event 객체)
  - `id`: Event ID (삭제 시 필요)
  - `subject`: 제목
  - `start`: 시작 시각 정보
  - `end`: 종료 시각 정보
  - `webLink`: Outlook 웹에서 열기 링크
  - 기타 필드...
- **nil**: 생성 실패

#### 예제

```ruby
event_service = TxGraph::Outlook::Calendar::EventService.new

# 간단한 일정
event = event_service.create_event(
  user_id: 'user@example.com',
  subject: '팀 미팅',
  start_at: '2025-12-24T10:00:00',
  end_at: '2025-12-24T11:00:00'
)

if event
  puts "일정 생성 성공!"
  puts "ID: #{event['id']}"
  puts "웹 링크: #{event['webLink']}"
end

# 상세한 일정 (본문, 장소, 참석자 포함)
event = event_service.create_event(
  user_id: 'manager@example.com',
  subject: '프로젝트 킥오프 미팅',
  start_at: Time.now + 1.day,
  end_at: Time.now + 1.day + 2.hours,
  time_zone: 'Asia/Seoul',
  body: '<h2>안건</h2><ul><li>프로젝트 개요</li><li>일정 논의</li></ul>',
  location: '회의실 A (3층)',
  attendees: [
    { email: 'dev1@example.com', name: '개발자1', type: 'required' },
    { email: 'dev2@example.com', name: '개발자2', type: 'required' },
    { email: 'designer@example.com', name: '디자이너', type: 'optional' }
  ]
)

# Redmine 근태 관리 연동 예제
attendance = Attendance.find(123)
event = event_service.create_event(
  user_id: User.current.mail,
  subject: "근무: #{attendance.work_date.strftime('%Y-%m-%d')}",
  start_at: attendance.start_time,
  end_at: attendance.end_time,
  time_zone: 'Asia/Seoul',
  location: attendance.work_location
)

if event
  attendance.update(calendar_event_id: event['id'])
end
```

---

### delete_event

일정을 삭제합니다.

```ruby
delete_event(user_id:, event_id:) → Boolean
```

#### 파라미터

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `user_id` | String | 사용자 UPN (이메일) 또는 User Object ID |
| `event_id` | String | 삭제할 Event ID (`create_event`의 리턴값에서 `id` 필드) |

#### 리턴값

- **true**: 삭제 성공
- **false**: 삭제 실패

#### 예제

```ruby
event_service = TxGraph::Outlook::Calendar::EventService.new

# 일정 삭제
success = event_service.delete_event(
  user_id: 'user@example.com',
  event_id: 'AAMkAGI2TAAA='
)

if success
  puts "일정 삭제 완료"
else
  puts "일정 삭제 실패"
end

# Redmine 근태 관리 연동 예제
attendance = Attendance.find(123)
if attendance.calendar_event_id
  success = event_service.delete_event(
    user_id: User.current.mail,
    event_id: attendance.calendar_event_id
  )
  
  if success
    attendance.update(calendar_event_id: nil)
    flash[:notice] = '일정이 삭제되었습니다.'
  else
    flash[:error] = '일정 삭제에 실패했습니다.'
  end
end
```

---

## 4. TxGraph::SharePoint::LinkConverter

SharePoint 공유 링크에서 파일의 고유 GUID를 추출합니다.

### 특징

- 🔗 **다양한 URL 형식 지원**: `:p:/`, `:f:/`, `Doc.aspx` 등
- 🔍 **자동 GUID 추출**: `webUrl` 또는 `eTag`에서 자동 추출
- 🎯 **정규화**: `{GUID}` 또는 `GUID` 형태 모두 처리

### 생성자 (initialize)

```ruby
LinkConverter.new(
  access_token = nil,
  graph_base: 'https://graph.microsoft.com/v1.0',
  token_manager: nil
)
```

#### 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| `access_token` | String | nil | 수동으로 지정할 Access Token |
| `graph_base` | String | v1.0 | Graph API Base URL |
| `token_manager` | TokenManager | nil | TokenManager 인스턴스 (자동 생성) |

#### 예제

```ruby
# 방법 1: 자동 토큰 관리 (권장)
converter = TxGraph::SharePoint::LinkConverter.new

# 방법 2: 수동 토큰 지정
converter = TxGraph::SharePoint::LinkConverter.new('your-token-here')
```

---

### get_guid_from_url

SharePoint 공유 링크에서 파일의 GUID를 추출합니다.

```ruby
get_guid_from_url(sharing_url) → String | nil
```

#### 파라미터

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `sharing_url` | String | SharePoint 공유 링크 |

#### 지원되는 URL 형식

```
✅ https://yourcompany.sharepoint.com/:p:/g/EQB1z6Udy4jnSZWW5PSr3HbP...
✅ https://yourcompany.sharepoint.com/:f:/r/sites/YourSite/Documents/file.xlsx?sourcedoc=%7BGUID%7D
✅ https://yourcompany.sharepoint.com/sites/Project/_layouts/15/Doc.aspx?sourcedoc={GUID}&action=edit
✅ https://yourcompany-my.sharepoint.com/:w:/r/personal/user/_layouts/15/Doc.aspx?sourcedoc={GUID}
```

#### 리턴값

- **String**: 파일의 GUID (대문자, 하이픈 포함, 중괄호 제외)
  - 예: `1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF`
- **nil**: GUID 추출 실패

#### 예제

```ruby
converter = TxGraph::SharePoint::LinkConverter.new

# 기본 사용
sharing_url = "https://yourcompany.sharepoint.com/:p:/g/IQB1z6Udy4jnSZWW5PSr3HbPAULbh0gcOxAePDOuglzWHcE"
guid = converter.get_guid_from_url(sharing_url)

if guid
  puts "GUID: #{guid}"
  # => GUID: 1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF
  
  # Embed URL 생성 (PowerPoint, Excel 등)
  site_url = "https://yourcompany.sharepoint.com/sites"
  embed_url = "#{site_url}/_layouts/15/embed.aspx?uniqueid=#{guid}"
  puts "Embed URL: #{embed_url}"
else
  puts "GUID 추출 실패"
end

# 여러 URL 처리
urls = [
  "https://company.sharepoint.com/:p:/g/link1",
  "https://company.sharepoint.com/:x:/r/sites/HR/Documents/report.xlsx?sourcedoc={GUID1}",
  "https://company.sharepoint.com/:w:/r/personal/user/Documents/doc.docx?sourcedoc={GUID2}"
]

urls.each do |url|
  guid = converter.get_guid_from_url(url)
  puts "#{url} => #{guid || 'FAILED'}"
end

# Redmine 이슈 설명에서 SharePoint 링크 찾기
issue = Issue.find(123)
sharepoint_urls = issue.description.scan(/https:\/\/[^\s]+sharepoint\.com[^\s]+/)

sharepoint_urls.each do |url|
  guid = converter.get_guid_from_url(url)
  if guid
    # Office365Storage에 저장
    Office365Storage.set("DOC.#{issue.id}", guid, description: "Issue ##{issue.id}")
  end
end
```

---

## 통합 예제

### 예제 1: 근태 관리 시스템 연동

```ruby
class AttendanceCalendarSync
  def initialize
    @event_service = TxGraph::Outlook::Calendar::EventService.new
  end
  
  # 출근 시 자동으로 일정 생성
  def create_work_event(attendance)
    event = @event_service.create_event(
      user_id: attendance.user.mail,
      subject: "근무: #{attendance.work_type}",
      start_at: attendance.clock_in,
      end_at: attendance.clock_out || (attendance.clock_in + 8.hours),
      time_zone: 'Asia/Seoul',
      location: attendance.office_location,
      body: "<p>근무 유형: #{attendance.work_type}</p><p>비고: #{attendance.notes}</p>"
    )
    
    if event
      attendance.update(calendar_event_id: event['id'])
      Rails.logger.info "일정 생성 성공: Attendance ##{attendance.id} => Event #{event['id']}"
    else
      Rails.logger.error "일정 생성 실패: Attendance ##{attendance.id}"
    end
  end
  
  # 퇴근/수정 시 일정 삭제
  def delete_work_event(attendance)
    return unless attendance.calendar_event_id
    
    success = @event_service.delete_event(
      user_id: attendance.user.mail,
      event_id: attendance.calendar_event_id
    )
    
    if success
      attendance.update(calendar_event_id: nil)
      Rails.logger.info "일정 삭제 성공: Attendance ##{attendance.id}"
    else
      Rails.logger.error "일정 삭제 실패: Attendance ##{attendance.id}"
    end
  end
end

# 사용 예시
sync = AttendanceCalendarSync.new
attendance = Attendance.find(123)
sync.create_work_event(attendance)
```

---

### 예제 2: SharePoint 문서 자동 연결

```ruby
class SharePointDocumentLinker
  def initialize
    @converter = TxGraph::SharePoint::LinkConverter.new
  end
  
  # 이슈에서 SharePoint 링크 찾아 GUID 저장
  def link_documents_to_issue(issue)
    sharepoint_urls = extract_sharepoint_urls(issue.description)
    
    return if sharepoint_urls.empty?
    
    sharepoint_urls.each_with_index do |url, index|
      guid = @converter.get_guid_from_url(url)
      
      if guid
        key = index == 0 ? "DOC.#{issue.id}" : "DOC.#{issue.id}.#{index}"
        Office365Storage.set(
          key,
          guid,
          description: "Issue ##{issue.id}: #{issue.subject}"
        )
        Rails.logger.info "SharePoint GUID 저장: Issue ##{issue.id} => #{guid}"
      else
        Rails.logger.warn "GUID 추출 실패: #{url}"
      end
    end
  end
  
  # 이슈의 모든 SharePoint 문서 조회
  def get_issue_documents(issue)
    documents = []
    
    # 메인 문서
    main_guid = Office365Storage.get("DOC.#{issue.id}")
    documents << main_guid if main_guid
    
    # 추가 문서
    (1..10).each do |i|
      guid = Office365Storage.get("DOC.#{issue.id}.#{i}")
      break unless guid
      documents << guid
    end
    
    documents
  end
  
  private
  
  def extract_sharepoint_urls(text)
    return [] unless text
    text.scan(/https:\/\/[^\s]+sharepoint\.com[^\s]+/)
  end
end

# 사용 예시
linker = SharePointDocumentLinker.new
issue = Issue.find(456)
linker.link_documents_to_issue(issue)

documents = linker.get_issue_documents(issue)
puts "Issue ##{issue.id}에 연결된 문서: #{documents.count}개"
```

---

### 예제 3: 배치 작업 - 월간 회의 일정 일괄 생성

```ruby
class MonthlyMeetingScheduler
  def initialize
    @event_service = TxGraph::Outlook::Calendar::EventService.new
  end
  
  # 매월 첫째 월요일 10시에 전사 회의 생성
  def schedule_monthly_meetings(year, month)
    first_monday = find_first_monday(year, month)
    return unless first_monday
    
    managers = User.where(role: 'manager')
    
    managers.each do |manager|
      event = @event_service.create_event(
        user_id: manager.mail,
        subject: "#{year}년 #{month}월 전사 회의",
        start_at: first_monday.change(hour: 10),
        end_at: first_monday.change(hour: 12),
        time_zone: 'Asia/Seoul',
        location: '대회의실',
        body: '<h2>안건</h2><ol><li>전월 실적 리뷰</li><li>당월 목표 설정</li><li>주요 이슈 논의</li></ol>',
        attendees: get_all_staff_emails
      )
      
      if event
        puts "✓ #{manager.name} 일정 생성 완료"
      else
        puts "✗ #{manager.name} 일정 생성 실패"
      end
    end
  end
  
  private
  
  def find_first_monday(year, month)
    date = Date.new(year, month, 1)
    date += (1 - date.wday) % 7  # 첫째 월요일 찾기
    date
  end
  
  def get_all_staff_emails
    User.active.map do |user|
      { email: user.mail, name: user.name, type: 'required' }
    end
  end
end

# 실행
scheduler = MonthlyMeetingScheduler.new
scheduler.schedule_monthly_meetings(2025, 12)
```

---

## 에러 처리

### 일반적인 에러와 대응

```ruby
# TokenManager 에러
begin
  token_manager = TxGraph::Auth::TokenManager.new
rescue ArgumentError => e
  puts "설정 오류: #{e.message}"
  # => "tenant_id가 설정되지 않았습니다..."
end

# HTTP 요청 에러
client = TxGraph::Http::Client.new
status, body = client.get('/invalid/path')

case status
when '200', '201'
  data = JSON.parse(body)
  # 성공 처리
when '400'
  puts "잘못된 요청: #{body}"
when '401'
  puts "인증 실패: 토큰을 확인하세요"
when '403'
  puts "권한 부족: Azure에서 권한을 확인하세요"
when '404'
  puts "리소스를 찾을 수 없음"
when '429'
  puts "API 호출 제한 초과: 잠시 후 재시도하세요"
when 'EXCEPTION'
  puts "예외 발생: #{body}"
else
  puts "알 수 없는 에러: #{status} - #{body}"
end

# EventService 에러
event_service = TxGraph::Outlook::Calendar::EventService.new
event = event_service.create_event(
  user_id: 'invalid@example.com',
  subject: 'Test',
  start_at: Time.now,
  end_at: Time.now + 1.hour
)

if event.nil?
  # 로그 확인
  # tail -f log/production.log | grep "API Error"
  puts "일정 생성 실패 - 로그를 확인하세요"
end

# LinkConverter 에러
converter = TxGraph::SharePoint::LinkConverter.new
guid = converter.get_guid_from_url('invalid-url')

if guid.nil?
  puts "GUID 추출 실패 - URL 형식 또는 권한을 확인하세요"
end
```

---

## 로깅

TxGraph는 `Rails.logger`를 사용하여 상세한 로그를 출력합니다.

### 로그 레벨

- **INFO**: 정상 작동
- **WARN**: 경고 (토큰 갱신 실패했으나 기존 토큰 유지 등)
- **ERROR**: 에러 (API 호출 실패, 인증 실패 등)

### 로그 예시

```
# 토큰 갱신 경고
토큰 갱신 실패(기존 토큰 유지): 401 Unauthorized

# 401 자동 재시도
401 Unauthorized 감지(일정 생성): 토큰 강제 갱신 후 1회 재시도합니다.

# 재시도 실패
재시도 실패(일정 생성): 401 - 인증 실패(만료/잘못된 토큰/테넌트 불일치 등)

# 권한 부족
재시도 실패(GET): 403 - 권한 부족/정책 차단(Admin consent/Access Policy 등)

# API 에러
API Error(일정 생성): 400 - {"error":{"code":"InvalidRequest","message":"..."}}

# SharePoint GUID 추출 실패
Error: webUrl 또는 eTag에서 GUID를 찾을 수 없습니다.
```

### 로그 필터링

```bash
# Office365 관련 로그만 보기
tail -f log/production.log | grep -i "office365\|txgraph"

# 에러만 보기
tail -f log/production.log | grep "ERROR"

# 특정 작업 추적
tail -f log/production.log | grep "일정 생성"
```

---

## 성능 최적화

### 토큰 캐싱

TokenManager는 토큰을 `Rails.cache`에 저장하여 프로세스 간 공유합니다.

```ruby
# Redis 캐시 설정 (config/environments/production.rb)
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'] || 'redis://localhost:6379/1',
  expires_in: 90.minutes
}
```

### 배치 작업 최적화

```ruby
# 나쁜 예: 매번 새 인스턴스 생성
users.each do |user|
  event_service = TxGraph::Outlook::Calendar::EventService.new  # ✗ 비효율적
  event_service.create_event(...)
end

# 좋은 예: 인스턴스 재사용
event_service = TxGraph::Outlook::Calendar::EventService.new  # ✓ 한 번만 생성
users.each do |user|
  event_service.create_event(...)
end
```

### API 호출 제한 관리

Microsoft Graph API는 호출 제한(throttling)이 있습니다.

```ruby
class ApiRateLimiter
  def with_rate_limit
    sleep 0.1  # 요청 간 100ms 대기
    yield
  rescue => e
    if e.message.include?('429')  # Too Many Requests
      sleep 60  # 1분 대기 후 재시도
      yield
    else
      raise
    end
  end
end

limiter = ApiRateLimiter.new
event_service = TxGraph::Outlook::Calendar::EventService.new

users.each do |user|
  limiter.with_rate_limit do
    event_service.create_event(...)
  end
end
```

---

## 테스트

### Rails 콘솔에서 테스트

```ruby
# Rails 콘솔 실행
cd /Users/testors/redmine-ssr/redmine-dev
bundle exec rails console production

# 토큰 테스트
token_manager = TxGraph::Auth::TokenManager.new
puts token_manager.token
puts "유효시간: #{token_manager.expires_in}초"

# HTTP 클라이언트 테스트
client = TxGraph::Http::Client.new
status, body = client.get('/me')
puts "Status: #{status}"
puts JSON.pretty_generate(JSON.parse(body)) if status == '200'

# 일정 생성 테스트
event_service = TxGraph::Outlook::Calendar::EventService.new
event = event_service.create_event(
  user_id: 'your-email@example.com',
  subject: '테스트 일정',
  start_at: Time.now + 1.hour,
  end_at: Time.now + 2.hours
)
puts "Event ID: #{event['id']}" if event

# SharePoint 링크 테스트
converter = TxGraph::SharePoint::LinkConverter.new
guid = converter.get_guid_from_url('your-sharepoint-url')
puts "GUID: #{guid}"
```

---

## 참고 자료

- [Microsoft Graph API 문서](https://learn.microsoft.com/en-us/graph/overview)
- [Calendar API 레퍼런스](https://learn.microsoft.com/en-us/graph/api/resources/calendar)
- [Event 리소스 타입](https://learn.microsoft.com/en-us/graph/api/resources/event)
- [SharePoint API](https://learn.microsoft.com/en-us/graph/api/resources/sharepoint)
- [에러 코드 목록](https://learn.microsoft.com/en-us/graph/errors)

---

**버전**: 1.0  
**최종 업데이트**: 2025-12-29  
**문의**: 플러그인 관련 문의는 README.rdoc를 참조하세요.

