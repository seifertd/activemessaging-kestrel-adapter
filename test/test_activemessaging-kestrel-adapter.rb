require 'test/unit'
require 'activemessaging-kestrel-adapter'

class TestActiveMessagingKestrelAdapter < Test::Unit::TestCase
  def test_default_config
    cfg = {:servers => 'localhost:22133'}
    adapter = ActiveMessaging::Adapters::Kestrel::Connection.new(cfg)
    assert_equal ActiveMessaging::Adapters::Kestrel::SimpleRetry, adapter.instance_variable_get("@retry_policy")[:strategy]
    assert_equal 1, adapter.instance_variable_get("@retry_policy")[:config][:tries]
    assert_equal 5, adapter.instance_variable_get("@retry_policy")[:config][:delay]
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
    assert_equal ActiveMessaging::Adapters::Kestrel::SimpleRetry, adapter.instance_variable_get("@retry_policy")[:strategy]
    assert_equal 1, adapter.instance_variable_get("@retry_policy")[:config][:tries]
    assert_equal 5, adapter.instance_variable_get("@retry_policy")[:config][:delay]
  end
end
