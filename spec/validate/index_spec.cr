require "../spec_helper"

module V1::Validator
  it "Test - Validate Index Image" do
    idx = Random.index(1024, 1, 3)
    # Should be all good here.
    validate(idx)
  end
end
