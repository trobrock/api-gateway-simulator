require 'sinatra/base'

class Application < Sinatra::Base
  def runtime
    settings.cli_options[:runtime]
  end

  def path
    settings.cli_options[:path]
  end

  def docker_sync_name
    settings.cli_options[:docker_sync]
  end

  def docker_network
    settings.cli_options[:network] ? "--network #{settings.cli_options[:network]}" : ''
  end

  def handler
    settings.cli_options[:handler]
  end

  def docker_environment
    Array(settings.cli_options[:env]).map { |v| "-e \"#{v}\"" }.join(' ')
  end

  def error_response(message)
    [502, {}, message]
  end

  helpers do
    def request_headers
      env.reduce({}) do |acc, (k, v)|
        acc[Regexp.last_match(1).downcase] = v if k =~ /^http_(.*)/i
        acc
      end
    end
  end

  post '/*' do
    docker_build = request_headers.delete('x_docker_built')
    data = {
      body: request.body.read,
      resource: '/{proxy+}',
      path: request.env['PATH_INFO'],
      httpMethod: 'POST',
      isBase64Encoded: false,
      queryStringParameters: params,
      pathParameters: {
        proxy: request.env['PATH_INFO']
      },
      headers: headers
    }

    volumes = if docker_sync_name
                "-v #{docker_sync_name}:/var/task:nocopy"
              else
                "-v #{path}:/var/task"
              end

    image = if docker_build
              "lambci/lambda:build-#{runtime}"
            else
              "lambci/lambda:#{runtime}"
            end

    raw_resp = `docker run #{volumes} #{docker_environment} #{docker_network} #{image} "#{handler}" \
    '#{JSON.generate(data)}'`

    begin
      resp = JSON.parse(raw_resp)
    rescue JSON::ParserError
      return error_response("Failed to parse JSON response from Lambda function: #{raw_resp}")
    end

    unless resp['body'].is_a?(String)
      return error_response("Body from Lambda function is not a string: #{resp['body']}")
    end

    [resp['statusCode'], resp['headers'], resp['body']]
  end
end
