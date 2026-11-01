# frozen_string_literal: true

require "socket"

# Stdlib-only HTTP/1.1 server for integration tests. No WEBrick or Rack, and no
# test makes a real external network call.
class LocalHttpServer
  Request = Data.define(:method, :path, :headers, :body)
  ScriptedResponse = Data.define(:status, :headers, :body)

  REASONS = {
    200 => "OK",
    201 => "Created",
    204 => "No Content",
    302 => "Found",
    400 => "Bad Request",
    401 => "Unauthorized",
    403 => "Forbidden",
    404 => "Not Found",
    422 => "Unprocessable Content",
    429 => "Too Many Requests",
    500 => "Internal Server Error",
    503 => "Service Unavailable"
  }.freeze

  DEFAULT_RESPONSE = ScriptedResponse.new(
    status: 200,
    headers: { "Content-Type" => "application/json" },
    body: "{}"
  )

  attr_reader :requests, :port

  def initialize(responses: [])
    @responses = responses.map { |response| normalize(response) }
    @requests = []
    @mutex = Mutex.new
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { serve }
    @thread.abort_on_exception = false
  end

  def url(prefix: nil)
    base = "http://127.0.0.1:#{port}"
    prefix.nil? ? base : "#{base}#{prefix}"
  end

  def received
    @mutex.synchronize { @requests.dup }
  end

  def stop
    @server.close unless @server.closed?
  rescue IOError
    nil
  ensure
    @thread&.join(2)
  end

  private

  def normalize(response)
    return response if response.is_a?(ScriptedResponse)

    ScriptedResponse.new(
      status: response.fetch(:status, 200),
      headers: response.fetch(:headers, { "Content-Type" => "application/json" }),
      body: response.fetch(:body, "{}")
    )
  end

  def serve
    loop do
      socket = @server.accept
      handle(socket)
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def handle(socket)
    request_line = socket.gets
    return if request_line.nil?

    method, target, = request_line.split(" ")
    headers = read_headers(socket)
    body = read_body(socket, headers)

    @mutex.synchronize do
      @requests << Request.new(method: method, path: target, headers: headers, body: body)
    end

    write_response(socket, next_response)
  ensure
    socket.close unless socket.closed?
  end

  def read_headers(socket)
    headers = {}
    while (line = socket.gets)
      break if line == "\r\n" || line == "\n"

      key, value = line.split(":", 2)
      headers[key.to_s.downcase] = value.to_s.strip if value
    end
    headers
  end

  def read_body(socket, headers)
    length = headers["content-length"].to_i
    return nil unless length.positive?

    socket.read(length)
  end

  def next_response
    @mutex.synchronize { @responses.shift } || DEFAULT_RESPONSE
  end

  def write_response(socket, response)
    body = response.body.to_s
    reason = REASONS.fetch(response.status, "OK")

    socket.write("HTTP/1.1 #{response.status} #{reason}\r\n")
    response.headers.merge(
      "Content-Length" => body.bytesize.to_s,
      "Connection" => "close"
    ).each do |key, value|
      socket.write("#{key}: #{value}\r\n")
    end
    socket.write("\r\n")
    socket.write(body)
  end
end
