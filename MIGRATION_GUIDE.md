# SharePoint GUID 일괄 마이그레이션 가이드

## 사용법

### 1. 전체 이슈 마이그레이션 (권장 - 기존 GUID에 file_type, source_url 추가)

```bash
cd /var/www/redmine-dev
# Dry Run (테스트)
RAILS_ENV=production bundle exec rake office365:migrate_all[true]

# 실제 실행
RAILS_ENV=production bundle exec rake office365:migrate_all[false]
```

또는:
```bash
RAILS_ENV=production bundle exec rake office365:migrate_sharepoint_guids[false,true,all]
```

### 2. 최근 N개월 이슈만 처리

```bash
# 최근 2개월
RAILS_ENV=production bundle exec rake office365:migrate_sharepoint_guids[false,false,2months]

# 최근 6개월
RAILS_ENV=production bundle exec rake office365:migrate_sharepoint_guids[false,false,6months]
```

### 3. Dry Run (테스트 - 저장 안 함)

```bash
RAILS_ENV=production bundle exec rake office365:migrate_sharepoint_guids[true,false,all]
```

## 기타 명령어

### 통계 조회

```bash
RAILS_ENV=production bundle exec rake office365:stats
```

### 특정 이슈 GUID 추출

```bash
RAILS_ENV=production bundle exec rake office365:extract_guid[이슈번호]
```

예시:
```bash
RAILS_ENV=production bundle exec rake office365:extract_guid[46855]
```

## 주의사항

1. **Dry Run 먼저 실행**: 실제 실행 전에 반드시 `dry_run=true`로 테스트하세요.
2. **백그라운드 실행 권장**: 대량 작업이므로 `screen` 또는 `nohup` 사용을 권장합니다.
   ```bash
   screen -S sharepoint_migration
   cd /var/www/redmine-dev
   RAILS_ENV=production bundle exec rake office365:migrate_sharepoint_guids[false]
   # Ctrl+A, D로 detach
   ```
3. **로그 확인**: `log/production.log`에서 상세 로그 확인 가능
4. **처리 시간**: 이슈 개수에 따라 다르지만, Graph API 호출이 필요한 경우 시간이 오래 걸릴 수 있습니다.

## 처리 대상

### 기본 명령어 (migrate_sharepoint_guids)
- **기간**: 파라미터로 지정 (기본값: 2개월)
  - `2months`: 최근 2개월 (`updated_on >= 2.months.ago`)
  - `6months`: 최근 6개월
  - `all`: 전체 이슈
- **조건**: description에 `sharepoint.com` 포함
- **건너뜀**: 이미 GUID가 저장된 이슈 (force=false인 경우)

### 전체 마이그레이션 (migrate_all)
- **기간**: 전체 이슈 (생성 시점 무관)
- **강제 업데이트**: 자동으로 force=true (기존 GUID도 재추출하여 file_type, source_url 추가)

## 지원하는 URL 형식

1. **Office Online 에디터 직접 링크** (Graph API 없이 즉시 추출)
   - `https://supercreative.sharepoint.com/:x:/r/_layouts/15/Doc.aspx?sourcedoc={GUID}`

2. **OneNote URL** (Graph API 없이 즉시 추출)
   - `https://supercreative.sharepoint.com/_layouts/OneNote.aspx?...wd=target(...|GUID|...)`

3. **공유 링크** (Graph API 호출 필요)
   - `https://supercreative.sharepoint.com/:p:/g/...`
   - `https://supercreative.sharepoint.com/:f:/g/...`
   - `https://supercreative.sharepoint.com/:x:/g/...`

## 예상 출력

```
================================================================================
SharePoint GUID 일괄 추출 및 저장
================================================================================
모드: DRY RUN (실제로 저장하지 않음)
강제 업데이트: 아니오 (새 GUID만 추출)
================================================================================

대상 이슈: 1500건 (전체 + SharePoint URL 포함)

처리 중: 150/150 (100.0%)

================================================================================
처리 완료
================================================================================
총 이슈 수:           150건
처리된 이슈:          150건
성공:                 120건
건너뜀 (기존 GUID):   25건
실패:                 5건
URL 없음:             0건
================================================================================
```

## 문제 해결

### Graph API 인증 오류

플러그인 설정에서 OAuth 정보를 확인하세요:
- 관리 > 플러그인 > Redmine Tx Office365 plugin > 설정

필요한 정보:
- Tenant ID
- Client ID
- Client Secret
- SharePoint Site URL

### 특정 이슈 GUID 추출 실패

Rails console에서 직접 확인:
```ruby
issue = Issue.find(이슈번호)
TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)
Office365Storage.get("DOC.#{issue.id}")
```
