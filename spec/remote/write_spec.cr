require "../spec_helper"
require "./remote_helper"
require "http/server"
require "http/server/handler"
require "cossack"

module V1::Remote
  it "Test URL" do
    tests = [
      {
        tag:  "gcr.io/foo/bar:latest",
        path: "/v2/foo/bar/manifests/latest",
        url:  "https://gcr.io/v2/foo/bar/manifests/latest",
      }, {
        tag:  "localhost:8080/foo/bar:baz",
        path: "/v2/foo/bar/blobs/upload",
        url:  "http://localhost:8080/v2/foo/bar/blobs/upload",
      },
    ]

    tests.each_with_index do |test, _|
      w = Writer.new(
        ref: Name::Tag.new(test[:tag], strict: false)
      )
      got = w.url test[:path]
      got.to_s.should eq(test[:url])
    end
  end

  it "Test Next Location" do
    tests = [
      {
        location: "https://gcr.io/v2/foo/bar/blobs/uploads/1234567?baz=blah",
        url:      "https://gcr.io/v2/foo/bar/blobs/uploads/1234567?baz=blah",
      }, {
        location: "/v2/foo/bar/blobs/uploads/1234567?baz=blah",
        url:      "https://gcr.io/v2/foo/bar/blobs/uploads/1234567?baz=blah",
      },
    ]
    w = Writer.new(
      ref: Name::Tag.new("gcr.io/foo/bar:latest", strict: false)
    )
    tests.each_with_index do |test, _|
      resp = Cossack::Response.new(200, ::Hash{"Location" => test[:location]}, "")
      got = w.next_location(resp)
      got.to_s.should eq(test[:url])
    end
  end

  def setup_writer(repo : String, handler : HTTP::Handler::HandlerProc)
    server = HTTP::Server.new(handler)
    address = server.bind_tcp 8085
    setup_writer_with_server(repo, server, address)
  end

  def setup_writer_with_server(repo, server, address)
    tag = Name::Tag.new sprintf("%s/%s:latest", address.to_s, repo), strict: false
    {Writer.new(ref: tag), server}
  end

  it "Test Check Existing Blob" do
    tests = [
      {name:     "success",
       status:   200,
       existing: true,
       want_err: false},
      {name:     "not found",
       status:   404,
       existing: false,
       want_err: false},
      {name:     "error",
       status:   500,
       existing: false,
       want_err: true},
    ]

    img = setup_image
    h = must_config_name img
    expected_repo = "foo/bar"
    expected_path = sprintf "/v2/%s/blobs/%s", expected_repo, h.to_s

    tests.each_with_index do |test, _|
      w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
        fail "Method; got #{ctx.request.method}, want 'HEAD'" unless ctx.request.method == "HEAD"
        fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
        ctx.response.status_code = test[:status]
        ctx.response.print test[:name]
      end
      )
      spawn do
        s.listen
      end
      begin
        Fiber.yield
        if test[:want_err]
          expect_raises(Exception) do
            w.check_existing_blob(h)
          end
        else
          existing = w.check_existing_blob(h)
          existing.should eq(test[:existing])
        end
      ensure
        s.close
      end
    end
  end

  it "Test Initial Upload No Mounts Exists" do
    img = setup_image
    h = must_config_name img
    expected_repo = "foo/bar"
    expected_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    expected_query = HTTP::Params.encode(::Hash{
      "mount" => h.to_s,
      "from"  => "baz/bar",
    })
    w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'POST'" unless ctx.request.method == "POST"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      fail "Query; got #{ctx.request.query}, want #{expected_query}" unless ctx.request.query == expected_query
      ctx.response.status_code = 201
      ctx.response.print "Mounted"
    end
    )
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      _, mounted = w.initiate_upload("baz/bar", h.to_s)
      fail "initiate_upload = !mounted, want mounted" unless mounted
    ensure
      s.close
    end
  end

  it "Test Initial Upload No Mounts Initiated" do
    img = setup_image
    h = must_config_name img
    expected_repo = "baz/blah"
    expected_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    expected_query = HTTP::Params.encode(::Hash{
      "mount" => h.to_s,
      "from"  => "baz/bar",
    })
    expected_location = "https://somewhere.io/upload?foo=bar"

    w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'POST'" unless ctx.request.method == "POST"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      fail "Query; got #{ctx.request.query}, want #{expected_query}" unless ctx.request.query == expected_query
      ctx.response.status_code = 202
      ctx.response.headers["Location"] = expected_location
      ctx.response.print "Initiated"
    end
    )
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      location, mounted = w.initiate_upload("baz/bar", h.to_s)
      fail "initiate_upload = mounted, want !mounted" if mounted
      location.should eq(expected_location)
    ensure
      s.close
    end
  end

  it "Test Initial Upload No Mounts Bad Status" do
    img = setup_image
    h = must_config_name img
    expected_repo = "ugh/another"
    expected_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    expected_query = HTTP::Params.encode(::Hash{
      "mount" => h.to_s,
      "from"  => "baz/bar",
    })

    w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'POST'" unless ctx.request.method == "POST"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      fail "Query; got #{ctx.request.query}, want #{expected_query}" unless ctx.request.query == expected_query
      ctx.response.status_code = 204 # No content
    end
    )
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      expect_raises(V1::Remote::Transport::RegistryError) do
        _, _ = w.initiate_upload("baz/bar", h.to_s)
      end
    ensure
      s.close
    end
  end

  it "Test Initiate Upload Mounts With Mount From Different Registry" do
    img = setup_image
    h = must_config_name img
    expected_mount_repo = "a/different/repo"
    expected_repo = "yet/again"
    expected_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    expected_query = HTTP::Params.encode(::Hash{
      "mount" => h.to_s,
      "from"  => "baz/bar",
    })
    _ = MountableImage.new(
      image: img,
      reference: Name::Tag.new "gcr.io/#{expected_mount_repo}", strict: false
    )
    w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'POST'" unless ctx.request.method == "POST"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      fail "Query; got #{ctx.request.query}, want #{expected_query}" unless ctx.request.query == expected_query
      ctx.response.status_code = 201
      ctx.response.print "Mounted"
    end
    )
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      _, mounted = w.initiate_upload("baz/bar", h.to_s)
      fail "initiate_upload = !mounted, want mounted" unless mounted
    ensure
      s.close
    end
  end

  it "Test Initial Upload Mounts With Mount From Same Registry" do
    img = setup_image
    h = must_config_name img
    expected_mount_repo = "a/different/repo"
    expected_repo = "yet/again"
    expected_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    expected_query = HTTP::Params.encode(::Hash{
      "mount" => h.to_s,
      "from"  => expected_mount_repo,
    })

    server = HTTP::Server.new(HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'POST'" unless ctx.request.method == "POST"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      fail "Query; got #{ctx.request.query}, want #{expected_query}" unless ctx.request.query == expected_query
      ctx.response.status_code = 201
      ctx.response.print "Mounted"
    end
    )
    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      Fiber.yield

      _ = MountableImage.new(
        image: img,
        reference: Name::Tag.new "#{address.to_s}/#{expected_mount_repo}", strict: false
      )

      w, _ = setup_writer_with_server(expected_repo, server, address)

      _, mounted = w.initiate_upload(expected_mount_repo, h.to_s)

      fail "initiate_upload = !mounted, want mounted" unless mounted
    ensure
      server.close
    end
  end

  it "Test Dedupe Layers" do
    new_blob = Proc(IO).new { V1::Util::NoOpCloser.new(IO::Memory.new("a" * 10000)) }
    img = Random.image(1024, 3)

    # Append three identical Tarball::Layers, which should be deduped
    # because contents can be hashed before uploading.
    3.times do |_|
      tl = Tarball::Layer.from_opener new_blob
      img = Mutate.append_layers img, [tl]
    end

    # Append three identical Stream::Layer, whose uploads will *not* be
    # deduped since write can't tell they're identical ahead of time.
    3.times do |_|
      sl = Stream::Layer.new new_blob.call
      img = Mutate.append_layers img, [sl]
    end

    expected_repo = "write/time"
    head_path_prefix = "/v2/#{expected_repo}/blobs/"
    initiate_path = "/v2/#{expected_repo}/blobs/uploads/"
    manifest_path = "/v2/#{expected_repo}/manifests/latest"
    upload_path = "/upload"
    commit_path = "/commit"
    num_uploads = 0

    server = HTTP::Server.new do |ctx|
      method = ctx.request.method
      path = ctx.request.path
      if method == "HEAD" && path.starts_with?(head_path_prefix) && path != initiate_path
        ctx.response.status_code = 404
        ctx.response.print "Not Found"
        next
      end

      case path
      when "/v2/"
        ctx.response.print "okay"
      when initiate_path
        fail "Method; got #{method}, want POST" unless method == "POST"
        ctx.response.headers["Location"] = upload_path
        ctx.response.status_code = 202 # Accepted
        ctx.response.print "Accepted"
      when upload_path
        fail "Method; got #{method}, want PATCH" unless method == "PATCH"
        num_uploads += 1
        ctx.response.headers["Location"] = commit_path
        ctx.response.status_code = 201 # Created
        ctx.response.print "Created"
      when commit_path
        ctx.response.status_code = 201 # Created
        ctx.response.print "Created"
      when manifest_path
        fail "Method; got #{method}, want PUT" unless method == "PUT"
        ctx.response.status_code = 201 # Created
        ctx.response.print "Created"
      else
        fail "Unexpected path: #{path}"
      end
    end

    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      Fiber.yield
      tag = Name::Tag.new "#{address.to_s}/#{expected_repo}", strict: false
      write tag, img, with_auth(Authn::ANONYMOUS)

      # 3 random layers, 1 tarball layer (deduped), 3 stream layers (not deduped), 1 image config blob
      want_uploads = 3 + 1 + 3 + 1
      fail "Write uploaded #{num_uploads} blobs, want #{want_uploads}" unless want_uploads == num_uploads
    ensure
      server.close
    end
  end

  it "Test Stream Blob" do
    img = setup_image
    expected_path = "/vWhatever/I/decide"
    expected_commit_location = "https://commit.io/v12/blob"
    w, s = setup_writer("what/ever", HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'PATCH'" unless ctx.request.method == "PATCH"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      if (body = ctx.request.body)
        got = V1::Util.read_all(body)
        want = img.raw_config_file
        got.should eq(want)
        ctx.response.headers["Location"] = expected_commit_location
        ctx.response.status_code = 201
        ctx.response.print "Created"
      else
        fail "No body received"
      end
    end)
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      stream_location = w.url expected_path
      l = Partial.config_layer(img)
      blob = l.compressed
      commit_location = w.stream_blob blob, stream_location.to_s
      commit_location.to_s.should eq(expected_commit_location)
    ensure
      s.close
    end
  end

  it "Test Stream Layer" do
    n, want_size = 10000, 46
    new_blob = Proc(IO).new { V1::Util::NoOpCloser.new(IO::Memory.new("a" * n)) }
    # want_digest = "sha256:3d7c465be28d9e1ed810c42aeb0e747b44441424f566722ba635dc93c947f30e"
    expected_path = "/vWhatever/I/decide"
    expected_commit_location = "https://commit.io/v12/blob"

    w, s = setup_writer("what/ever", HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'PATCH'" unless ctx.request.method == "PATCH"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      if (body = ctx.request.body)
        _, size = V1::Hash.sha256(body)
        size.should eq want_size
        ctx.response.headers["Location"] = expected_commit_location
        ctx.response.status_code = 201
        ctx.response.print "Created"
      else
        fail "No body received"
      end
    end)
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      stream_location = w.url expected_path
      l = Stream::Layer.new new_blob.call
      blob = l.compressed
      commit_location = w.stream_blob blob, stream_location.to_s
      commit_location.to_s.should eq(expected_commit_location)
    ensure
      s.close
    end
  end

  it "Test Commit Blob" do
    img = setup_image
    h = must_config_name img
    expected_path = "/no/commitment/issues"
    expected_query = HTTP::Params{"digest" => h.to_s}.to_s
    w, s = setup_writer("what/ever", HTTP::Handler::HandlerProc.new do |ctx|
      fail "Method; got #{ctx.request.method}, want 'PUT'" unless ctx.request.method == "PUT"
      fail "URL; got #{ctx.request.path}, want #{expected_path}" unless ctx.request.path == expected_path
      fail "Query; got #{ctx.request.query}, want #{expected_query}" unless ctx.request.query == expected_query
      ctx.response.status_code = 201
    end)
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      commit_location = w.url expected_path
      w.commit_blob commit_location.to_s, h.to_s
    ensure
      s.close
    end
  end

  it "Test Upload One" do
    img = setup_image
    h = must_config_name img
    expected_repo = "baz/blah"
    head_path = sprintf "/v2/%s/blobs/%s", expected_repo, h.to_s
    initiate_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    stream_path = "/path/to/upload"
    commit_path = "/path/to/commit"

    w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      path = ctx.request.path
      method = ctx.request.method
      resp = ctx.response
      case path
      when head_path
        fail "Method; got #{method}, want HEAD" unless method == "HEAD"
        resp.status_code = 404
        resp.print "Not Found"
      when initiate_path
        fail "Method; got #{method}, want POST" unless method == "POST"
        resp.headers["Location"] = stream_path
        resp.status_code = 202
        resp.print "Initiated"
      when stream_path
        fail "Method; got #{method}, want PATCH" unless method == "PATCH"
        if (body = ctx.request.body)
          got = V1::Util.read_all body
          want = img.raw_config_file
          got.should eq(want)

          resp.headers["Location"] = commit_path
          resp.status_code = 202
          resp.print "Initiated"
        else
          fail "No body received"
        end
      when commit_path
        fail "Method; got #{method}, want PUT" unless method == "PUT"
        resp.status_code = 201
        resp.print "Created"
      else
        fail "unexpected path: #{path}"
      end
    end)
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      l = Partial.config_layer img
      w.upload_one l
    ensure
      s.close
    end
  end

  it "Test Upload One Streamed Layer" do
    expected_repo = "baz/blah"
    initiate_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    stream_path = "/path/to/upload"
    commit_path = "/path/to/commit"

    w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      path = ctx.request.path
      method = ctx.request.method
      resp = ctx.response
      case path
      when initiate_path
        fail "Method; got #{method}, want POST" unless method == "POST"
        resp.headers["Location"] = stream_path
        resp.status_code = 202
        resp.print "Initiated"
      when stream_path
        fail "Method; got #{method}, want PATCH" unless method == "PATCH"
        resp.headers["Location"] = commit_path
        resp.status_code = 202
        resp.print "Initiated"
      when commit_path
        fail "Method; got #{method}, want PUT" unless method == "PUT"
        resp.status_code = 201
        resp.print "Created"
      else
        fail "unexpected path: #{path}"
      end
    end)
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      n, want_size = 10000, 46
      new_blob = Proc(IO).new { V1::Util::NoOpCloser.new(IO::Memory.new("a" * n)) }
      want_diff_id = "sha256:27dd1f61b867b6a0f6e9d8a41c43231de52107e53ae424de8f847b821db4b711"

      l = Stream::Layer.new new_blob.call
      w.upload_one l
      _ = l.digest
      diff_id = l.diff_id
      diff_id.to_s.should eq(want_diff_id)
      l.size.should eq(want_size)
    ensure
      s.close
    end
  end

  it "Test Commit Image" do
    img = setup_image
    expected_repo = "foo/bar"
    expected_path = sprintf "/v2/%s/manifests/latest", expected_repo

    w, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      r = ctx.request

      fail "Method; got #{r.method}, want PUT" unless r.method == "PUT"
      fail "URL; got #{r.path}, want #{expected_path}" unless r.path == expected_path

      if (body = r.body)
        got = V1::Util.read_all body
        want = img.raw_manifest
        got.should eq want
        mt = img.media_type
        got = r.headers["Content-Type"]
        got.should eq mt.to_s
      else
        fail "no body found"
      end
    end
    )
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      w.commit_image img
    ensure
      s.close
    end
  end

  it "Test Write" do
    img = setup_image
    expected_repo = "write/time"
    head_path_prefix = sprintf "/v2/%s/blobs/", expected_repo
    initiate_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    manifest_path = sprintf "/v2/%s/manifests/latest", expected_repo

    _, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      path = ctx.request.path
      method = ctx.request.method
      resp = ctx.response
      if method == "HEAD" && path.starts_with?(head_path_prefix) && path != initiate_path
        resp.status_code = 404
        resp.print "Not Found"
        return
      end
      case path
      when "/v2/"
        resp.print "Okay"
      when initiate_path
        fail "Method; got #{method}, want POST" unless method == "POST"
        resp.status_code = 201
        resp.print "Mounted"
      when manifest_path
        fail "Method; got #{method}, want PUT" unless method == "PUT"
        resp.status_code = 201
        resp.print "Created"
      else
        fail "unexpected path: #{path}"
      end
    end)
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      tag = Name::Tag.new sprintf("%s/%s:latest", s.addresses[0].to_s, expected_repo), strict: false
      write tag, img, with_auth(Authn::ANONYMOUS)
    ensure
      s.close
    end
  end

  it "Test Write With Errors" do
    img = setup_image
    expected_repo = "write/time"
    head_path_prefix = sprintf "/v2/%s/blobs/", expected_repo
    initiate_path = sprintf "/v2/%s/blobs/uploads/", expected_repo
    expected_error = "NAME_INVALID: some explanation of how things were messed up."

    _, s = setup_writer(expected_repo, HTTP::Handler::HandlerProc.new do |ctx|
      path = ctx.request.path
      method = ctx.request.method
      resp = ctx.response
      if method == "HEAD" && path.starts_with?(head_path_prefix) && path != initiate_path
        resp.status_code = 404
        resp.print "Not Found"
        return
      end
      case path
      when "/v2/"
        resp.print "Okay"
      when initiate_path
        fail "Method; got #{method}, want POST" unless method == "POST"
        resp.status_code = 400
        resp.write expected_error.to_json.to_slice
      else
        fail "unexpected path: #{path}"
      end
    end)
    spawn do
      s.listen
    end
    begin
      Fiber.yield
      tag = Name::Tag.new sprintf("%s/%s:latest", s.addresses[0].to_s, expected_repo), strict: false
      begin
        write tag, img, with_auth(Authn::ANONYMOUS)
      rescue ex
        if (m = ex.message)
          m.should contain(expected_error.to_json)
        else
          fail "exception with no message"
        end
      else
        fail "expecting error, but got nothing"
      end
    ensure
      s.close
    end
  end

  it "Test Scopes for Upload" do
    ref_to_upload = Name::Tag.new "example.com/sample/sample:latest", strict: false
    repo1 = Name::Tag.new "example.com/sample/another_repo1:latest", strict: false
    repo2 = Name::Tag.new "example.com/sample/another_repo2:latest", strict: false

    img = setup_image
    layers = img.layers
    dummy_layer = layers[0]

    test_cases = [
      {name:      "empty layers",
       reference: ref_to_upload,
       layers:    [] of V1::Layer,
       expected:  [ref_to_upload.scope(Transport::PUSH_SCOPE)],
      },
      {name:      "mountable layers with single reference with no-duplicate",
       reference: ref_to_upload,
       layers:    [MountableLayer.new(layer: dummy_layer, reference: repo1)],
       expected:  [ref_to_upload.scope(Transport::PUSH_SCOPE), repo1.scope(Transport::PULL_SCOPE)],
      },
      {name:      "mountable layers with single reference with duplicate",
       reference: ref_to_upload,
       layers:    [MountableLayer.new(layer: dummy_layer, reference: repo1),
                MountableLayer.new(layer: dummy_layer, reference: repo1)],
       expected: [ref_to_upload.scope(Transport::PUSH_SCOPE), repo1.scope(Transport::PULL_SCOPE)],
      },
      {name:      "mountable layers with multiple reference with no-duplicate",
       reference: ref_to_upload,
       layers:    [MountableLayer.new(layer: dummy_layer, reference: repo1),
                MountableLayer.new(layer: dummy_layer, reference: repo2)],
       expected: [ref_to_upload.scope(Transport::PUSH_SCOPE),
                  repo1.scope(Transport::PULL_SCOPE),
                  repo2.scope(Transport::PULL_SCOPE)],
      },
      {name:      "mountable layers with multiple reference with duplicate",
       reference: ref_to_upload,
       layers:    [MountableLayer.new(layer: dummy_layer, reference: repo1),
                MountableLayer.new(layer: dummy_layer, reference: repo2),
                MountableLayer.new(layer: dummy_layer, reference: repo1),
                MountableLayer.new(layer: dummy_layer, reference: repo2)],
       expected: [ref_to_upload.scope(Transport::PUSH_SCOPE),
                  repo1.scope(Transport::PULL_SCOPE),
                  repo2.scope(Transport::PULL_SCOPE)],
      },
    ]
    test_cases.each do |tc|
      p "Running test for - #{tc[:name]}"
      actual = scopes_for_uploading_image tc[:reference], tc[:layers]
      actual.should eq(tc[:expected])
      want = tc[:expected][0]
      got = actual[0]
      got.should eq(want)
    end
  end

  it "Test Write Index" do
    idx = setup_index 2
    expected_repo = "write/time"
    head_path_prefix = "/v2/#{expected_repo}/blobs/"
    initiate_path = "/v2/#{expected_repo}/blobs/uploads/"
    manifest_path = "/v2/#{expected_repo}/manifests/latest"
    child_digest = must_index_manifest(idx).manifests[0].digest.to_s
    child_path = "/v2/#{expected_repo}/manifests/#{child_digest}"
    existing_child_digest = must_index_manifest(idx).manifests[1].digest.to_s
    existing_child_path = "/v2/#{expected_repo}/manifests/#{existing_child_digest}"

    server = HTTP::Server.new do |ctx|
      r = ctx.request
      rs = ctx.response
      if r.method == "HEAD" && r.path.starts_with?(head_path_prefix) && r.path != initiate_path
        rs.status_code = 404
        rs.print "Not Found"
        next
      end
      case r.path
      when "/v2/"
        rs.print "okay"
      when initiate_path
        fail "Method; got #{r.method}, want POST" unless r.method == "POST"
        rs.status_code = 201
        rs.print "Mounted"
      when manifest_path
        fail "Method; got #{r.method}, want PUT" unless r.method == "PUT"
        rs.status_code = 201
        rs.print "Created"
      when existing_child_path
        fail "unxpected method; got #{r.method}, want HEAD" unless r.method == "HEAD"
        rs.print "okay"
      when child_path
        if r.method == "HEAD"
          rs.status_code = 404
          rs.print "Not Found"
        elsif r.method != "PUT"
          fail "Method; got #{r.method}, expected PUT"
        else
          rs.status_code = 201
          rs.print "Created"
        end
      else
        fail "unexpected path: #{r.path}"
      end
    end

    address = server.bind_tcp 8085
    spawn do
      server.listen
    end
    begin
      Fiber.yield
      tag = Name::Tag.new "#{address.to_s}/#{expected_repo}:latest", strict: false
      write_index tag, idx, with_auth(Authn::ANONYMOUS)
    ensure
      server.close
    end
  end
end
