# Call Control Conference System Tutorial

## Introduction

The [Call Control framework](https://developers.telnyx.com/docs/api/v2/call-control) is a set of APIs that allow complete control of a call flow from the moment a call begins to the moment it is completed. In between, you will receive a number of [webhooks](https://developers.telnyx.com/docs/v2/call-control/receiving-webhooks) for each step of the call, allowing you to act on these events and send commands using the Telnyx Library. A subset of the operations available in the Call Control API is the [Call Control Conference](https://developers.telnyx.com/docs/api/v2/call-control/Conference-Commands) API. This allows the user (you) to create and manage a conference programmatically upon receiving an incoming call, or when initiating an outgoing call.


The [Telnyx Ruby Library](https://github.com/team-telnyx/telnyx-ruby) is a convenient wrapper around the REST APIs, a function which allows you to access and control call flows using an intuitive object-oriented API. This tutorial will walk you through creating a simple Sinatra server that allows you to create and manage a conference.

## Setup

Before beginning, please setup ensure that you have the Telnyx and Sinatra gems installed.

```shell
gem install telnyx sinatra
```

Alternatively, create a Gemfile for your project

```ruby
  source 'https://rubygems.org'

  gem 'sinatra'
  gem 'telnyx'
```
You will also need to login to your Telnyx account and create an [API token](https://portal.telnyx.com/#/app/auth/v2), as well as [create a number](https://portal.telnyx.com/#/app/numbers/my-numbers) if you haven't already. You will also need to [create a connection](https://portal.telnyx.com/#/app/connections) for the number. The connection also needs to be setup to work with the conference control api:

* Set the *Connection Type* to **Call Control**

* make sure the *Implementation* is **Webhook**, and the *Webhook API Version* is **API v2**

* Fill in the *Webhook URL* with the address the server will be running on. Alternatively, you can use a service like [Ngrok](https://ngrok.com/) to temporarily forward a local port to the internet to a random address and use that.

  

Now create a file such as `conference_demo_server.rb`, then write the following to setup the telnyx library.

```ruby
  require 'sinatra'
  require 'telnyx'

  CONFIG = {
    # The following 3 keys need to be filled out
    telnyx_api_key: '<your Telnyx api key>',
    phone_number: '<Telnyx phone number>', # the number that will be used for accessing the conference
    connection_id: '<connection id>', # the connection id for phone number above
  }

  # Setup telnyx api key.
  Telnyx.api_key = CONFIG[:telnyx_api_key]
```
## Receiving Webhooks & Creating a Conference
Now that you have setup your auth token, phone number, and connection, you can begin to use the API Library to make and control conferences. First, you will need to setup a Sinatra endpoint to receive webhooks for call and conference events. There are a number of webhooks that you should anticipate receiving during the lifecycle of each call and conference. This will allow you to take action in response to any number of events triggered during a call. In this example, you will use the `call.initiated` and `call.answered` events to add call to a conference. Because you will need to wait until there is a running call before you can create a conference, plan to use call events to create the conference after a call is initiated.

```ruby
# ...
# Declare script level variables
calls = []
conference = nil 

set :port, 9090
post "/webhook" do
  # Parse the request body.
  request.body.rewind
  data = JSON.parse(request.body.read)['data']
  
  # Handle events
  if data['record_type'] == 'event'
    case data['event_type']
    when 'call.initiated'
      # Create a new call object.
      call = Telnyx::Call.new id: data['payload']['call_control_id'],
                              call_leg_id: data['payload']['call_leg_id']
      # Save the new call object into our call list for later use.
      calls << call
      # Answer the call, this will cause the api to send another webhook event
      # of the type call.answered, which we will handle below.
      call.answer

    when 'call.answered'
      # Find the stored call, which was created during a call.initiated event.
      call = calls.find { |call| call.id == data['payload']['call_control_id'] }

      # Create a new conference if this is the first caller and there
      # is no conference running yet.
      if conference.nil?
        conference = Telnyx::Conferences.create call_control_id: call.id,
                                                name: 'demo-conference'
                                                
      # If there is a conference, then add the new caller.
      else
        conference.join call_control_id: call.id
      end
    when 'call.hangup'
      # Remove the ended call from the active call list
      calls.reject! {|call| call.call_leg_id == data['payload']['call_leg_id']}
    end
  end
end
```

---

Pat youself on the back--that's a lot of code to go through! Now let's break it down even further and explain what it does. First, create an array for keeping track of the ongoing calls and define a variable for storing the conference object. Then, tell Sinatra to listen on port 9090 and create an endpoint at `/webhook`, which can be anything you choose as the API doesn't care; here we just call it webhook.

```ruby
calls = []
conference = nil 

set :port, 9090
post "/webhook" do
# ...
end
```

---

Next, parse the data from the API server, check to see if it is a webhook event, and act on it if it is. Then, you will define what actions to take on different types of events.

```ruby
post "/webhook" do
  request.body.rewind
  data = JSON.parse(request.body.read)['data']
  if data['record_type'] == 'event'
    case data['event_type']
    # ...
  end
end
```

---

Here is where you will respond to a new call being initiated, which can be from either an inbound or outbound call. Create a new `Telnyx::Call` object and store it in the active call list, then call `call.answer` to answer it if it's an inbound call.

```ruby
when 'call.initiated'
  call = Telnyx::Call.new id: data['payload']['call_control_id'],
                          call_leg_id: data['payload']['call_leg_id']
  calls << call
  call.answer
```

---

On the `call.answered` event, retrieve the stored call created during the `call.initiated` event. Then, either create a new conference if this is the first call and there isn't a conference running yet, or add the call to an existing conference. Note that a `call_control_id` is required to start a conference, so there must aready be an existing call before you can create a conference, which is why we create the conference here.

```ruby
when 'call.answered'
  call = calls.find { |call| call.id == data['payload']['call_control_id'] }

  if conference.nil?
    conference = Telnyx::Conferences.create call_control_id: call.id,
                                            name: 'demo-conference'
  else
    conference.join call_control_id: call.id
  end
```

---

And finally, when a call ends we remove it from the active call list.

```ruby
when 'call.hangup'
  puts 'Call hung up'
  calls.reject! {|call| call.call_leg_id == data['payload']['call_leg_id']}
```

### Authentication

Now you have a working conference application! How secure is it though? Could a 3rd party simply craft fake webhooks to manipulate the call flow logic of your application? Telnyx has you covered with a powerful signature verification system! Simply make the following changes:

```ruby
# ...
ENV['TELNYX_PUBLIC_KEY'] = '<public key>' # Please fetch the public key from: https://portal.telnyx.com/#/app/account/public-key
post '/webhook' do
  request.body.rewind
  body = request.body.read # Save the body for verification later
  data = JSON.parse(body)['data']

  Telnyx::Webhook::Signature.verify(body,
                                    request.env['HTTP_TELNYX_SIGNATURE_ED25519'],
                                    request.env['HTTP_TELNYX_TIMESTAMP'])
# ...
```

Fill in the public key from the Telnyx Portal [here](https://portal.telnyx.com/#/app/account/public-key). `Telnyx::Webhook::Signature.verify` will do the work of verifying the authenticity of the message, and raise `SignatureVerificationError` if the signature does not match the payload.

### Usage

If you used a Gemfile, start the conference server with `bundle exec ruby conference_demo_server.rb`, if you are using globally installed gems use `ruby conference_demo_server.rb`.

## Complete Running Call Control Conference Application

The [api-v2 directory](api-v2) contains an extended version of the tutorial code above, with the added ability to control the conference from the console! See the comments in the code for details on invoking the commands.