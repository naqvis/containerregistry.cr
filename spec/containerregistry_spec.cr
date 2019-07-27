require "./spec_helper"
require "uri"

describe Containerregistry do
  describe "authn" do
    it "test anonymous authorization" do
      a = Authn::ANONYMOUS
      a.authorization.should eq("")
    end

    it "test basic authorization from json" do
      b = Authn::Basic.new("foo", "bar")
      b.authorization.should eq("Basic Zm9vOmJhcg==")
    end

    it "test bearer authorization" do
      b = Authn::Bearer.new("bazinga")
      b.authorization.should eq("Bearer bazinga")
    end

    it "test bearer authorization from json" do
      b = Authn::Bearer.from_json(%({"token": "bazinga"}))
      b.authorization.should eq("Bearer bazinga")
    end
  end

  describe "name" do
    it "test url" do
      url = "123"
      uri = URI.parse("//#{url}")
      uri.host.should eq(url)
    end

    it "test repo" do
      repo = "registry.ng.bluemix.net/epm-sales/financial-facts-tactical-job"
      r = Name::Repository.new(repo)
      r.repo_str.should eq("epm-sales/financial-facts-tactical-job")
    end

    it "test tag without value" do
      repo = "registry.ng.bluemix.net/epm-sales/financial-facts-tactical-job"
      t = Name::Tag.new(repo, strict: false)
      t.tag.should eq("latest")
    end

    it "test tag with value" do
      repo = "registry.ng.bluemix.net/epm-sales/financial-facts-tactical-job:1.3"
      t = Name::Tag.new(repo)
      t.tag.should eq("1.3")
    end

    it "test digest without value" do
      expect_raises(Name::BadNameException) do
        repo = "registry.ng.bluemix.net/epm-sales/financial-facts-tactical-job"
        Name::Digest.new(repo)
      end
    end
  end
  describe "V1" do
    it "test manifest simple" do
      expect_raises(JSON::MappingError) do
        V1.parse_manifest(IO::Memory.new("{}"))
      end
    end

    it "test manifest with hash" do
      json = <<-JSON
    { "schemaVersion": 2, "mediaType": "application/vnd.docker.distribution.manifest.v2+json", "config": { "mediaType":
"application/vnd.docker.container.image.v1+json", "size": 7023, "digest":
"sha256:b5b2b2c507a0944348e0303114d8d93aaaa081732b86451d9bce1f432a537bc7" }, "layers": [ { "mediaType":
"application/vnd.docker.image.rootfs.diff.tar.gzip", "size": 32654, "digest":
"sha256:e692418e4cbaf90ca69d05a66403747baa33ee08806650b51fab815ad7fc331f" }, { "mediaType":
"application/vnd.docker.image.rootfs.diff.tar.gzip", "size": 16724, "digest":
"sha256:3c3a4604a545cdc127456d94e421cd355bca5b528f4a9c1905b15da2eb4a4c6b" }, { "mediaType":
"application/vnd.docker.image.rootfs.diff.tar.gzip", "size": 73109, "digest":
"sha256:ec4b8955958665577945c89419d1af06b5f7636b4ac3da7f12184802ad867736" } ] }
JSON
      V1.parse_manifest(IO::Memory.new(json))
    end
  end

  describe "V1::Util" do
    it "test reader" do
      want = "This is the input string."
      zipped = V1::Util.gzip_reader_closer(IO::Memory.new want)
      unzipped = V1::Util.gunzip_reader_closer zipped
      unzipped.gets_to_end.should eq want
    end

    it "test is gzipped" do
      tests = [
        {in: Bytes.new(0), out: false},
        {in: Bytes[0x0, 0x0, 0x0], out: false},
        {in: Bytes[0x1f, 0x8b, 0x1b], out: true},
      ]

      tests.each_with_index do |t, _|
        r = IO::Memory.new(t[:in])
        got = V1::Util.is_gzipped r
        t[:out].should eq got
      end
    end

    it "test verifcation failure" do
      want = "This is the input string."
      buf = IO::Memory.new(want)
      expect_raises(Exception) do
        verified = V1::Util.verify_read_closer(buf,
          must_hash("no the same"))
        verified.gets_to_end
      end
    end

    it "test verification" do
      want = "This is the input string."
      buf = IO::Memory.new(want)
      verified = V1::Util.verify_read_closer(buf, must_hash(want))
      verified.gets_to_end.should eq(want)
    end
  end
end
