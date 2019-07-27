module V1::Remote
  extend self

  BOGUS_DIGEST = "sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  def must_digest(img : Manifest)
    h = img.digest
    fail "digest failed. " if h.nil?
    h
  end

  def must_manifest(img : V1::Image)
    m = img.manifest
    fail "manifest failed." if m.nil?
    m
  end

  def must_raw_manifest(img)
    m = img.raw_manifest
    fail "raw_manifest failed" if m.nil?
    m
  end

  def must_raw_config_file(img : V1::Image)
    c = img.raw_config_file
    fail "raw_config_file failed" if c.nil?
    c
  end

  def must_config_name(img : V1::Image)
    h = img.config_name
    fail "config_name failed" if h.nil?
    h
  end

  def random_image
    rnd = Random.image(1024, 1)
    fail "Random.image failed" if rnd.nil?
    rnd
  end

  def new_reference(host : String, repo : String, ref : String)
    Name::Tag.new sprintf("%s/%s:%s", host, repo, ref), strict: false
  rescue ex
    Name::Digest.new sprintf("%s/%s@%s", host, repo, ref), strict: false
  end

  def random_index
    rnd = Random.index(1024, 1, 3)
    if rnd.nil?
      fail "Random.index failed"
    end
    rnd
  end

  def must_index_manifest(idx : V1::ImageIndex)
    m = idx.index_manifest
    fail "index_manifest failed" if m.nil?
    m
  end

  def must_child(idx : V1::ImageIndex, h : V1::Hash)
    img = idx.image h
    fail "image failed" if img.nil?
    img
  end

  def must_media_type(man : Manifest)
    mt = man.media_type
    fail "media_type failed" if mt.nil?
    mt
  end

  def must_hash(s : String)
    h = V1::Hash.new s
    fail "V1::Hash.new failed" if h.nil?
    h
  end

  def setup_image
    rnd = Random.image(1024, 1)
    fail "Random.image failed" if rnd.nil?
    rnd
  end

  def setup_index(children)
    rnd = Random.index(1024, 1, children)
    fail "Random.index failed" if rnd.nil?
    rnd
  end
end
