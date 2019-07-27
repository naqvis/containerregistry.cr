require "../spec_helper"
require "gzip"
require "file_utils"

module V1::Tarball
  # Compression settings matter in order for the digest, size,
  # compressed assertions to pass
  #
  # Since our v1util.GzipReadCloser uses gzip.BestSpeed
  # we need our fixture to use the same - bazel's pkg_tar doesn't
  # seem to let you control compression settings
  def setup
    File.open("spec/tarball/testdata/content.tar", "r") do |input|
      File.open("gzip_content.tgz", "w") do |output|
        Gzip::Writer.open(output, level: Gzip::BEST_COMPRESSION) do |gzip|
          IO.copy input, gzip
        end
      end
    end
  end

  def teardown
    FileUtils.rm("gzip_content.tgz")
  end

  def assert_digests_are_equal(a : Layer, b : Layer)
    a.digest.should eq(b.digest)
  end

  def assert_diff_ids_are_equal(a : Layer, b : Layer)
    a.diff_id.should eq(b.diff_id)
  end

  def assert_compressed_stream_are_equal(a : Layer, b : Layer)
    sa = a.compressed
    sa_bytes = V1::Util.read_all(sa)

    sb = b.compressed
    sb_bytes = V1::Util.read_all(sb)

    sa_bytes.should eq(sb_bytes)
  end

  def assert_uncompressed_stream_are_equal(a : Layer, b : Layer)
    sa = a.uncompressed
    sa_bytes = V1::Util.read_all(sa)

    sb = b.uncompressed
    sb_bytes = V1::Util.read_all(sb)

    sa_bytes.should eq(sb_bytes)
  end

  def assert_sizes_are_equal(a : Layer, b : Layer)
    a.size.should eq(b.size)
  end

  it "Test Layer From File" do
    setup
    tar_layer = Layer.from_file("spec/tarball/testdata/content.tar")

    tar_gz_layer = Layer.from_file("gzip_content.tgz")
    assert_digests_are_equal tar_layer, tar_gz_layer
    assert_diff_ids_are_equal tar_layer, tar_gz_layer
    assert_compressed_stream_are_equal tar_layer, tar_gz_layer
    assert_uncompressed_stream_are_equal tar_layer, tar_gz_layer
    assert_sizes_are_equal tar_layer, tar_gz_layer
  ensure
    teardown
  end

  it "Test Layer from Opener" do
    setup
    f = File.open("spec/tarball/testdata/content.tar")
    uc_bytes = V1::Util.read_all(f)
    f.close

    uc_opener = Opener.new {
      V1::Util::NoOpCloser.new IO::Memory.new(uc_bytes)
    }

    tar_layer = Layer.from_opener uc_opener
    f = File.open("gzip_content.tgz")
    gz_bytes = V1::Util.read_all(f)
    f.close
    gz_opener = Opener.new {
      V1::Util::NoOpCloser.new IO::Memory.new(gz_bytes)
    }
    tar_gz_layer = Layer.from_opener gz_opener

    assert_digests_are_equal tar_layer, tar_gz_layer
    assert_diff_ids_are_equal tar_layer, tar_gz_layer
    assert_compressed_stream_are_equal tar_layer, tar_gz_layer
    assert_uncompressed_stream_are_equal tar_layer, tar_gz_layer
    assert_sizes_are_equal tar_layer, tar_gz_layer
  ensure
    teardown
  end

  it "Test Layer from Reader" do
    setup
    f = File.open("spec/tarball/testdata/content.tar")
    uc_bytes = V1::Util.read_all(f)
    f.close

    tar_layer = Layer.from_reader IO::Memory.new uc_bytes
    f = File.open("gzip_content.tgz")
    gz_bytes = V1::Util.read_all(f)
    f.close

    tar_gz_layer = Layer.from_reader IO::Memory.new gz_bytes

    assert_digests_are_equal tar_layer, tar_gz_layer
    assert_diff_ids_are_equal tar_layer, tar_gz_layer
    assert_compressed_stream_are_equal tar_layer, tar_gz_layer
    assert_uncompressed_stream_are_equal tar_layer, tar_gz_layer
    assert_sizes_are_equal tar_layer, tar_gz_layer
  ensure
    teardown
  end
end
