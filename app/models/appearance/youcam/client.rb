require "net/http"

# HTTP to YouCam, on Net::HTTP. API calls carry the key and a JSON content type (GETs too: some answer 415 without
# one) and pass through before_request (the app-wide throttle). Presigned uploads and result downloads go straight to
# storage: no key, no throttle.
#
# Retries: rate limits (429) always; server and network errors only on calls that are safe to repeat. A task create
# is never repeated after a server or network error, because the first one may have started (and charged) a task.
class Appearance::Youcam::Client
  BASE_URL = "https://yce-api-01.makeupar.com".freeze
  TRIES = 3
  BACKOFF = 2 # seconds, times the attempt number
  SERVER_ERRORS = [ 500, 502, 503, 504 ].freeze
  NETWORK_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, EOFError, OpenSSL::SSL::SSLError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT
  ].freeze

  # status is 0 for a network error. code is the provider's error_code when it sent one.
  class HttpError < StandardError
    attr_reader :status, :code

    def initialize(status, code, message)
      @status = status
      @code = code
      super("HTTP #{status} #{code} #{message}".squish)
    end
  end

  def initialize(base_url: BASE_URL, before_request: nil, sleeper: ->(seconds) { sleep(seconds) })
    @base_url = base_url
    @before_request = before_request
    @sleeper = sleeper
  end

  def get(path, key:)
    json api(Net::HTTP::Get, path, key:, safe: true)
  end

  # safe: true for calls that can be repeated harmlessly (file registration, task delete).
  def post(path, body, key:, safe: false)
    json api(Net::HTTP::Post, path, key:, safe:, body: body.to_json)
  end

  def put(url, bytes, headers:)
    uri = URI(url)
    request = Net::HTTP::Put.new(uri, headers)
    request.body = bytes
    perform(uri, request, safe: true)
    nil
  end

  def download(url)
    uri = URI(url)
    perform(uri, Net::HTTP::Get.new(uri), safe: true).body
  end

  private
    def api(verb, path, key:, safe:, body: nil)
      uri = URI.join(@base_url, path)
      request = verb.new(uri, "Authorization" => "Bearer #{key}", "Content-Type" => "application/json",
        "Accept" => "application/json")
      request.body = body
      perform(uri, request, safe:, throttled: true)
    end

    def perform(uri, request, safe:, throttled: false)
      retry_statuses = safe ? [ 429, *SERVER_ERRORS ] : [ 429 ]

      1.upto(TRIES) do |attempt|
        last = attempt == TRIES
        @before_request&.call if throttled

        begin
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10,
            read_timeout: 30, write_timeout: 30) { |http| http.request(request) }
        rescue *NETWORK_ERRORS => error
          raise HttpError.new(0, "NetworkError", error.class.name) if last || !safe

          @sleeper.call(BACKOFF * attempt)
          next
        end

        return response if response.is_a?(Net::HTTPSuccess)
        raise http_error(response) if last || !response.code.to_i.in?(retry_statuses)

        @sleeper.call(BACKOFF * attempt)
      end
    end

    def http_error(response)
      body = JSON.parse(response.body.to_s) rescue {}
      body = {} unless body.is_a?(Hash)
      HttpError.new(response.code.to_i, body["error_code"], body["error"])
    end

    def json(response)
      JSON.parse(response.body)
    end
end
