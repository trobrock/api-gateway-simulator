require 'sinatra/base'

class Application < Sinatra::Base
  def image
    settings.cli_options[:image]
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

    docker_build = docker_build ? '' : "-v #{docker_sync_name}:/var/task:nocopy"
    docker_command = <<-CMD
    docker run #{docker_build} #{docker_environment} #{docker_network} #{image} "#{handler}" \
    '#{JSON.generate(data)}'
    CMD
    resp = system(docker_command)
    resp = JSON.parse(resp)

    [resp['statusCode'], resp['headers'], resp['body']]
  end
end
