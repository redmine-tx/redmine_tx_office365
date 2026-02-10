namespace :office365 do
  desc "SharePoint URL에서 GUID 추출 및 저장 (기간 지정 가능)"
  task :migrate_sharepoint_guids, [:dry_run, :force, :period] => :environment do |t, args|
    dry_run = args[:dry_run] == 'true'
    force = args[:force] == 'true'
    period = args[:period] || '2months' # 기본값: 2개월

    puts "=" * 80
    puts "SharePoint GUID 일괄 추출 및 저장"
    puts "=" * 80
    puts "모드: #{dry_run ? 'DRY RUN (실제로 저장하지 않음)' : 'PRODUCTION (실제 저장)'}"
    puts "강제 업데이트: #{force ? '예 (기존 GUID도 재추출)' : '아니오 (새 GUID만 추출)'}"
    puts "=" * 80
    puts ""

    # 기간별 이슈 조회
    if period == 'all'
      issues = Issue.where('description LIKE ?', '%sharepoint.com%').order(:id)
      period_desc = "전체"
    else
      # 숫자 추출 (예: "2months" → 2, "6months" → 6)
      months = period.to_i
      months = 2 if months <= 0 # 기본값

      cutoff_date = months.months.ago
      issues = Issue.where('updated_on >= ?', cutoff_date)
                    .where('description LIKE ?', '%sharepoint.com%')
                    .order(:id)
      period_desc = "최근 #{months}개월"
    end

    total_count = issues.count
    puts "대상 이슈: #{total_count}건 (#{period_desc} + SharePoint URL 포함)"
    puts ""

    if total_count == 0
      puts "처리할 이슈가 없습니다."
      exit
    end

    # 통계
    stats = {
      total: total_count,
      processed: 0,
      success: 0,
      skipped: 0,
      failed: 0,
      no_url: 0
    }

    # 진행 상황 표시
    progress_interval = [total_count / 20, 1].max

    issues.find_each.with_index do |issue, index|
      begin
        # 진행 상황 표시
        if (index + 1) % progress_interval == 0 || index == 0 || index == total_count - 1
          percentage = ((index + 1).to_f / total_count * 100).round(1)
          print "\r처리 중: #{index + 1}/#{total_count} (#{percentage}%)  "
        end

        stats[:processed] += 1

        # SharePoint URL 추출
        sharepoint_urls = issue.description.scan(%r{https://[^/\s]+\.sharepoint\.com/[^\s]+})

        if sharepoint_urls.empty?
          stats[:no_url] += 1
          next
        end

        # 기존 GUID 확인
        existing_data = Office365Storage.get("DOC.#{issue.id}")
        if existing_data && !force
          stats[:skipped] += 1
          next
        end

        # GUID 추출 시도
        if dry_run
          # Dry run: 추출만 하고 저장하지 않음
          url = sharepoint_urls.first
          guid = TxOffice365Hooks.extract_guid_from_url(url)

          unless guid
            # Graph API 시도 (실제 호출은 하지 않음)
            puts "\n  이슈 ##{issue.id}: Graph API 호출 필요 - #{url[0..60]}..."
          end

          stats[:success] += 1
        else
          # 실제 저장
          TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)

          # 저장 확인
          new_data = Office365Storage.get("DOC.#{issue.id}")
          if new_data
            stats[:success] += 1
          else
            stats[:failed] += 1
          end
        end

      rescue => e
        stats[:failed] += 1
        puts "\n  에러 - 이슈 ##{issue.id}: #{e.class} - #{e.message}"
      end
    end

    # 최종 결과 출력
    puts "\n"
    puts "=" * 80
    puts "처리 완료"
    puts "=" * 80
    puts "총 이슈 수:           #{stats[:total]}건"
    puts "처리된 이슈:          #{stats[:processed]}건"
    puts "성공:                 #{stats[:success]}건"
    puts "건너뜀 (기존 GUID):   #{stats[:skipped]}건" unless force
    puts "실패:                 #{stats[:failed]}건"
    puts "URL 없음:             #{stats[:no_url]}건"
    puts "=" * 80

    if dry_run
      puts ""
      puts "⚠️  DRY RUN 모드였습니다. 실제로 저장되지 않았습니다."
      puts ""
      puts "실행 예시:"
      puts "  최근 2개월: bundle exec rake office365:migrate_sharepoint_guids[false,false,2months]"
      puts "  최근 6개월: bundle exec rake office365:migrate_sharepoint_guids[false,false,6months]"
      puts "  전체 이슈:  bundle exec rake office365:migrate_sharepoint_guids[false,true,all]"
    end
  end

  desc "전체 이슈의 SharePoint GUID 마이그레이션 (단축 명령어)"
  task :migrate_all, [:dry_run] => :environment do |t, args|
    dry_run = args[:dry_run] == 'true'

    puts "전체 이슈 마이그레이션을 시작합니다..."
    puts ""

    Rake::Task['office365:migrate_sharepoint_guids'].invoke(
      dry_run.to_s,
      'true',  # force=true (기존 GUID도 재추출)
      'all'    # period=all
    )
  end

  desc "특정 이슈의 SharePoint GUID 추출 (예: rake office365:extract_guid[12345])"
  task :extract_guid, [:issue_id] => :environment do |t, args|
    issue_id = args[:issue_id]

    unless issue_id
      puts "사용법: bundle exec rake office365:extract_guid[이슈번호]"
      exit
    end

    issue = Issue.find(issue_id)

    puts "이슈 ##{issue.id}: #{issue.subject}"
    puts "본문: #{issue.description[0..200]}..."
    puts ""

    TxOffice365Hooks.extract_and_store_sharepoint_guid(issue)

    stored = Office365Storage.get("DOC.#{issue.id}")
    if stored
      puts "✓ 성공!"
      if stored.is_a?(Hash)
        puts "  GUID: #{stored['guid']}"
        puts "  사이트 ID: #{stored['site_id']}" if stored['site_id']
      else
        puts "  GUID: #{stored}"
      end
    else
      puts "✗ 실패 - GUID를 추출하지 못했습니다."
    end
  end

  desc "SharePoint GUID 통계 조회"
  task :stats => :environment do
    puts "=" * 80
    puts "SharePoint GUID 저장 통계"
    puts "=" * 80
    puts ""

    total_issues = Issue.count
    issues_with_url = Issue.where('description LIKE ?', '%sharepoint.com%').count
    stored_guids = Office365Storage.where('key LIKE ?', 'DOC.%').count

    puts "전체 이슈 수:                    #{total_issues}건"
    puts "SharePoint URL 포함 이슈:        #{issues_with_url}건"
    puts "GUID 저장된 이슈:                #{stored_guids}건"
    puts ""

    # 최근 업데이트
    recent = Office365Storage.where('key LIKE ?', 'DOC.%')
                             .order(updated_at: :desc)
                             .limit(10)

    if recent.any?
      puts "최근 업데이트된 GUID (최근 10건):"
      recent.each do |storage|
        issue_id = storage.key.sub('DOC.', '')
        issue = Issue.find_by(id: issue_id)
        if issue
          data = JSON.parse(storage.value) rescue storage.value
          guid = data.is_a?(Hash) ? data['guid'] : data
          puts "  이슈 ##{issue_id}: #{guid[0..20]}... (#{storage.updated_at.strftime('%Y-%m-%d %H:%M')})"
        end
      end
    end

    puts "=" * 80
  end
end
