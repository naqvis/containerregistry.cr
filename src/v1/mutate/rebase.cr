module V1::Mutate
  extend self

  # rebase returns a new V1::Image where the old_base in orig is replaced by new_base
  def rebase(orig : V1::Image, old_base : V1::Image, new_base : V1::Image)
    # Verify that old_base's layers are present in orig, otherwise orig is not based on old_base at all.
    orig_layers = orig.layers
    old_base_layers = old_base.layers

    raise "image #{orig} is not based on #{old_base} (too few layers)" if old_base_layers.size > orig_layers.size

    old_base_layers.each_with_index do |l, i|
      old_layer_digest = l.digest
      orig_layer_digest = orig_layers[i].digest
      raise "image #{orig} is not based on #{old_base} (layer #{i} mismatch)" unless old_layer_digest == orig_layer_digest
    end
    orig_config = orig.config_file
    if orig_config.nil?
      raise "unable to get config file of orig image"
    else
      # Stitch together an image that contains
      # - original image's config
      # - new base image's layers + top of original image's layers
      # - new base image's history + top of original image's history
      rebased_image = config(Empty::IMAGE, orig_config.config.dup)
      # Get new base layers and config for history
      new_base_layers = new_base.layers
      new_config = new_base.config_file

      # Add new base layers
      new_base_layers.each_with_index do |l, i|
        rebased_image = append(rebased_image, [Addendum.new(
          layer: l,
          history: new_config.try(&.history.try(&.[i]))
        )])
      end
      # Add original layers above the old base
      start = old_base_layers.size
      orig_layers[start..].each_with_index do |l, i|
        rebased_image = append(rebased_image, [Addendum.new(
          layer: l,
          history: orig_config.try(&.history.try(&.[start + i]))
        )])
      end
      rebased_image
    end
  end
end
