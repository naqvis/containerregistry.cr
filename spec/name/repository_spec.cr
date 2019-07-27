require "../spec_helper"

module Name
  GOOD_STRICT_VALIDATION_REPO_NAMES = [
    "gcr.io/g-convoy/hello-world",
    "gcr.io/google.com/project-id/hello-world",
    "us.gcr.io/project-id/sub-repo",
    "example.text/foo/bar",
    "mirror.gcr.io/ubuntu",
    "index.docker.io/library/ubuntu",
  ]

  GOOD_WEAK_VALIDATION_REPO_NAMES = [
    "namespace/pathcomponent/image",
    "library/ubuntu",
    "ubuntu",
  ]

  BAD_REPO_NAMES = [
    "white space",
    "b@char/image",
  ]

  it "Test Repository Strict Validation" do
    GOOD_STRICT_VALIDATION_REPO_NAMES.each_with_index do |name, _|
      repo = Name::Repository.new name, strict: true
      repo.name.should eq(name)
    end
  end

  it "Test Weak and Invalid Repository Names" do
    (GOOD_WEAK_VALIDATION_REPO_NAMES + BAD_REPO_NAMES).each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Repository.new name, strict: true
      end
    end
  end

  it "Test Repository Weak Validation" do
    (GOOD_STRICT_VALIDATION_REPO_NAMES + GOOD_WEAK_VALIDATION_REPO_NAMES).each_with_index do |name, _|
      Name::Repository.new name, strict: false
    end
  end

  it "Test Invalid Repository Names" do
    BAD_REPO_NAMES.each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Repository.new name, strict: false
      end
    end
  end

  it "Test Repository Components" do
    registry = "gcr.io"
    repository = "project-id/image"
    repo_name_str = "#{registry}/#{repository}"
    repo = Name::Repository.new repo_name_str, strict: true

    repo.reg_name.should eq(registry)
    repo.repo_str.should eq(repository)
  end

  it "Test Repository Scopes" do
    registry = "gcr.io"
    repository = "project-id/image"
    action = "pull"
    expected_scope = ["repository", repository, action].join(":")

    repo_name_str = "#{registry}/#{repository}"
    repo = Name::Repository.new repo_name_str, strict: true

    repo.scope(action).should eq(expected_scope)
  end
end
