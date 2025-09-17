class FakeRedis
  Entry = Struct.new(:value, :expires_at)

  def initialize
    @store = {}
  end

  def setex(key, ttl, value)
    write(key, value, ttl)
    "OK"
  end

  def set(key, value, ex: nil)
    ttl = ex.nil? ? nil : ex.to_i
    write(key, value, ttl)
    "OK"
  end

  def get(key)
    entry = @store[key.to_s]
    return nil unless entry

    if entry.expires_at && Time.now >= entry.expires_at
      @store.delete(key.to_s)
      return nil
    end

    entry.value
  end

  def getdel(key)
    key = key.to_s
    value = get(key)
    @store.delete(key)
    value
  end

  def del(*keys)
    keys.flatten.sum do |key|
      @store.delete(key.to_s) ? 1 : 0
    end
  end

  def ttl(key)
    entry = @store[key.to_s]
    return -2 unless entry
    return -1 unless entry.expires_at

    remaining = (entry.expires_at - Time.now).ceil
    if remaining <= 0
      @store.delete(key.to_s)
      -2
    else
      remaining
    end
  end

  def exists?(key)
    !get(key).nil?
  end

  private

  def write(key, value, ttl)
    expires_at = ttl && ttl > 0 ? Time.now + ttl : nil
    @store[key.to_s] = Entry.new(value.to_s, expires_at)
  end
end
