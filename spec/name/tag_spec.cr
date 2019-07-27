require "../spec_helper"

module Name
  GOOD_STRICT_VALIDATION_TAG_NAMES = [
    "gcr.io/g-convoy/hello-world:latest",
    "gcr.io/google.com/g-convoy/hello-world:latest",
    "gcr.io/project-id/with-nums:v2",
    "us.gcr.io/project-id/image:with.period.in.tag",
    "gcr.io/project-id/image:w1th-alpha_num3ric.PLUScaps",
    "domain.with.port:9001/image:latest",
  ]

  GOOD_WEAK_VALIDATION_TAG_NAMES = [
    "namespace/pathcomponent/image",
    "library/ubuntu",
    "gcr.io/project-id/implicit-latest",
    "www.example.test:12345/repo/path",
  ]

  BAD_TAG_NAMES = [
    "gcr.io/project-id/bad_chars:c@n'tuse",
    "gcr.io/project-id/wrong-length:white space",
    "gcr.io/project-id/too-many-chars:thisisthetagthatneverendsitgoesonandonmyfriendsomepeoplestartedtaggingitnotknowingwhatitwasandtheyllcontinuetaggingitforeverjustbecausethisisthetagthatneverends",
  ]

  it "Test Tag Strict Validation with Good Names" do
    GOOD_STRICT_VALIDATION_TAG_NAMES.each_with_index do |name, _|
      tag = Name::Tag.new name, strict: true
      tag.name.should eq(name)
    end
  end

  it "Test Tag Strict Validation with Weak and Bad Names" do
    (GOOD_WEAK_VALIDATION_TAG_NAMES + BAD_TAG_NAMES).each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Tag.new name, strict: true
      end
    end
  end

  it "Test Tag Weak Validation with Good and Weak Names" do
    (GOOD_STRICT_VALIDATION_TAG_NAMES + GOOD_WEAK_VALIDATION_TAG_NAMES).each_with_index do |name, _|
      Name::Tag.new name, strict: false
    end
  end

  it "Test Tag Weak Validation with Bad Names" do
    BAD_TAG_NAMES.each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Tag.new name, strict: false
      end
    end
  end

  it "Test Tag Components" do
    registry = "gcr.io"
    repository = "project-id/image"
    test_tag = "latest"
    tag_name_str = "#{registry}/#{repository}:#{test_tag}"
    tag = Name::Tag.new tag_name_str, strict: true

    tag.reg_name.should eq(registry)
    tag.repo_str.should eq(repository)
    tag.tag.should eq(test_tag)
  end

  it "Test Tag Scopes" do
    registry = "gcr.io"
    repository = "project-id/image"
    test_tag = "latest"
    action = "pull"
    expected_scope = ["repository", repository, action].join(":")

    tag_name_str = "#{registry}/#{repository}:#{test_tag}"
    tag = Name::Tag.new tag_name_str, strict: true

    tag.scope(action).should eq(expected_scope)
  end

  it "Test Tag All Defaults" do
    tag_name_str = "ubuntu"
    tag = Name::Tag.new tag_name_str, strict: false

    expected_name = "index.docker.io/library/ubuntu:latest"

    tag.name.should eq(expected_name)
  end
end
