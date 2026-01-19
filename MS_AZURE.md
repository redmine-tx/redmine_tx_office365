# Microsoft Azure(Entra ID) 설정 가이드

이 문서는 Redmine Tx Office365 플러그인에서 Microsoft Graph API를 사용하기 위한 Azure 설정 방법을 설명합니다.

현재 구현은 **Client Credentials Flow(앱 권한, Application permission)** 기반입니다.

---

## 1. Azure(Entra ID) 앱 등록

1. [Azure Portal](https://portal.azure.com) 접속 → **Microsoft Entra ID**
2. **App registrations** → **New registration** 클릭
3. 아래 항목 입력:
   - **Name**: 원하는 이름 (예: `redmine-msgraph-link-converter`)
   - **Supported account types**: 보통 단일 테넌트면 *Accounts in this organizational directory only* 선택
   - **Redirect URI**: (이 플러그인은 필요 없음) 비워도 됩니다
4. **Register** 클릭
5. 생성 후 **Overview** 페이지에서 아래 값을 기록해 두세요:
   - **Directory (tenant) ID** → 환경변수 `TENANT_ID`로 사용
   - **Application (client) ID** → 환경변수 `CLIENT_ID`로 사용

> 💡 **Tip**: 이 값들은 나중에 플러그인 설정에 입력해야 하므로 안전한 곳에 보관하세요.

---

## 2. Client Secret 발급

1. 방금 만든 앱 → **Certificates & secrets** 메뉴
2. **Client secrets** 탭 → **New client secret** 클릭
3. 설명(Description) 입력 및 만료(Expiration) 기간 설정:
   - 권장: 24개월 (보안 정책에 따라 조정)
4. **Add** 클릭
5. 생성 직후 표시되는 **Value** 컬럼의 값을 복사하여 보관
   - 이 값이 환경변수 `CLIENT_SECRET`입니다
   - ⚠️ **중요**: 이 화면을 닫으면 다시 볼 수 없으니 즉시 안전한 장소에 저장하세요

> 🔒 **보안 주의사항**:
> - `CLIENT_SECRET`는 비밀번호와 동일한 보안 수준입니다
> - Git 저장소에 절대 커밋하지 마세요
> - 프로덕션 환경에서는 환경변수나 비밀 관리 시스템(Azure Key Vault, AWS Secrets Manager 등)을 사용하세요

---

## 3. Microsoft Graph 권한 설정 (Application Permissions)

1. 앱 → **API permissions** 메뉴
2. **Add a permission** 클릭
3. **Microsoft Graph** 선택
4. **Application permissions** 선택 (⚠️ Delegated permissions 아님)
5. 아래 권한들을 검색하여 추가:

### 3.1. 필수 권한

#### SharePoint/OneDrive 파일 접근용
- **`Sites.Read.All`**: SharePoint 사이트 및 파일 읽기 (범용)
- 또는 **`Files.Read.All`**: OneDrive/SharePoint 파일 읽기

> 💡 일반적으로 공유 링크를 Graph API로 해석하고 driveItem을 조회하려면 위 권한 중 하나 이상이 필요합니다.

#### Outlook 일정 관리용 (근태 관리 기능 사용 시)
- **`Calendars.ReadWrite`**: 사용자 일정 읽기/쓰기

### 3.2. 고급 보안 옵션 (선택)

더 엄격한 보안이 필요한 경우:
- **`Sites.Selected`**: 특정 사이트만 접근 허용
  - 장점: 필요한 사이트에만 권한 부여
  - 단점: 사이트별로 별도 Grant 작업 필요 (Graph API 또는 PowerShell 사용)

> ℹ️ `Sites.Selected`는 "권한 추가"만으로는 동작하지 않으며, 각 SharePoint 사이트에 개별적으로 권한을 부여해야 합니다.

### 3.3. 권한 추가 후 확인

**API permissions** 페이지에 다음과 같이 표시되어야 합니다:

| API / Permission name | Type | Admin consent required |
|----------------------|------|------------------------|
| Microsoft Graph / Sites.Read.All | Application | Yes |
| Microsoft Graph / Calendars.ReadWrite | Application | Yes |

---

## 4. 관리자 동의 (Admin Consent) 부여

Application permission은 **반드시 관리자 동의**가 필요합니다.

1. 앱 → **API permissions** 페이지
2. **Grant admin consent for [조직명]** 버튼 클릭
3. 확인 대화상자에서 **Yes** 클릭
4. Status 컬럼이 모두 **✓ Granted for [조직명]** 로 변경되는지 확인

> ⚠️ **관리자 권한 필요**: 이 작업은 Azure AD의 전역 관리자 또는 애플리케이션 관리자 권한이 있어야 가능합니다.

---

## 5. 발급받은 정보 확인

아래 3가지 값이 준비되었는지 확인하세요:

| 항목 | Azure Portal 위치 | 용도 |
|-----|------------------|-----|
| **Tenant ID** | App registrations → Overview → Directory (tenant) ID | 조직 식별자 |
| **Client ID** | App registrations → Overview → Application (client) ID | 앱 식별자 |
| **Client Secret** | Certificates & secrets → Client secrets → Value | 앱 인증 비밀키 |

---

## 6. Redmine 플러그인 설정에 적용

### 6.1. 플러그인 설정 화면에서 입력

1. Redmine 관리자 로그인
2. **관리** → **플러그인** → **Redmine Tx Office365 plugin** → **설정**
3. 위에서 발급받은 값 입력:
   - **Tenant ID**: Directory (tenant) ID
   - **Client ID**: Application (client) ID  
   - **Client Secret**: Client secrets Value
   - **SharePoint Site URL**: 사용할 SharePoint 사이트 URL
     - 예: `https://yourcompany.sharepoint.com/sites/YourSite`

### 6.2. 환경변수로 설정 (대안)

플러그인 설정 대신 환경변수로도 설정 가능합니다:

```bash
# Linux/macOS (.bashrc, .zshrc 또는 systemd service 파일)
export TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export CLIENT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export CLIENT_SECRET="your-secret-value-here"
```

```bash
# Systemd 서비스 파일 예시 (/etc/systemd/system/redmine.service)
[Service]
Environment="TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
Environment="CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
Environment="CLIENT_SECRET=your-secret-value-here"
```

---

## 7. 연결 테스트

### 7.1. Rails 콘솔에서 테스트

```bash
cd /Users/testors/redmine-ssr/redmine-dev
bundle exec rails console production
```

```ruby
# 토큰 발급 테스트
token_manager = TxGraph::Auth::TokenManager.new
access_token = token_manager.token
puts "토큰 발급 성공: #{access_token[0..50]}..."
puts "유효시간: #{token_manager.expires_in}초"

# SharePoint 링크 변환 테스트
converter = TxGraph::SharePoint::LinkConverter.new
test_url = "https://yourcompany.sharepoint.com/:p:/g/YOUR_SHARING_LINK"
guid = converter.get_guid_from_url(test_url)
puts "GUID: #{guid}"
```

### 7.2. 성공 시 출력 예시

```
토큰 발급 성공: eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ij...
유효시간: 3599초
GUID: 1DA5CF75-88CB-49E7-9596-E4F4ABDC76CF
```

---

## 8. 문제 해결 (Troubleshooting)

### 8.1. 401 Unauthorized

**증상**: 토큰 발급 실패 또는 API 호출 시 401 에러

**원인**:
- `TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET` 값이 잘못됨
- Client Secret이 만료됨
- Client Secret을 복사할 때 공백이 포함됨

**해결 방법**:
1. Azure Portal에서 값 재확인
2. Client Secret 만료일 확인 (Certificates & secrets 메뉴)
3. 필요 시 새 Secret 발급 후 재설정

### 8.2. 403 Forbidden

**증상**: API 호출 시 403 에러 또는 "Insufficient privileges to complete the operation"

**원인**:
- 필요한 권한이 추가되지 않음
- 관리자 동의(Admin consent)가 부여되지 않음
- 권한 타입이 Application이 아닌 Delegated로 추가됨

**해결 방법**:
1. **API permissions** 에서 필요한 권한 확인:
   - `Sites.Read.All` 또는 `Files.Read.All`
   - `Calendars.ReadWrite` (일정 사용 시)
2. 권한 타입이 **Application** 인지 확인
3. **Grant admin consent** 재실행
4. Status가 "Granted for [조직명]"인지 확인

### 8.3. 404 Not Found (SharePoint 링크 변환 시)

**증상**: SharePoint URL에서 GUID 추출 실패

**원인**:
- 공유 링크가 만료되었거나 삭제됨
- 앱이 해당 사이트/파일에 접근 권한이 없음
- URL 형식이 지원되지 않음

**해결 방법**:
1. 브라우저에서 해당 URL 접근 테스트
2. SharePoint 사이트의 권한 설정 확인
3. `Sites.Read.All` 권한이 부여되었는지 확인

### 8.4. "AADSTS7000215: Invalid client secret is provided"

**증상**: 토큰 발급 시 위 에러 메시지

**원인**:
- Client Secret 값이 잘못됨 (복사 오류, 앞뒤 공백 등)
- Secret이 만료됨

**해결 방법**:
1. Azure Portal → Certificates & secrets → 만료일 확인
2. 새 Secret 발급
3. 앞뒤 공백 없이 정확히 복사하여 재설정

### 8.5. 로그 확인 방법

```bash
# Redmine 로그에서 Office365 관련 로그 확인
cd /Users/testors/redmine-ssr/redmine-dev
tail -f log/production.log | grep -i "office365\|txgraph"
```

**성공 로그 예시**:
```
Office365: Access token obtained successfully
Office365: Issue #123에서 SharePoint GUID 저장됨: 1DA5CF75-...
```

**실패 로그 예시**:
```
Office365: Failed to obtain access token: 401 Unauthorized
Office365: Issue #123에서 SharePoint URL의 GUID 추출 실패
```

---

## 9. 보안 권장사항

### 9.1. Client Secret 관리

- ✅ Secret 만료일을 캘린더에 등록하여 사전 갱신
- ✅ 프로덕션/개발 환경별로 다른 앱 등록 사용
- ✅ Secret 값을 비밀 관리 시스템에 저장 (Azure Key Vault, HashiCorp Vault 등)
- ❌ Git 저장소에 절대 커밋 금지
- ❌ 로그에 Secret 값 출력 금지

### 9.2. 권한 최소화

- 필요한 권한만 부여 (Principle of Least Privilege)
- 가능하면 `Sites.Selected` 사용하여 특정 사이트만 접근
- 주기적으로 권한 사용 현황 검토

### 9.3. 모니터링

- Azure AD → Enterprise applications → 해당 앱 → Sign-in logs 정기 확인
- 비정상적인 API 호출 패턴 모니터링
- 토큰 발급 실패율 추적

---

## 10. 참고 자료

- [Microsoft Graph API 문서](https://learn.microsoft.com/en-us/graph/overview)
- [Application permissions 가이드](https://learn.microsoft.com/en-us/graph/auth-v2-service)
- [Sites.Selected 권한 설정 방법](https://learn.microsoft.com/en-us/graph/permissions-selected-overview)
- [Azure AD 앱 등록 가이드](https://learn.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)

---

**작성일**: 2025-12-29  
**버전**: 1.0  
**문의**: 플러그인 관련 문의는 README.rdoc의 문제 해결 섹션을 참조하세요.

