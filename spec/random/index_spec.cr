require "../spec_helper"

module V1::Random
  it "Test Random Index" do
    ri = index(1024, 5, 3)

    manifest = ri.index_manifest
    if manifest.nil?
      fail "Error reading manifest"
    else
      manifest.manifests.each_with_index do |desc, _|
        img = ri.image(desc.digest)
        digest = img.digest

        digest.to_s.should eq(desc.digest.to_s)
      end
    end

    digest = ri.digest

    expect_raises(Exception) do
      ri.image(digest)
      ri.image_index(digest)
    end

    ri.media_type.should eq(Types::OCIIMAGEINDEX)
  end
end
