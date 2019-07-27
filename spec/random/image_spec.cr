require "../spec_helper"

module V1::Random
  it "Test Manifest and Config" do
    want = 12_i64
    img = Random.image(1024, want)

    manifest = img.manifest
    if (m = manifest)
      m.layers.size.should eq(want)
    else
      fail "Error loading manifest"
    end

    config = img.config_file
    config.rootfs.diff_ids.size.should eq(want)
  end

  it "Test Tar Layer" do
    img = Random.image(1024, 5)
    layers = img.layers
    layers.size.should eq(5)
    layers.each_with_index do |l, _|
      l.media_type.should eq(Types::DOCKERLAYER)
      rc = l.uncompressed
      Crystar::Reader.open(rc) do |tr|
        hdr = tr.next_entry
        if (h = hdr)
          b = V1::Util.read_all(h.io)
          b.size.should eq(1024)
        else
          fail "No entry in tar"
        end
        hdr = tr.next_entry
        if !hdr.nil?
          fail "Layer contained more files. want EOF"
        end
      end
      rc.close
    end
  end
end
