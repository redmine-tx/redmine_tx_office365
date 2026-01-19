class FixOffice365StoragesEncoding < ActiveRecord::Migration[5.2]
  def up
    # MySQL에서 UTF-8 한글 지원을 위해 컬럼 인코딩 변경
    if ActiveRecord::Base.connection.adapter_name.downcase.include?('mysql')
      execute "ALTER TABLE office365_storages MODIFY description TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
      execute "ALTER TABLE office365_storages MODIFY value TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    end
  end

  def down
    # 롤백은 필요 없음 (인코딩 변경은 안전함)
  end
end

