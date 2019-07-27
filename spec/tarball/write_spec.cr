require "../spec_helper"
require "file_utils"

module V1::Tarball
  it "Test Write" do
    # Make a tempfile for tarball writes.
    fp = File.tempfile "", ""
    begin
      rand_image = Random.image(256, 8)
      tag = Name::Tag.new "gcr.io/foo/bar:latest", strict: true
      write_to_file fp.path, tag, rand_image

      # Make sure the image is valid and can be loaded.
      # Load it both by nil and by its name
      [nil, tag].each do |it|
        tar_img = image_from_path fp.path, it
        mf = tar_img.manifest
        rmf = rand_image.manifest
        # mf.to_json.should eq(rmf.to_json)

        assert_image_layers_match_manifest_layers tar_img
        assert_layers_are_identical rand_image, tar_img
      end

      # Try loading a different tag, it should error.
      fake_tag = Name::Tag.new "gcr.io/nothistag:latest", strict: true
      expect_raises(Exception, "tag gcr.io/nothistag:latest not found in tarball.") do
        image_from_path fp.path, fake_tag
      end
    ensure
      fp.delete
    end
  end

  it "Test Multi Write Same Image" do
    # Make a tempfile for tarball writes.
    fp = File.tempfile "", ""
    begin
      rand_image = Random.image(256, 8)
      tag = Name::Tag.new "gcr.io/foo/bar:latest", strict: true
      tag2 = Name::Tag.new "gcr.io/baz/bat:latest", strict: true

      dig3 = Name::Digest.new "gcr.io/baz/baz@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", strict: true

      ref_to_image = ::Hash{tag => rand_image, tag2 => rand_image, dig3 => rand_image}

      # Write the images with both tags to the tarball
      multi_ref_write_to_file fp.path, ref_to_image

      ref_to_image.each do |ref, _|
        next unless ref.is_a?(Name::Tag)
        tar_img = image_from_path fp.path, ref.as(Name::Tag)
        mf = tar_img.manifest
        rmf = rand_image.manifest
        mf.should eq(rmf)
        assert_image_layers_match_manifest_layers tar_img
        assert_layers_are_identical rand_image, tar_img
      end
    ensure
      fp.delete
    end
  end

  it "Test Multi Write Different Image" do
    # Make a tempfile for tarball writes.
    fp = File.tempfile "", ""
    begin
      rand_image1 = Random.image(256, 8)
      rand_image2 = Random.image(256, 8)
      rand_image3 = Random.image(256, 8)

      # Create two tags, one pointing to each image created.
      tag = Name::Tag.new "gcr.io/foo/bar:latest", strict: true
      tag2 = Name::Tag.new "gcr.io/baz/bat:latest", strict: true

      dig3 = Name::Digest.new "gcr.io/baz/baz@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", strict: true

      ref_to_image = ::Hash{tag => rand_image1, tag2 => rand_image2, dig3 => rand_image3}

      # Write both images to the tarball
      multi_ref_write_to_file fp.path, ref_to_image

      ref_to_image.each do |ref, img|
        next unless ref.is_a?(Name::Tag)
        tar_img = image_from_path fp.path, ref.as(Name::Tag)
        mf = tar_img.manifest
        rmf = img.manifest
        mf.should eq(rmf)
        assert_image_layers_match_manifest_layers tar_img
        assert_layers_are_identical img, tar_img
      end
    ensure
      fp.delete
    end
  end

  def assert_image_layers_match_manifest_layers(img)
    layers = img.layers
    digests_from_image = Array(V1::Hash).new(layers.size)
    layers.each { |l| digests_from_image << l.digest }
    m = img.manifest
    if m.nil?
      fail "error getting layers to compare: #{img}"
    end
    digests_from_manifest = Array(V1::Hash).new(m.layers.size)
    m.layers.each { |l| digests_from_manifest << l.digest }

    if digests_from_image != digests_from_manifest
      fail "image.layers are not in same order as the image.manifest.layers"
    end
  end

  def assert_layers_are_identical(src, res)
    al = src.layers
    bl = src.layers
    ad = get_digests al
    bd = get_digests bl
    fail "layers digests are not identical" if ad != bd

    ad = get_diff_ids al
    bd = get_diff_ids bl
    fail "layers diff_ids are not identical" if ad != bd
  end

  def get_digests(l)
    digests = Array(V1::Hash).new(l.size)
    l.each { |a| digests << a.digest }
    digests
  end

  def get_diff_ids(l)
    diff_ids = Array(V1::Hash).new(l.size)
    l.each { |a| diff_ids << a.digest }
    diff_ids
  end
end
