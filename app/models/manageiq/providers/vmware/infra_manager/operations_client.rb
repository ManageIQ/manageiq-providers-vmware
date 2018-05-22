class ManageIQ::Providers::Vmware::InfraManager::OperationsClient
  def initialize(ems, server, username, password)
    @ems            = ems
    @connect_params = {:server => server, :username => username, :password => password}
  end

  def get(path, args = {})
    url = "#{operations_worker_uri}#{path}"
    headers = {
      :params => connect_params,
      :args   => args,
    }

    response = RestClient.get(url, headers)
    response.body
  end

  def post(path, args = {})
    url = "#{operations_worker_uri}#{path}"
    payload = connect_params.merge(args)

    response = RestClient.post(url, payload)
    response.body
  end

  private

  attr_reader :ems, :connect_params

  def operations_worker_uri
    @operations_worker_uri ||= operations_worker_klass.uri(ems)
  end

  def operations_worker_klass
    @operations_worker_klass ||= ems.class::OperationsWorker
  end
end
