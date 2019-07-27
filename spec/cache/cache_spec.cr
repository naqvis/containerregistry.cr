require "../spec_helper"
require "./cache_helper"

module V1::Cache
  it "Test Cache that the cache is populated when layer_by_digest is called" do
    num_layers = 5_i64
    img = Random.image(10, num_layers)
    m = MemCache.new
    img = image(img, m)

    # Cache is empty
    fail "Before consuming, cache is non-empty: #{m.size}" if m.size > 0

    # Consume each layer, cache gets populated
    _ = img.layers
    got, want = m.size, num_layers
    fail "Cache has #{got} entries, want #{want}" if got != want
  end

  it "Test Cache Short circuit that if a layer is found in the cache, layer_by_digest is not called" do
    fake_hash = V1::Hash.new("fake", "data")
    l = FakeLayer.new
    m = MemCache.new(::Hash{fake_hash => l.as(V1::Layer)})
    img = image(FakeImage.new, m)

    [0..10].each_with_index do |i|
      begin
        _ = img.layer_by_digest(fake_hash)
      rescue ex
        fail "layer_by_digest[#{i}]: #{ex.message}"
      end
    end
  end
end
