require 'heroku-api'
require "heroku/client"

class Heroku::Client::Organizations
  class << self
    def api
      @api ||= begin
        require("excon")
        manager_url = ENV['HEROKU_MANAGER_URL'] || "https://manager-api.heroku.com"
        key = Heroku::Auth.get_credentials[1]
        auth = "Basic #{Base64.encode64(':' + key).gsub("\n", '')}"
        @headers = {} unless @headers
        hdrs = @headers.merge( {"Authorization" => auth } )
        @connection = Excon.new(manager_url, :headers => hdrs)
      end

      self
    end

    def request params
      begin
        @connection.request params
      rescue Excon::Errors::HTTPStatusError => error
        klass = case error.response.status
          when 401 then Heroku::API::Errors::Unauthorized
          when 402 then Heroku::API::Errors::VerificationRequired
          when 403 then Heroku::API::Errors::Forbidden
          when 404
            if error.request[:path].match /\/apps\/\/.*/
              Heroku::API::Errors::NilApp
            else
              Heroku::API::Errors::NotFound
            end
          when 408 then Heroku::API::Errors::Timeout
          when 422 then Heroku::API::Errors::RequestFailed
          when 423 then Heroku::API::Errors::Locked
          when 429 then Heroku::API::Errors::RateLimitExceeded
          when /50./ then Heroku::API::Errors::RequestFailed
          else Heroku::API::Errors::ErrorWithResponse
        end

        decompress_response!(error.response)
        reerror = klass.new(error.message, error.response)
        reerror.set_backtrace(error.backtrace)
        raise(reerror)
      end
    end

    def headers=(headers)
      @headers = headers
    end

    # Orgs
    #################################
    def get_orgs
      begin
        Heroku::Helpers.json_decode(api.request(
          :expects => 200,
          :path => "/v1/user/info",
          :method => :get
          ).body)
      rescue Excon::Errors::NotFound
        # user is not a member of any organization
        { 'user' => {} }
      end
    end

    # Apps
    #################################
    def join_app(app)
      api.request(
        :expects => 200,
        :method => :post,
        :path => "/v1/app/#{app}/join"
      )
    end

    def leave_app(app)
      api.request(
        :expects => 204,
        :method => :delete,
        :path => "/v1/app/#{app}/join"
      )
    end

    def lock_app(app)
      api.request(
        :expects => 200,
        :method => :post,
        :path => "/v1/app/#{app}/lock"
      )
    end

    def unlock_app(app)
      api.request(
        :expects => 204,
        :method => :delete,
        :path => "/v1/app/#{app}/lock"
      )
    end

    # Members
    #################################
    def get_members(org)
      Heroku::Helpers.json_decode(
        api.request(
          :expects => 200,
          :method => :get,
          :path => "/v1/organization/#{org}/user"
        ).body
      )
    end

    def add_member(org, member, role)
      api.request(
        :expects => 201,
        :method => :post,
        :path => "/v1/organization/#{org}/user",
        :body => Heroku::Helpers.json_encode( { "email" => member, "role" => role } ),
        :headers => {"Content-Type" => "application/json"}
      )
    end

    def set_member(org, member, role)
      api.request(
        :expects => 200,
        :method => :put,
        :path => "/v1/organization/#{org}/user/#{CGI.escape(member)}",
        :body => Heroku::Helpers.json_encode( { "role" => role } ),
        :headers => {"Content-Type" => "application/json"}
      )
    end

    def remove_member(org, member)
      api.request(
        :expects => 204,
        :method => :delete,
        :path => "/v1/organization/#{org}/user/#{CGI.escape(member)}"
      )
    end

    private

    def decompress_response!(response)
      return unless response.headers['Content-Encoding'] == 'gzip'
      response.body = Zlib::GzipReader.new(StringIO.new(response.body)).read
    end

  end
end