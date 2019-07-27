require "../spec_helper"
require "crystar"

module V1::Stream
  it "Test Stream Vs Buffer" do
    n, want_size = 10000, 46
    new_blob = Proc(IO).new { V1::Util::NoOpCloser.new(IO::Memory.new("a" * n)) }
    # want_digest = "sha256:3d7c465be28d9e1ed810c42aeb0e747b44441424f566722ba635dc93c947f30e"
    want_diff_id = "sha256:27dd1f61b867b6a0f6e9d8a41c43231de52107e53ae424de8f847b821db4b711"

    # Check that stream some content results in the expected digest/diff_id/size
    l = Layer.new(new_blob.call)
    c = l.compressed
    _ = V1::Util.read_all(c)
    c.close

    # Unable to verify `#digest` as Gzip::Writer header contains modification time, which changes on each run
    # so just call `#digest` method to ensure digest is calculated on compressed stream
    l.digest

    d = l.diff_id
    d.to_s.should eq(want_diff_id)
    s = l.size
    s.should eq(want_size)

    # Test that buffer the same contents and using Tarball::Layer.from_opener results in same digest/diff_id/size
    tl = Tarball::Layer.from_opener new_blob
    tl.digest
    tl.diff_id.to_s.should eq(want_diff_id)
    tl.size.should eq(want_size)
  end

  it "Test Large Stream" do
    n, want_size = 10000000, 10003073 # "Compressing" n random bytes results in this many bytes.
    new_blob = Proc(IO).new { V1::Util::NoOpCloser.new(IO::Sized.new(IO::Memory.new(::Random::Secure.random_bytes n), n)) }

    # Check that stream some content results in the expected digest/diff_id/size
    l = Layer.new(new_blob.call)
    c = l.compressed
    _ = V1::Util.read_all(c)
    c.close

    (l.digest.to_s != V1::Hash.empty.to_s).should be_true
    (l.diff_id.to_s != V1::Hash.empty.to_s).should be_true
    l.size.should eq(want_size)
  end

  it "Test Streamable Layer from Tarball" do
    pr, pw = IO.pipe
    spawn do
      # Stream a bunch of files into the layer
      Crystar::Writer.open(pw) do |tw|
        [0...1000].each do |i|
          name = "file-#{i}.txt"
          body = "i am file number #{i}"
          tw.write_header Crystar::Header.new(
            name: name,
            mode: 0o0600_i64,
            size: body.size.to_i64,
            flag: Crystar::REG.ord.to_u8
          )
          tw.write body.to_slice
        end
      end
      pw.close
    end
    Fiber.yield
    l = Layer.new(pr)
    rc = l.compressed
    _ = V1::Util.read_all(rc)
    rc.close

    want_diff_id = "sha256:0bc9b625944428111b66d80c2c2f234670c9c745940794f851e84a4f46f3a282"
    l.digest
    l.diff_id.to_s.should eq(want_diff_id)
  end

  it "Test Not Computed" do
    l = Layer.new V1::Util::NoOpCloser.new IO::Memory.new "hi"

    # All methods should return ExNotComputed until the stream has been consumed and closed.
    expect_raises(ExNotComputed, "value not computed until stream is consumed") do
      l.size
    end
    expect_raises(ExNotComputed, "value not computed until stream is consumed") do
      l.digest
    end
    expect_raises(ExNotComputed, "value not computed until stream is consumed") do
      l.diff_id
    end
  end

  it "Test Consumed" do
    l = Layer.new V1::Util::NoOpCloser.new IO::Memory.new "hello"
    rc = l.compressed
    _ = V1::Util.read_all(rc)
    rc.close
    # ExConsumed should be raised here
    expect_raises(ExConsumed, "stream was already consumed") do
      l.compressed
    end
  end

  it "Test Media Type" do
    l = Layer.new V1::Util::NoOpCloser.new IO::Memory.new "hello"
    l.media_type.should eq (Types::DOCKERLAYER)
  end
end
