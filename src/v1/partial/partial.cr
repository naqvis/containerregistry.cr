# Module Partial defines methods for building up a V1::Image from
# minimal subsets that are sufficient for defining a V1::Image.
module V1::Partial
  extend self

  # fills in the missing methods from a compressed layer, so that
  # it implements V1::Layer
  def compressed_to_layer(ul) # : CompressedLayer)
    CompressedLayerExtender.new(ul)
  end

  # compressed_to_image fills in the missing methods from a CompressedImageCore
  # so that it implements v1.Image
  def compressed_to_image(cic : CompressedImageCore)
    CompressedImageExtender.new(cic)
  end

  # fills in the missing methods from an uncompressedimagecore so that it implements V1::Image
  def uncompressed_to_image(uic : UncompressedImageCore)
    UncompressedImageExtender.new(uic)
  end

  # uncompressed_to_layer fills int he missing methods from an uncompressed layer
  # so that it implements V1::Layer
  def uncompressed_to_layer(ul : UncompressedLayer)
    UnCompressedLayerExtender.new(ul)
  end
end

require "./*"
