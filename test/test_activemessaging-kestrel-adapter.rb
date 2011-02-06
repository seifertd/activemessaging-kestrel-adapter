require 'test/unit'
require 'active_support'  # Annoying that I have to do this for the ActiveMessaging framework ...
require 'activemessaging'
require 'activemessaging-kestrel-adapter'

class TestActiveMessagingKestrelAdapter < Test::Unit::TestCase
  def test_default_config
    cfg = {:servers => 'localhost:22133'}
    adapter = ActiveMessaging::Adapters::Kestrel::Connection.new(cfg)
    assert_equal adapter.instance_variable_get("@retry_policy")[:strategy], ActiveMessaging::Adapters::Kestrel::SimpleRetry
    assert_equal adapter.instance_variable_get("@retry_policy")[:config], {:tries => 1, :delay => 5}
  end

  def test_config_from_yaml
    yaml = <<-YAML
development:
  adapter: kestrel
  servers: localhost:22133
  retry_policy:
    strategy: SimpleRetry
    config: 
      tries: 1
      delay: 5
    YAML
    cfg = YAML.load(yaml)['development']
    adapter = ActiveMessaging::Adapters::Kestrel::Connection.new(cfg)
    assert_equal adapter.instance_variable_get("@retry_policy")[:strategy], ActiveMessaging::Adapters::Kestrel::SimpleRetry
    assert_equal adapter.instance_variable_get("@retry_policy")[:config], {:tries => 1, :delay => 5}
  end
end
