require "../spec_helper"
require "./remote_helper"

module V1::Remote
  it "Test Raw Manifest Digests" do
    img = random_image
    expected_repo = "foo/bar"
    cases = [
      {
        name:           "normal pull, by tag",
        ref:            "latest",
        response_body:  must_raw_manifest(img),
        content_digest: must_digest(img).to_s,
        want_err:       false,
      }, {
        name:           "normal pull, by digest",
        ref:            must_digest(img).to_s,
        response_body:  must_raw_manifest(img),
        content_digest: must_digest(img).to_s,
        want_err:       false,
      }, {
        name:           "right content-digest, wrong body, by digest",
        ref:            must_digest(img).to_s,
        response_body:  "not even json".to_slice,
        content_digest: must_digest(img).to_s,
        want_err:       true,
      }, {
        name:           "right body, wrong content-digest, by tag",
        ref:            "latest",
        response_body:  must_raw_manifest(img),
        content_digest: BOGUS_DIGEST,
        want_err:       false,
      }, {
        # NB: This succeeds! We don't care what the registry thinks.
        name:           "right body, wrong content-digest, by digest",
        ref:            must_digest(img).to_s,
        response_body:  must_raw_manifest(img),
        content_digest: BOGUS_DIGEST,
        want_err:       false,
      },
    ]
    cases.each do |tc|
      manifest_path = sprintf "/v2/%s/manifests/%s", expected_repo, tc[:ref]
      server = HTTP::Server.new do |ctx|
        r = ctx.request
        rs = ctx.response
        case r.path
        when manifest_path
          fail "Method; got #{r.method}, want GET" unless r.method == "GET"
          rs.headers["Docker-Content-Digest"] = tc[:content_digest]
          rs.write tc[:response_body]
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
        ref = new_reference address.to_s, expected_repo, tc[:ref]
        begin
          rmt = Remote.remote_image(
            fetcher: Fetcher.new(ref: ref, client: Cossack::Client.new)
          )
          rmt.raw_manifest
        rescue ex
          raise ex if !tc[:want_err]
        end
      ensure
        server.close
      end
    end
  end

  it "Test Raw Manifest Not Found" do
    expected_repo = "foo/bar"
    manifest_path = sprintf "/v2/%s/manifests/latest", expected_repo
    server = HTTP::Server.new do |ctx|
      r = ctx.request
      rs = ctx.response
      case r.path
      when manifest_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.status_code = 404
        rs.print "Not found"
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
      ref = Name::Tag.new sprintf("%s/%s:latest", address.to_s, expected_repo), strict: false

      rmt = Remote.remote_image(
        fetcher: Fetcher.new(ref: ref, client: Cossack::Client.new)
      )
      expect_raises(V1::Remote::Transport::RegistryError) do
        rmt.raw_manifest
      end
    ensure
      server.close
    end
  end

  it "Test Raw Config File Not Found" do
    img = random_image
    expected_repo = "foo/bar"
    manifest_path = sprintf "/v2/%s/manifests/latest", expected_repo
    config_path = sprintf "/v2/%s/blobs/%s", expected_repo, must_config_name(img).to_s
    server = HTTP::Server.new do |ctx|
      r = ctx.request
      rs = ctx.response
      case r.path
      when config_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.status_code = 404
        rs.print "Not found"
      when manifest_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.write must_raw_manifest img
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
      ref = Name::Tag.new sprintf("%s/%s:latest", address.to_s, expected_repo), strict: false

      rmt = Remote.remote_image(
        fetcher: Fetcher.new(ref: ref, client: Cossack::Client.new)
      )
      expect_raises(V1::Remote::Transport::RegistryError) do
        rmt.raw_config_file
      end
    ensure
      server.close
    end
  end

  it "Test Accept Headers" do
    img = random_image
    expected_repo = "foo/bar"
    manifest_path = sprintf "/v2/%s/manifests/latest", expected_repo
    server = HTTP::Server.new do |ctx|
      r = ctx.request
      rs = ctx.response
      case r.path
      when manifest_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        want_accept = [Types::DOCKERMANIFESTSCHEMA2.to_s, Types::OCIMANIFESTSCHEMA1.to_s].join(",")
        got = r.headers["Accept"]
        fail "Accept header; got #{got}, want #{want_accept}" unless got == want_accept
        rs.write must_raw_manifest img
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
      ref = Name::Tag.new sprintf("%s/%s:latest", address.to_s, expected_repo), strict: false

      rmt = Remote.remote_image(
        fetcher: Fetcher.new(ref: ref, client: Cossack::Client.new)
      )

      got = rmt.raw_manifest
      want = must_raw_manifest img
      got.should eq(want)
    ensure
      server.close
    end
  end

  it "Test Image" do
    img = random_image
    expected_repo = "foo/bar"
    layer_digest = must_manifest(img).layers[0].digest
    layer_size = must_manifest(img).layers[0].size
    config_path = sprintf "/v2/%s/blobs/%s", expected_repo, must_config_name(img).to_s
    manifest_path = sprintf "/v2/%s/manifests/latest", expected_repo
    layer_path = sprintf "/v2/%s/blobs/%s", expected_repo, layer_digest.to_s
    manifest_req_count = 0
    server = HTTP::Server.new do |ctx|
      r = ctx.request
      rs = ctx.response
      case r.path
      when "/v2/"
        rs.print "okay"
      when config_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.write must_raw_config_file img
      when manifest_path
        manifest_req_count += 1
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.write must_raw_manifest img
      when layer_path
        fail "Blobsize should not make any request: #{r.path}"
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
      tag = Name::Tag.new sprintf("%s/%s:latest", address.to_s, expected_repo), strict: false
      rmt = Remote.image tag, with_transport(Cossack::Client.new)
      got, want = must_raw_manifest(rmt), must_raw_manifest(img)
      fail "raw_manifest() = #{got}, want = #{want}" unless got == want

      got, want = must_raw_config_file(rmt), must_raw_config_file(img)
      fail "must_raw_config_file() = #{got}, want = #{want}" unless got == want

      # Make sure caching the manifest works.
      fail "raw_manifest made #{manifest_req_count} requests, expected 1" unless manifest_req_count == 1

      l = rmt.layer_by_digest(layer_digest)
      # Blobsize should not HEAD
      got, want = l.size, layer_size
      fail "BlobSize() = #{got} want #{want}" unless got == want
    ensure
      server.close
    end
  end

  it "Test Pulling Manifest List" do
    idx = random_index
    expected_repo = "foo/bar"
    manifest_path = sprintf "/v2/%s/manifests/latest", expected_repo
    child_digest = must_index_manifest(idx).manifests[0].digest
    child = must_child(idx, child_digest)
    child_path = sprintf "/v2/%s/manifests/%s", expected_repo, child_digest.to_s
    config_path = sprintf "/v2/%s/blobs/%s", expected_repo, must_config_name(child).to_s

    # Rewrite the index to make sure the desired platform matches the second child.
    manifest = idx.index_manifest

    # Make sure the first manifest doesn't match.
    manifest.manifests[0].platform = V1::Platform.new(
      architecture: "not-real-arch",
      os: "not-real-os"
    )

    # Make sure the second manifest does.
    manifest.manifests[1].platform = Remote::DEFAULT_PLATFORM
    raw_manifest = manifest.to_json.to_slice

    server = HTTP::Server.new do |ctx|
      r = ctx.request
      rs = ctx.response
      case r.path
      when "/v2/"
        rs.print "okay"
      when manifest_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.headers["Content-Type"] = must_media_type(idx).to_s
        rs.write raw_manifest
      when child_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.write must_raw_manifest child
      when config_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.write must_raw_config_file child
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
      tag = Name::Tag.new sprintf("%s/%s:latest", address.to_s, expected_repo), strict: false
      rmt_child = Remote.image tag, with_transport(Cossack::Client.new)

      # Test that child works as expected.
      got, want = must_raw_manifest(rmt_child), must_raw_manifest(child)
      fail "raw_manifest() = #{String.new(got)}, want = #{String.new(want)}" unless got == want

      got, want = must_raw_config_file(rmt_child), must_raw_config_file(child)
      fail "must_raw_config_file() = #{String.new(got)}, want = #{String.new(want)}" unless got == want
    ensure
      server.close
    end
  end

  it "Test Pulling Manifest List No Match" do
    idx = random_index
    expected_repo = "foo/bar"
    manifest_path = sprintf "/v2/%s/manifests/latest", expected_repo
    child_digest = must_index_manifest(idx).manifests[1].digest
    child = must_child(idx, child_digest)
    child_path = sprintf "/v2/%s/manifests/%s", expected_repo, child_digest.to_s
    config_path = sprintf "/v2/%s/blobs/%s", expected_repo, must_config_name(child).to_s

    server = HTTP::Server.new do |ctx|
      r = ctx.request
      rs = ctx.response
      case r.path
      when "/v2/"
        rs.print "okay"
      when manifest_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.headers["Content-Type"] = must_media_type(idx).to_s
        rs.write must_raw_manifest idx
      when child_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.write must_raw_manifest child
      when config_path
        fail "Method; got #{r.method}, want GET" unless r.method == "GET"
        rs.write must_raw_config_file child
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
      platform = V1::Platform.new(
        architecture: "not-real-arch",
        os: "not-real-os"
      )

      tag = Name::Tag.new sprintf("%s/%s:latest", address.to_s, expected_repo), strict: false
      expect_raises(Exception) do
        Remote.image tag, with_platform(platform)
      end
    ensure
      server.close
    end
  end
end
