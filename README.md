activemessaging-kestrel-adapter
===========

This is an adapter to the kestrel messaging server for the ActiveMessaging framework.  It is 
in the early stages of development.

Features
--------

* send to any queue
* receive from any subscribed queue

Examples
--------

    require 'activemessaging-kestrel-adapter'

    # configure ActiveMessaging broker in an appropriate broker.yml file:
    # development:
    #   adapter: kestrel
    #   servers: localhost:22133
    #   empty_queues_delay: 0.1
    #   retry_policy:
    #     strategy: SimpleRetry
    #     config: 
    #       tries: 1
    #       delay: 5
    # the retry_policy: second is optional and should be left out under
    # most circumstances (see below).
    config = YAML.load(File.read("broker.yml"))

    adapter = ActiveMessaging::Adapters::Kestrel::Connection.new(config[:development])

    adapter.send("arbitrarily_named_queue", "message as string")
    adapter.subscribe("queue1")
    adapter.subscribe("queue2")
    adapter.receive # get a message from any of the subscribed queues, or nil if they are all empty

Configuration
-------------

See the ActiveMessaging project for details of broker configuration.  This
Kestrel adapter can be configured with a retry_policy, but it is not 
necessary to do so as a sensible default will be used if the configuration
is not present.  The default policy is as shown above.  The default
policy in the face of receive exceptions is to sleep 5 seconds, then retry
once.  If an exception still occurs, it is raised.  The strategy must
refer to a class that once instantiated, responds to the do_work() method.
The method must take a options hash.  The value of the options hash will 
be the config: key in the configuration file.  For 99% of use cases, you
should not even bother defining the retry_policy as the default is fine.
The ability to override the policy is provided for edge cases.

empty_queues_delay is provided as a hack for when this adapter is used by the
ActiveMessaging::Gateway messaging loop.  Without setting this to some
small non zero value, the messaging loop will consume 100% of CPU if there
are no messages in subscribed queues.  If you are using this adapter outside
of the ActiveMessaging::Gateway messaging loop, do not set this key, but beware
of CPU burn if you call ActiveMessaging::Adapters::Kestrel::Connection#receive
in a loop and there are no messages in the subscribed queues.

Requirements
------------

* activemessaging >= 0.9.0
* memcache-client
* active_support
* active_support/core_ext
* i18n

Future
------

* Handle a cluster of kestrel servers

Install
-------

* gem install activemessaging-kestrel-adapter

Author
------

Original author: Douglas A. Seifert <doug@dseifert.net>

License
-------

The MIT License

Copyright (c) 2011-2012 Douglas A. Seifert

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
