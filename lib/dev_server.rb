# frozen_string_literal: true

require 'sinatra/base'

class Application < Sinatra::Base
  def runtime
    settings.cli_options['runtime']
  end

  def path
    File.join(Dir.pwd, settings.cli_options['path'])
  end

  def docker_sync_name
    settings.cli_options['docker_sync']
  end

  def docker_network
    settings.cli_options['network'] ? "--network #{settings.cli_options['network']}" : ''
  end

  def handlers
    settings.cli_options['handlers']
  end

  def docker_environment
    Array(settings.cli_options['environment']).map { |k, v| "-e \"#{k}=#{v}\"" }.join(' ')
  end

  def error_response(message)
    [502, {}, message]
  end

  def volumes
    if docker_sync_name
      "-v #{docker_sync_name}:/var/task:nocopy"
    else
      "-v #{path}:/var/task"
    end
  end

  def image
    docker_build = request_headers.delete('x_docker_built')

    if docker_build
      "lambci/lambda:build-#{runtime}"
    else
      "lambci/lambda:#{runtime}"
    end
  end

  def request_path
    request.env['PATH_INFO']
  end

  def handler_from_config(http_method)
    request_path_parts = request_path.split('/')

    handlers.keys.each do |handler_path|
      path_parts = handler_path.split('/')
      next if path_parts.size != request_path_parts.size

      path_match = true
      path_parts.each_with_index do |part, index|
        path_match &&= (part[0] == ':' || request_path_parts[index] == part)
      end
      next unless path_match

      handler = handlers[handler_path][http_method]
      return handler if handler
    end

    nil
  end

  def proxy_path_parameters
    parts = request_path.split('/')
    parts.delete_at(1)
    parts.join('/')
  end

  def handle_request(http_method)
    data = {
      body: request.body.read,
      resource: '/{proxy+}',
      path: request_path,
      httpMethod: http_method,
      isBase64Encoded: false,
      queryStringParameters: params,
      pathParameters: {
        proxy: proxy_path_parameters
      },
      headers: headers
    }

    handler = handler_from_config(http_method)
    if handler.nil?
      return error_response("No handler configured for #{http_method} #{request_path}")
    end

    raw_resp = `docker run #{volumes} #{docker_environment} #{docker_network} #{image} \
    "#{handler}" '#{JSON.generate(data)}'`

    begin
      resp = JSON.parse(raw_resp)
    rescue JSON::ParserError
      return error_response("Failed to parse JSON response from Lambda function: #{raw_resp}")
    end

    unless resp['body'].nil? || resp['body'].is_a?(String)
      return error_response("Body from Lambda function is not a string: #{resp['body']}")
    end

    [resp['statusCode'], resp['headers'], resp['body']]
  end

  helpers do
    def request_headers
      env.reduce({}) do |acc, (k, v)|
        acc[Regexp.last_match(1).downcase] = v if k =~ /^http_(.*)/i
        acc
      end
    end
  end

  get '/*' do
    handle_request('GET')
  end

  post '/*' do
    handle_request('POST')
  end
end
