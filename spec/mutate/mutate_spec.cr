require "../spec_helper"
require "crystar"

module V1::Mutate
  it "Test Extract Whiteout" do
    img = Tarball.image_from_path("spec/mutate/testdata/whiteout_image.tar", nil)
    Crystar::Reader.open(extract img) do |tr|
      tr.each_entry do |hdr|
        path_sep = {% if flag?(:win32) %} ";" {% else %} ":" {% end %}
        parts = hdr.name.split(path_sep)
        parts.each do |part|
          fail "whiteout file found in tar: #{hdr.name}" if part == "foo"
        end
      end
    end
  end

  it "Test Extract Overwritten File" do
    img = Tarball.image_from_path("spec/mutate/testdata/overwritten_file.tar", nil)
    Crystar::Reader.open(extract img) do |tr|
      tr.each_entry do |hdr|
        if hdr.name.includes?("foo.txt")
          buf = hdr.io.gets_to_end
          fail "Contents of file were not correctly overwritten" if buf.includes?("foo")
        end
      end
    end
  end

  it "Test Whiteout Directory" do
    fs_map = ::Hash{"baz" => true, "red/blue" => true}
    tests = [
      {"usr/bin", false},
      {"baz/foo.txt", true},
      {"baz/bar/foo.txt", true},
      {"red/green", false},
      {"red/yellow.txt", false},
    ]

    tests.each do |test|
      whiteout = in_whiteout_dir(fs_map, test[0])
      whiteout.should eq(test[1])
    end
  end

  it "Test Noop condition" do
    source = source_image
    result = append_layers source, Array(V1::Layer).new

    source.manifest.should eq(result.manifest)
    source.config_file.should eq(result.config_file)
  end

  it "Test Append with History" do
    source = source_image
    add = Addendum.new(
      layer: MockLayer.new,
      history: V1::History.new(author: "Ali")
    )
    result = append source, [add]
    layers = result.layers
    fail "correct layer was not appended." unless layers[1] == MockLayer.new
    fail "adding a layer MUST change the config file size" if config_size_are_equal(source, result)
    cf = get_config_file(result)
    fail "append history is not the same" unless get_history(cf)[1] == add.history
  end

  it "Test Append Layers" do
    source = source_image
    result = append_layers source, [MockLayer.new]

    fail "appending a layer did not mutate the manifest" if manifests_are_equal(source, result)
    fail "adding a layer did not mutate the config file" if config_files_are_equal(source, result)
    fail "adding a layer MUST change the config file size" if config_size_are_equal(source, result)
    layers = result.layers
    layers.size.should eq(2)
    fail "correct layer was not appended." unless layers[1] == MockLayer.new
    assert_layer_order_matches_config result
    assert_layer_order_matches_manifest result
    assert_querying_for_layer_succeeds result.as(Image), layers[1].as(MockLayer)
  end

  it "Test Mutate Config" do
    source = source_image
    cfg = get_config_file(source)
    new_env = ["foo=bar"]
    cfg.config.env = new_env

    result = config(source, cfg.config)
    fail "mutating the config MUST mutate the manifest" if manifests_are_equal(source, result)
    fail "mutating the config did not mutate the config file" if config_files_are_equal(source, result)
    fail "adding an environment variable MUST change the config file size" if config_size_are_equal(source, result)
    fail "mutating the config MUST mutate the config digest" if config_digests_are_equal(source, result)
    assert_accurate_manifest_config_digest result
    fail "incorrect environment set #{cfg.config.env} != #{new_env}" if cfg.config.env != new_env
  end

  it "Test Mutate Created At" do
    source = source_image
    want = Time.utc - Time::Span.new(0, 0, 2, 0, 0)
    result = created_at(source, want)
    fail "mutating the created time MUST mutate the config digest" if config_digests_are_equal(source, result)
    got = get_config_file(result).created
    fail "mutating the created time MUST mutate the time from #{got} to #{want}" if got != want
  end

  it "Test Mutate Time" do
    source = source_image
    want = Time.utc
    result = time(source, want)
    fail "mutating the created time MUST mutate the config digest" if config_digests_are_equal(source, result)
    got = get_config_file(result).created
    fail "mutating the created time MUST mutate the time from #{got} to #{want}" if got != want
  end

  it "Test Layer Time" do
    source = source_image
    layers = get_layers source
    expected_time = Time.local(1970, 1, 1, 0, 0, 1, location: Time::Location::UTC)
    layers.each do |layer|
      result = layer_time layer, expected_time
      assert_m_time result, expected_time
    end
  end

  it "Test Append Streamable Layer" do
    img = append_layers(source_image, [Stream::Layer.new(V1::Util::NoOpCloser.new(IO::Memory.new("a" * 100))),
                                       Stream::Layer.new(V1::Util::NoOpCloser.new(IO::Memory.new("b" * 100))),
                                       Stream::Layer.new(V1::Util::NoOpCloser.new(IO::Memory.new("c" * 100)))])

    # Until the streams are consumed, the image manifest is not yet computed.
    expect_raises(Stream::ExNotComputed, "value not computed until stream is consumed") do
      img.manifest
    end

    # We can still get Layers while some are not yet computed.
    ls = img.layers
    want_diff_ids = [
      "sha256:2816597888e4a0d3a36b82b83316ab32680eb8f00f8cd3b904d681246d285a0e",
      "sha256:d6cbb053abf2933889a0ccbf6ac244623a63a2e3397e991dde09266bdaa932d1",
      "sha256:bdcdc9e9204fe2099666b438af288629b1fa7f89797341bf7d435ce4ca2b706b",
    ]
    ls[1..].each_with_index do |l, i|
      rc = l.compressed
      # Consume the layer's stream and close it to compute the layer's metdata
      _ = V1::Util.read_all rc
      rc.close

      # The layer's metadata is now available.
      l.diff_id.to_s.should eq(want_diff_ids[i])
    end
    # Now that the streamable layers have been consumed, the image's
    # manifest can be computed.
    img.manifest
    img.digest
  end

  # Helper functions #
  # #####
  #
  #

  def assert_m_time(layer, time)
    l = layer.uncompressed
    Crystar::Reader.open(l) do |tr|
      tr.each_entry do |hdr|
        fail "unexpected mod time for layer. expected #{time}, got #{hdr.mod_time}" if time != hdr.mod_time
      end
    end
  end

  def assert_querying_for_layer_succeeds(image : Image, layer : MockLayer)
    query_tests = [
      {name: "digest", expected_layer: layer,
       hash: ->layer.digest, query: ->image.layer_by_digest(V1::Hash)},
      {name: "diff id", expected_layer: layer,
       hash: ->layer.diff_id, query: ->image.layer_by_diff_id(V1::Hash)},
    ]

    query_tests.each do |tc|
      hash = tc[:hash].call
      got_layer = tc[:query].call(hash)
      if got_layer != tc[:expected_layer]
        fail "Query layer using #{tc[:name]} does not return the expected layer #{got_layer}  #{tc[:expected_layer]}"
      end
    end
  end

  def assert_layer_order_matches_config(img)
    layers = get_layers img
    cf = get_config_file img

    got, want = layers.size, cf.rootfs.diff_ids.size
    fail "Difference in size between the image layers (#{got}) and the config file diff ids (#{want})" unless got == want

    layers.each_with_index do |_, i|
      diff_id = layers[i].diff_id
      got, want = diff_id.to_s, cf.rootfs.diff_ids[i].to_s
      fail "Layer diff id (#{got}) is not at the expected index (#{i}) in #{cf.rootfs.diff_ids}" unless got == want
    end
  end

  def assert_layer_order_matches_manifest(img)
    layers = get_layers img
    mf = get_manifest img

    got, want = layers.size, mf.layers.size
    fail "Difference in size between the image layers (#{got}) and the config file diff ids (#{want})" unless got == want

    layers.each_with_index do |_, i|
      digest = layers[i].digest
      got, want = digest.to_s, mf.layers[i].digest.to_s
      fail "Layer diff id (#{got}) is not at the expected index (#{i}) in #{mf.layers}" unless got == want
    end
  end

  def assert_accurate_manifest_config_digest(img)
    m = get_manifest img
    got = m.config.digest
    rcfg = get_raw_config_file img
    want = compute_digest rcfg
    fail "Manifest config digest (#{got}) does not match digest of config file (#{want})" unless got == want
  end

  def compute_digest(data)
    d, _ = V1::Hash.sha256(IO::Memory.new data)
    d
  end

  def get_layers(i)
    l = i.layers
    if l.nil?
      fail "unable to get layers: #{i}"
    else
      l
    end
  end

  def get_history(cf)
    h = cf.history
    if h.nil?
      fail "unable to get history: #{cf}"
    else
      h
    end
  end

  def config_size_are_equal(source, result)
    ms = get_manifest source
    mr = get_manifest result
    ms.config.size == mr.config.size
  end

  def config_digests_are_equal(source, result)
    fail "Invalid image" if source.nil? || result.nil?
    ms = get_manifest source
    mr = get_manifest result
    ms.config.digest == mr.config.digest
  end

  def config_files_are_equal(source, result)
    cs = get_config_file source
    cr = get_config_file result
    cs == cr
  end

  def manifests_are_equal(source, result)
    ms = get_manifest source
    mr = get_manifest result
    ms == mr
  end

  def source_image
    Tarball.image_from_path("spec/mutate/testdata/source_image.tar", nil)
  end

  def get_manifest(img)
    mf = img.manifest
    if mf.nil?
      fail "unable to get manifest: #{img}"
    else
      mf
    end
  end

  def get_config_file(img)
    fail "Invalid image" if img.nil?
    c = img.config_file
    if c.nil?
      fail "Error fetching image config file: #{img}"
    else
      c
    end
  end

  def get_raw_config_file(img)
    c = img.raw_config_file
    if c.nil?
      fail "Error fetching image raw_config file: #{img}"
    else
      c
    end
  end

  private class MockLayer
    include V1::Layer

    def digest
      V1::Hash.empty
    end

    def diff_id
      V1::Hash.empty
    end

    def media_type
      Types::MediaType["some-media-type"]
    end

    def size
      137438691328_i64
    end

    def compressed
      V1::Util::NoOpCloser.new(IO::Memory.new "compressed times")
    end

    def uncompressed
      V1::Util::NoOpCloser.new(IO::Memory.new "uncompressed times")
    end

    def ==(o : self)
      digest == o.digest && diff_id == o.diff_id && size == o.size &&
        compressed.gets_to_end == o.compressed.gets_to_end &&
        uncompressed.gets_to_end == o.uncompressed.gets_to_end
    end
  end
end
