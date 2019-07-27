require "../spec_helper"

module V1::Mutate
  def layer_digests(img)
    result = Array(String).new
    layers = img.layers
    if layers.nil?
      fail "old_base.layers are nil"
    else
      layers.each do |l|
        d = l.digest.to_s
        V1::Logger.info d
        result << d
      end
    end
    result
  end

  it "Test Rebase to test that layer digests are expected when performing a rebase on Random::Image layers" do
    # create a random old base image of 5 layers and gt those layers' digests.
    old_base = Random.image(100, 5)
    V1::Logger.info "Old base:"
    _ = layer_digests old_base

    # construct an image with 1 layer on top of old_base
    top = Random.image(100, 1)
    top_layers = top.layers
    top_history = V1::History.new(
      author: "Ali",
      created: Time.utc,
      created_by: "Test",
      comment: "this is a test"
    )
    orig = append old_base, [Addendum.new(
      layer: top_layers[0],
      history: top_history
    )]

    V1::Logger.info "Original: "
    orig_layer_digests = layer_digests orig

    # create a random new base image of 3 layers
    new_base = Random.image(100, 3)
    V1::Logger.info "New base:"
    new_base_layer_digests = layer_digests new_base

    # Rebase original image onto new base.
    rebased = rebase orig, old_base, new_base
    rebased_layer_digests = Array(String).new

    rebased_layers = rebased.layers
    rebased_layers.each do |l|
      dig = l.digest.to_s
      V1::Logger.info dig
      rebased_layer_digests << dig
    end

    # compare rebased layers
    want_layer_digests = new_base_layer_digests << orig_layer_digests[-1]

    if want_layer_digests.size != rebased_layer_digests.size
      fail "Rebased image contained #{rebased_layer_digests.size} layers, want #{want_layer_digests}"
    end

    rebased_layer_digests.each_with_index do |d, i|
      want = want_layer_digests[i]
      fail "Layer #{i} mismatch, got #{d}, want #{want}" if d != want
    end
  end
end
