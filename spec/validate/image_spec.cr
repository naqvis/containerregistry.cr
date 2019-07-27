require "../spec_helper"

module V1::Validator
  it "Test - Validate Image" do
    img = Random.image(1024, 5)
    # Should be all good here.
    validate(img)
  end
end
