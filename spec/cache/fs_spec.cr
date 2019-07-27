require "../spec_helper"
require "file_utils"

module V1::Cache
  it "Test Filesystem Cache" do
    dir = V1::Util.temp_dir("cr-cache")
    begin
      num_layers = 5_i64
      img = Random.image(10, num_layers)
      c = FileSystemCache.new(dir)
      img = image(img, c)

      # Read all the (compressed) layers to populate the cache.
      ls = img.layers
      ls.each do |l|
        rc = l.compressed
        _ = V1::Util.read_all(rc)
        rc.close
      end

      # Check that layer exists in the fs cache
      files = V1::Util.read_dir(dir)
      got, want = files.size, num_layers
      fail "Got #{got} cached files, want #{want}" unless got == want
      files.each do |fi|
        p = Path[dir, fi].to_s
        fail "Cached file #{p} is empty" unless File.size(p) > 0
      end

      # Read all (uncompressed) layers, those populate the cache too.
      ls.each_with_index do |l, _|
        rc = l.uncompressed
        _ = V1::Util.read_all(rc)
        rc.close
      end

      # Check that double the layers are present now, both compressed and uncompressed
      files = V1::Util.read_dir(dir)
      got, want = files.size, num_layers*2
      fail "Got #{got} cached files, want #{want}" unless got == want
      files.each do |fi|
        p = Path[dir, fi].to_s
        fail "Cached file #{p} is empty" unless File.size(p) > 0
      end

      # Delete a cached layer, see it disappear.
      l = ls[0]
      h = l.digest
      c.delete h
      files = V1::Util.read_dir(dir)
      got, want = files.size, num_layers*2 - 1
      fail "Got #{got} cached files, want #{want}" unless got == want

      # Read the image again, see the layer reappear
      ls.each_with_index do |layer, _|
        rc = layer.compressed
        _ = V1::Util.read_all(rc)
        rc.close
      end

      # Check that layer exist in the fs cache
      files = V1::Util.read_dir(dir)
      got, want = files.size, num_layers*2
      fail "Got #{got} cached files, want #{want}" unless got == want
      files.each do |fi|
        p = Path[dir, fi].to_s
        fail "Cached file #{p} is empty" unless File.size(p) > 0
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "Test Filesystem Cache" do
    dir = V1::Util.temp_dir("cr-cache")
    begin
      c = FileSystemCache.new(dir)
      h = V1::Hash.new("fake", "not-found")
      expect_raises(LayerNotFound, "layer was not found") do
        c.get h
      end
      expect_raises(LayerNotFound, "layer was not found") do
        c.delete h
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
