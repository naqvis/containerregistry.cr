require "../spec_helper"

module Name
  GOOD_STRICT_VALIDATION_REGISTRY_NAMES = [
    "gcr.io",
    "gcr.io:9001",
    "index.docker.io",
    "us.gcr.io",
    "example.text",
    "localhost",
    "localhost:9090",
  ]

  GOOD_WEAK_VALIDATION_REGISTRY_NAMES = [
    "",
  ]

  BAD_REGISTRY_NAMES = [
    "white space",
    "gcr?com",
  ]

  it "Test Registry Strict Valication" do
    GOOD_STRICT_VALIDATION_REGISTRY_NAMES.each_with_index do |name, _|
      registry = Name::Registry.new name, strict: true
      registry.reg_name.should eq(name)
    end
  end

  it "Test Registry Strict Valication with invalid names" do
    (GOOD_WEAK_VALIDATION_REGISTRY_NAMES + BAD_REGISTRY_NAMES).each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Registry.new name, strict: true
      end
    end
  end

  it "Test Registry Weak Valication" do
    (GOOD_STRICT_VALIDATION_REGISTRY_NAMES + GOOD_WEAK_VALIDATION_REGISTRY_NAMES).each_with_index do |name, _|
      Name::Registry.new name, strict: false
    end
  end

  it "Test Registry Weak Valication with invalid names" do
    BAD_REGISTRY_NAMES.each_with_index do |name, _|
      expect_raises(Name::BadNameException) do
        Name::Registry.new name, strict: false
      end
    end
  end

  it "Test Registry for Default Names" do
    test_reg = ["docker.io", ""]

    test_reg.each_with_index do |n, _|
      reg = Name::Registry.new n, strict: false
      reg.reg_name.should eq(Name::DEFAULT_REGISTRY)
    end
  end

  it "Test Registry Scopes" do
    test_reg = "gcr.io"
    test_action = "whatever"
    expected_scope = "registry:catalog:*"

    reg = Name::Registry.new test_reg
    actual_scope = reg.scope(test_action)
    actual_scope.should eq(expected_scope)
  end

  it "Test RFC1918" do
    tests = [
      {
        reg:    "index.docker.io",
        result: false,
      }, {
        reg:    "10.2.3.4:5000",
        result: true,
      }, {
        reg:    "8.8.8.8",
        result: false,
      }, {
        reg:    "172.16.3.4:3000",
        result: true,
      }, {
        reg:    "192.168.3.4",
        result: true,
      }, {
        reg:    "10.256.0.0:5000",
        result: false,
      },
    ]

    tests.each_with_index do |t, i|
      reg = Name::Registry.new t[:reg], strict: false
      got = reg.rfc1918?
      if got != t[:result]
        fail "#{i + 1}: [#{t[:reg]}] got: #{got}, want: #{t[:result]}"
      end
    end
  end

  it "Test Registry Scheme" do
    tests = [{
      domain: "foo.svc.local:1234",
      scheme: "http",
    }, {
      domain: "127.0.0.1:1234",
      scheme: "http",
    }, {
      domain: "127.0.0.1",
      scheme: "http",
    }, {
      domain: "localhost:8080",
      scheme: "http",
    }, {
      domain: "gcr.io",
      scheme: "https",
    }, {
      domain: "index.docker.io",
      scheme: "https",
    }, {
      domain: "::1",
      scheme: "http",
    }, {
      domain: "10.2.3.4:5000",
      scheme: "http",
    }]

    tests.each_with_index do |t, _|
      reg = Name::Registry.new t[:domain], strict: false
      reg.scheme.should eq(t[:scheme])
    end
  end
end
