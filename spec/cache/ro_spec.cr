require "../spec_helper"
require "./cache_helper"

module V1::Cache
  it "Test Read Only Cacher" do
    m = MemCache.new
    ro = ReadOnly.new(m)
    # Populate the cache.
    img = Random.image(10, 1)
    img = image(img, m)
    ls = img.layers
    got, want = ls.size, 1
    fail "Layers returned #{got} layers, want #{want}" unless got == want

    h = ls[0].digest
    m.m[h] = ls[0]

    # Layer can be read from original cache and RO cache.
    m.get h
    ro.get h
    ln = m.size

    # RO put is a no-op
    ro.put(ls[0])
    got, want = m.size, ln
    fail "After put, got #{got} entries, want #{want}" unless got == want

    # RO delete is a no-op
    ro.delete h
    got, want = m.size, ln
    fail "After delete, got #{got} entries, want #{want}" unless got == want

    # Deleting from the underlying RW cache updates RO view.
    m.delete h
    got, want = m.size, 0
    fail "After RW delete, got #{got} entries, want #{want}" unless got == want
  end
end
