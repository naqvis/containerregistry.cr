module V1::Remote::Transport
  class RegistryError < Exception
  end

  private class Error
    JSON.mapping(
      errors: {type: Array(Diagnostic), default: [] of Diagnostic}
    )

    def to_s
      case errors.size
      when 0
        "<empty response>"
      when 1
        errors[0].to_s
      else
        msgs = Array(String).new
        errors.each { |e| msgs << e.to_s }
        msg = msgs.join(";")
        "multiple errors returned: #{msg}"
      end
    end
  end

  private struct Diagnostic
    JSON.mapping(
      code: String,
      message: {type: String, default: ""},
      detail: {type: JSON::Any, nilable: true}
    )

    def to_s
      msg = String.build do |str|
        str << code
        str << ": "
        str << message
        str << "; #{detail.to_s}" unless detail.nil?
      end
      msg
    end
  end

  # check_error returns a structured error if the response status is not in codes.
  def self.check_error(resp, *codes) : RegistryError?
    codes.each do |code|
      return nil if resp.status == code
    end

    # https://github.com/docker/distribution/blob/master/docs/spec/api.md#errors
    begin
      err = Error.from_json(resp.body)
      RegistryError.new err.to_s
    rescue exception
      RegistryError.new "unsupported status code: #{resp.status}; body: #{resp.body}"
    end
  end
end
