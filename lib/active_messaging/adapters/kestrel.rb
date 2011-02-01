require 'memcache'

module ActiveMessaging
  module Adapters
    module Kestrel
      class Connection
        include ActiveMessaging::Adapter
        register :kestrel
        attr_accessor :reliable
        # Time to sleep between polls of empty queues
        attr_accessor :receive_throttle
        # Reconnect on error
        attr_accessor :error_policy

        def initialize(cfg)
          @receive_throttle = cfg.delete(:receive_throttle) || 0.1
          # TODO: Implement error policies
          @error_policy = cfg.delete(:error_policy) || :reconnect
          @config = cfg
          @queues = {}
          connect
          nil
        end

        def connect
          @kestrel = MemCache.new(@config)
          @kestrel.servers = @config[:servers]
        end

        def subscribe(destination_name, headers = {})
          headers[:destination] = destination_name
          if @queues[destination_name]
            # TODO: Should you get an exception or no?
          else
            @queues[destination_name] = headers
          end
          nil
        end

        def unsubscribe(destination_name, headers = {})
          @queues.delete(destination_name)
        end

        def send(destination_name, body, headers = {})
          ttl = (headers[:ttl] || 0).to_i
          if ttl <= 0
            @kestrel.set(destination_name, body)
          else
            @kestrel.set(destination_name, body, ttl)
          end
        end

        def receive
          # TODO: Is this what ActiveMessaging expects: can it handle a nil return?
          #while (true)
            # Get a message from a subscribed queue, but don't favor any queue over another
            queues_to_check = @queues.size > 1 ? @queues.keys.sort_by{rand} : @queues.keys
            queues_to_check.each do |queue|
              if item = @kestrel.get(queue)
                return item
              end
            end
          #  # Sleep a bit so we don't get into a spinloop
          #  sleep @receive_throttle
          #end
          return nil
        end
      end
    end
  end
end
