require "../spec_helper"

module V1::Tarball
  it "Test Manifest and Config" do
    img = image_from_path("spec/tarball/testdata/test_image_1.tar", nil)
    manifest = img.manifest
    if manifest.nil?
      fail "Unable to get manifest"
    else
      manifest.layers.size.should eq(1)
      config = img.config_file
      config.history.try &.size.should eq(1)
    end
  end

  it "Test No Manifest" do
    expect_raises(Exception, "file manifest.json not found in tar") do
      image_from_path("spec/tarball/testdata/no_manifest.tar", nil)
    end
  end

  it "Test Bundle Single" do
    expect_raises(Exception, "tarball must contain only a single image to be used with Tarball.image") do
      image_from_path("spec/tarball/testdata/test_bundle.tar", nil)
    end
  end

  it "Test Bundle Tag" do
    tag = Name::Tag.new "test_image_1", strict: false
    img = image_from_path("spec/tarball/testdata/test_bundle.tar", tag)
    img.manifest
  end

  it "Test Bundle multiple" do
    vectors = [
      "test_image_1",
      "test_image_2",
      "test_image_1:latest",
      "test_image_2:latest",
      "index.docker.io/library/test_image_1:latest",
    ]

    vectors.each_with_index do |v, _|
      tag = Name::Tag.new(v, false)
      img = image_from_path("spec/tarball/testdata/test_bundle.tar", tag)
      img.manifest
    end
  end
end
