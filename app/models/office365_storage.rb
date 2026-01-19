class Office365Storage < ActiveRecord::Base
  validates :key, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :value_type, inclusion: { in: %w[string integer float boolean json] }

  # Key-Value 스토어 인터페이스
  class << self
    # 값 조회
    def get(key)
      record = find_by(key: key.to_s)
      return nil unless record
      deserialize_value(record.value, record.value_type)
    end

    # 값 저장
    def set(key, value, description: nil)
      key = key.to_s
      value_type, serialized_value = serialize_value(value)
      
      record = find_or_initialize_by(key: key)
      record.value = serialized_value
      record.value_type = value_type
      record.description = description if description
      record.save!
      value
    end

    # 값 삭제
    def delete(key)
      where(key: key.to_s).delete_all
    end

    # 키 존재 확인
    def exists?(key)
      exists?(key: key.to_s)
    end

    # 모든 키 조회
    def keys
      pluck(:key)
    end

    # 여러 값 조회
    def get_multi(*keys)
      keys = keys.map(&:to_s)
      records = where(key: keys).index_by(&:key)
      keys.each_with_object({}) do |key, hash|
        if record = records[key]
          hash[key] = deserialize_value(record.value, record.value_type)
        end
      end
    end

    # 여러 값 저장
    def set_multi(hash, description: nil)
      hash.each do |key, value|
        set(key, value, description: description)
      end
    end

    # 값 증가 (integer만 가능)
    def increment(key, by: 1)
      record = find_or_initialize_by(key: key.to_s)
      current_value = record.persisted? ? deserialize_value(record.value, record.value_type).to_i : 0
      new_value = current_value + by
      set(key, new_value)
    end

    # 값 감소 (integer만 가능)
    def decrement(key, by: 1)
      increment(key, by: -by)
    end

    private

    def serialize_value(value)
      case value
      when Integer
        ['integer', value.to_s]
      when Float
        ['float', value.to_s]
      when TrueClass, FalseClass
        ['boolean', value.to_s]
      when Hash, Array
        ['json', value.to_json]
      else
        ['string', value.to_s]
      end
    end

    def deserialize_value(value, type)
      return nil if value.nil?

      case type
      when 'integer'
        value.to_i
      when 'float'
        value.to_f
      when 'boolean'
        value == 'true'
      when 'json'
        JSON.parse(value) rescue value
      else
        value
      end
    end
  end
end

