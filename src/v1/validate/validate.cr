# Module V1::Validate provides methods for validating image correctness.
module V1::Validator
  extend self

  def validate(img : V1::Image)
    image(img)
  end

  def validate(idx : V1::ImageIndex)
    index(idx)
  end
end

require "./*"
