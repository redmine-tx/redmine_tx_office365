require File.expand_path('../../test_helper', __FILE__)

class Office365StorageTest < ActiveSupport::TestCase
  fixtures :office365_storages

  def setup
    Office365Storage.delete_all
  end

  test "should set and get string value" do
    Office365Storage.set('test_key', 'test_value')
    assert_equal 'test_value', Office365Storage.get('test_key')
  end

  test "should set and get integer value" do
    Office365Storage.set('count', 42)
    assert_equal 42, Office365Storage.get('count')
    assert_instance_of Integer, Office365Storage.get('count')
  end

  test "should set and get float value" do
    Office365Storage.set('price', 19.99)
    assert_equal 19.99, Office365Storage.get('price')
    assert_instance_of Float, Office365Storage.get('price')
  end

  test "should set and get boolean value" do
    Office365Storage.set('enabled', true)
    assert_equal true, Office365Storage.get('enabled')
    
    Office365Storage.set('disabled', false)
    assert_equal false, Office365Storage.get('disabled')
  end

  test "should set and get hash value" do
    data = { name: 'Test', count: 100 }
    Office365Storage.set('config', data)
    result = Office365Storage.get('config')
    assert_equal 'Test', result['name']
    assert_equal 100, result['count']
  end

  test "should set and get array value" do
    data = [1, 2, 3, 4, 5]
    Office365Storage.set('numbers', data)
    assert_equal data, Office365Storage.get('numbers')
  end

  test "should delete value" do
    Office365Storage.set('temp', 'value')
    assert Office365Storage.exists?('temp')
    
    Office365Storage.delete('temp')
    assert_not Office365Storage.exists?('temp')
    assert_nil Office365Storage.get('temp')
  end

  test "should return all keys" do
    Office365Storage.set('key1', 'value1')
    Office365Storage.set('key2', 'value2')
    Office365Storage.set('key3', 'value3')
    
    keys = Office365Storage.keys
    assert_includes keys, 'key1'
    assert_includes keys, 'key2'
    assert_includes keys, 'key3'
  end

  test "should get multiple values" do
    Office365Storage.set('a', 1)
    Office365Storage.set('b', 2)
    Office365Storage.set('c', 3)
    
    result = Office365Storage.get_multi('a', 'b', 'c')
    assert_equal({ 'a' => 1, 'b' => 2, 'c' => 3 }, result)
  end

  test "should set multiple values" do
    Office365Storage.set_multi({
      'x' => 10,
      'y' => 20,
      'z' => 30
    })
    
    assert_equal 10, Office365Storage.get('x')
    assert_equal 20, Office365Storage.get('y')
    assert_equal 30, Office365Storage.get('z')
  end

  test "should increment counter" do
    Office365Storage.set('counter', 0)
    
    Office365Storage.increment('counter')
    assert_equal 1, Office365Storage.get('counter')
    
    Office365Storage.increment('counter', by: 5)
    assert_equal 6, Office365Storage.get('counter')
  end

  test "should decrement counter" do
    Office365Storage.set('counter', 10)
    
    Office365Storage.decrement('counter')
    assert_equal 9, Office365Storage.get('counter')
    
    Office365Storage.decrement('counter', by: 3)
    assert_equal 6, Office365Storage.get('counter')
  end

  test "should increment non-existent key from zero" do
    Office365Storage.increment('new_counter')
    assert_equal 1, Office365Storage.get('new_counter')
  end

  test "should update existing value" do
    Office365Storage.set('key', 'old_value')
    assert_equal 'old_value', Office365Storage.get('key')
    
    Office365Storage.set('key', 'new_value')
    assert_equal 'new_value', Office365Storage.get('key')
  end

  test "should set description" do
    Office365Storage.set('documented_key', 'value', description: 'This is a test key')
    record = Office365Storage.find_by(key: 'documented_key')
    assert_equal 'This is a test key', record.description
  end

  test "should enforce unique key constraint" do
    Office365Storage.create!(key: 'unique_key', value: 'value1')
    
    assert_raises(ActiveRecord::RecordInvalid) do
      Office365Storage.create!(key: 'unique_key', value: 'value2')
    end
  end

  test "should validate key presence" do
    record = Office365Storage.new(value: 'value')
    assert_not record.valid?
    assert_includes record.errors[:key], "can't be blank"
  end

  test "should validate value_type inclusion" do
    record = Office365Storage.new(key: 'test', value: 'value', value_type: 'invalid')
    assert_not record.valid?
    assert_includes record.errors[:value_type], "is not included in the list"
  end
end

