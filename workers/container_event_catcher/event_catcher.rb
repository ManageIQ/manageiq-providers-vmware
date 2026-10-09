# Load KubernetesEventCatcherBase from the manageiq-providers-kubernetes gem.
# In production the gem is installed via the inline gemfile in the worker binary.
# In development/test the local checkout is used via the path gem in Gemfile.
k8s_base = if (spec = Gem.loaded_specs['manageiq-providers-kubernetes'])
             File.join(spec.gem_dir, 'lib/manageiq/providers/kubernetes/workers/event_catcher_base')
           else
             File.expand_path('../../../manageiq-providers-kubernetes/lib/manageiq/providers/kubernetes/workers/event_catcher_base', __dir__)
           end
require k8s_base

require 'rest-client'
require 'json'

class EventCatcher < KubernetesEventCatcherBase
  # vSphere WCP sessions have no expiry field in the response.
  # 600s (10 min) is the documented default idle timeout — used as a
  # conservative assumed TTL so the token is refreshed before it silently expires.
  WCP_SESSION_TTL = 600

  attr_reader :token_expiry

  private

  def auth_options
    @token_expiry = Time.now.utc + WCP_SESSION_TTL
    {:bearer_token => wcp_login}
  end

  def wcp_login
    url = URI::HTTPS.build(:host => endpoint['hostname'], :path => '/wcp/login').to_s

    verify_ssl = case endpoint['security_protocol']
                 when 'ssl-without-validation' then OpenSSL::SSL::VERIFY_NONE
                 else OpenSSL::SSL::VERIFY_PEER
                 end

    result = RestClient::Request.execute(
      :method      => :post,
      :url         => url,
      :user        => authentication['userid'],
      :password    => authentication['password'],
      :verify_ssl  => verify_ssl,
      :ssl_ca_file => endpoint['certificate_authority'],
      :headers     => {'Accept' => '*/*', 'Content-Type' => 'application/json'}
    )

    JSON.parse(result.body)['session_id']
  end

  def log_prefix
    'MIQ(ManageIQ::Providers::Vmware::ContainerManager::EventCatcher)'
  end
end
