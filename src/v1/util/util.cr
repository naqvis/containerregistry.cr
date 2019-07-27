module V1::Util
  extend self

  def temp_dir(prefix : String, dir : String = Dir.tempdir)
    tempfile = File.tempfile(prefix)
    path = tempfile.path
    tempfile.delete
    path = Path[dir, path].to_s
    FileUtils.mkdir_p(path, mode: 0o700)
    path
  end

  def read_dir(dir : String)
    list = Dir.children(dir)
    list.sort
  end

  def dump_request(req, body)
    sb = String::Builder.build do |str|
      str << req.method
      str << " #{req.uri.path}"
      str << "?#{req.uri.query}" unless req.uri.query.nil?
      str << " HTTP/1.1 \r\n"
      str << "Host: #{req.uri.host}"
      str << ":#{req.uri.port}" if (p = req.uri.port) && (p != 80 || p != 443)
      str << "\r\n"
      req.headers.each do |k, v|
        str << "#{k}: #{v}\r\n"
      end
      if body
        str << req.body
        str << "\r\n"
      end
      str << "\r\n"
    end
    sb
  end

  def dump_response(res, body)
    sb = String::Builder.build do |str|
      str << "status code #{res.status}\r\n"
      res.headers.each do |k, v|
        str << "#{k}: #{v}\r\n"
      end
      if body
        str << res.body
        str << "\r\n"
      end
      str << "\r\n"
    end
    sb
  end
end

require "file_utils"
require "./*"
