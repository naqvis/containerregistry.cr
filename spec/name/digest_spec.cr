require "../spec_helper"

module Name
  VALID_DIGEST = "sha256:deadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33fdeadb33f"

  GOOD_STRICT_VALIDATION_DIGEST_NAMES = [
    "gcr.io/g-convoy/hello-world@" + VALID_DIGEST,
    "gcr.io/google.com/project-id/hello-world@" + VALID_DIGEST,
    "us.gcr.io/project-id/sub-repo@" + VALID_DIGEST,
    "example.text/foo/bar@" + VALID_DIGEST,
  ]

  GOOD_STRICT_VALIDATION_TAG_DIGEST_NAMES = [
    "example.text/foo/bar:latest@" + VALID_DIGEST,
    "example.text:8443/foo/bar:latest@" + VALID_DIGEST,
    "example.text/foo/bar:v1.0.0-alpine@" + VALID_DIGEST,
  ]

  GOOD_WEAK_VALIDATION_DIGEST_NAMES = [
    "namespace/pathcomponent/image@" + VALID_DIGEST,
    "library/ubuntu@" + VALID_DIGEST,
  ]

  GOOD_WEAK_VALIDATION_TAG_DIGEST_NAMES = [
    "nginx:latest@" + VALID_DIGEST,
    "library/nginx:latest@" + VALID_DIGEST,
  ]

  BAD_DIGEST_NAMES = [
    "gcr.io/project-id/unknown-alg@unknown:abc123",
    "gcr.io/project-id/wrong-length@sha256:d34db33fd34db33f",
    "gcr.io/project-id/missing-digest@",
  ]

  it "Test Digest Strict Validation with Good Names" do
    GOOD_STRICT_VALIDATION_DIGEST_NAMES.each_with_index do |name, _|
      digest = Name::Digest.new name, strict: true
      digest.name.should eq(name)
    end
  end

  it "Test Digest Strict Validation with Good Tag Names" do
    GOOD_STRICT_VALIDATION_TAG_DIGEST_NAMES.each_with_index do |name, _|
      Name::Digest.new name, strict: true
    end
  end

  it "Test Digest Strict Validation with Weak and Bad Names" do
    (GOOD_WEAK_VALIDATION_DIGEST_NAMES + BAD_DIGEST_NAMES).each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Digest.new name, strict: true
      end
    end
  end

  it "Test Digest creation with Good and Weak names" do
    (GOOD_STRICT_VALIDATION_DIGEST_NAMES +
      GOOD_WEAK_VALIDATION_DIGEST_NAMES +
      GOOD_WEAK_VALIDATION_TAG_DIGEST_NAMES).each_with_index do |name, _|
      Name::Digest.new name, strict: false
    end
  end

  it "Test Digest creation with Bad Name" do
    BAD_DIGEST_NAMES.each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Digest.new name, strict: true
      end
    end
  end

  it "Test Digest Components" do
    registry = "gcr.io"
    repository = "project-id/image"

    digest_name_str = "#{registry}/#{repository}@#{VALID_DIGEST}"
    digest = Name::Digest.new digest_name_str, strict: true

    digest.reg_name.should eq(registry)
    digest.repo_str.should eq(repository)
    digest.digest.should eq(VALID_DIGEST)
  end

  it "Test Digest Scopes" do
    registry = "gcr.io"
    repository = "project-id/image"
    action = "pull"
    expected_scope = ["repository", repository, action].join(":")

    digest_name_str = "#{registry}/#{repository}@#{VALID_DIGEST}"
    digest = Name::Digest.new digest_name_str, strict: true

    digest.scope(action).should eq(expected_scope)
  end
end
