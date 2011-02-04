require 'memcache'
require 'activemessaging/adapters/base'

module ActiveMessaging
  module Adapters
    # This module contains code to integrate the ActiveMessaging framework with a
    # kestrel message queue server.
    module Kestrel
      # Simple struct for wrapping received messages
      Message = Struct.new(:headers, :body, :command)

      # Resolve the provided string into a class object
      def to_class(class_name, initial_scope = Kernel)
        class_name.split('::').inject(initial_scope) { |scope, const_name| scope.const_get(const_name) }
      end

      # class for retrying things (should be pulled into a separate gem)
      class SimpleRetry
        # Yields to caller's block and retries up to options[:tries] (default 3)
        # times in the face of exceptions.  Returns return result of block if
        # successful.  If number of tries is exhausted, the exception is reraised.
        # Retry loop will sleep options[:delay] seconds between retries (default 5).
        # If you want error logging, pass in :logger.  If not provided, Rails.logger
        # is used if defined.
        def do_work(options = {})
          logger = defined?(::Rails) ? ::Rails.logger : nil
          use_options = {:tries => 3, :delay => 5, :logger => logger}.merge(options || {})
          exception = nil
          return_value = nil
          logger = use_options[:logger]
          use_options[:tries].times do |try|
            begin
              exception = nil
              return_value = yield
              break
            rescue Exception => e
              exception = e
              logger.warn("Got error on try #{try}: #{exception} retrying after #{use_options[:delay]} seconds") if logger
            end
            sleep use_options[:delay]
          end

          raise exception if exception
          return return_value
        end
      end

      # Connection to a kestrel message queue server
      class Connection < ActiveMessaging::Adapters::BaseConnection
        include ActiveMessaging::Adapter
        register :kestrel
        attr_accessor :reliable
        # Reconnect on error
        attr_accessor :retry_policy

        def initialize(cfg)
          cfg = symbolize_keys(cfg)
          @retry_policy = cfg.delete(:retry_policy) || {:strategy => SimpleRetry, :config => {:tries => 1, :delay => 5}}
          if @retry_policy[:strategy].is_a?(String)
            # TODO: when getting a retry policy strategy from the config file, it will be a string.  Convert it to a class
            # using the Kestrel module as a context, then Kernel.
            @retry_policy[:strategy] = Kestrel.const_get(retry_policy[:strategy]) rescue Kestrel.to_class(@retry_policy[:strategy])
          end
          @config = cfg
          @subscriptions = {}
          connect
          nil
        end

        # Connect to the kestrel server using a Memcached client
        def connect
          @kestrel = MemCache.new(@config)
          @kestrel.servers = @config[:servers]
        end
 
        # Subscribe to the named destination and begin receiving
        # messages from it
        def subscribe(destination_name, headers = {})
          headers[:destination] = destination_name
          if @subscriptions[destination_name]
            # TODO: Should you get an exception or no?
          else
            @subscriptions[destination_name] = headers
          end
          nil
        end

        # Stop receiving messages from the named destination
        def unsubscribe(destination_name, headers = {})
          @subscriptions.delete(destination_name)
        end

        # Send a message to the named destination.  headers can
        # include any of the following keys:
        #    :ttl => Set the time to live of the message in seconds
        def send(destination_name, body, headers = {})
          ttl = (headers[:ttl] || 0).to_i
          if ttl <= 0
            @kestrel.set(normalize(destination_name), body)
          else
            @kestrel.set(normalize(destination_name), body, ttl)
          end
        end

        # Gets a message from any subscribed destination and returns it as a 
        # ActiveMessaging::Adaptors::Kestrel::Message object
        def receive
          return nil if @subscriptions.size < 1

          # instantiate a class for doing the retries
          retrier = @retry_policy[:strategy].new

          retrier.do_work(@retry_policy[:config]) do
            queues_to_check = @subscriptions.size > 1 ? @subscriptions.keys.sort_by{rand} : @subscriptions.keys
            queues_to_check.each do |queue|
              if item = @kestrel.get(normalize(queue))
                # TODO: ActiveMessaging ought to provide a way to do messaging
                # without having to wrap the messages in another object
                return Message.new({'destination' => queue}, item, 'MESSAGE')
              end
            end
          end
          return nil
        end

        private
          def normalize(name)
            # Kestrel doesn't like '/' chars in queue names, so get rid of them
            # (and memoize the calculation)
            @normalized_names ||= Hash.new {|h,k| h[k] = k.gsub('/', '--FS--')}
            @normalized_names[name]
          end

          def symbolize_keys(hash)
            hash.inject({}) do |new_hash, (k, v)|
              if v.is_a?(Hash)
                v = symbolize_keys(v)
              end
              new_hash[k.to_sym] = v
              new_hash
            end
          end
      end
    end
  end
end
