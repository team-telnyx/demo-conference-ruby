# frozen_string_literal: true

require 'sinatra'
require 'telnyx'
require 'awesome_print'

##
## Telnyx Conferencing demo script
##
## This demo illustrates how to use the Telnyx Ruby SDK to
## create and control conferences.
##

CONFIG = {
  telnyx_api_key: '<your Telnyx api key>', # your-api-v2-key-here, create one here: https://portal.telnyx.com/#/app/auth/v2
  phone_number: '<Telnyx phone number>', # the number that will be used for accessing the conference, find it here: https://portal.telnyx.com/#/app/numbers/my-numbers
  connection_id: '<connection id>',  # connection id for phone_number, find it here: https://portal.telnyx.com/#/app/connections
  voice: 'female',
  language: 'en-GB',
  waiting_audio_url: 'https://upload.wikimedia.org/wikipedia/commons/4/40/Toreador_song_cleaned.ogg'
}.freeze

ENV['TELNYX_PUBLIC_KEY'] = '<public key>' # Please fetch the public key from: https://portal.telnyx.com/#/app/account/public-key

# Declare script level vars.
calls = [] # Keep a list of active calls.
webhook_ids = [] # Track webhook ids to avoid duplicates.
conference = nil

# Setup telnyx api key.
Telnyx.api_key = CONFIG[:telnyx_api_key]

set :port, 9090
post '/webhook' do
  request.body.rewind
  body = request.body.read # Copy the body as a plain string.
  data = JSON.parse(body)['data'] # Parse the request body.

  # Verify the signature of the webhook.
  # Webhook::Signature.verify will raise `SignatureVerificationError` if the signature cannot be validated.
  Telnyx::Webhook::Signature.verify(body,
                                    request.env['HTTP_TELNYX_SIGNATURE_ED25519'],
                                    request.env['HTTP_TELNYX_TIMESTAMP'])

  # Handle events.
  if data['record_type'] == 'event'
    return if webhook_ids.include? data['id']

    webhook_ids << data['id']
    puts 'New webhook event: '
    ap data # Pretty-print the webhook data.
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

      puts 'Call initiated'
      ap call

    when 'call.answered'
      # Find the stored call, which was created during a call.initiated event.
      call = calls.find { |call| call.id == data['payload']['call_control_id'] }
      # Speak to the new caller and tell them they are joining the conference.
      call.speak payload: 'joining conference',
                 voice: CONFIG[:voice],
                 language: CONFIG[:language]

      puts 'Call answered, adding to conference'
      ap call
      # Create a new conference if this is the first caller and there
      # is no conference running yet.
      if conference.nil?
        conference = Telnyx::Conferences.create call_control_id: call.id,
                                                name: "demo-conference#{rand(1_000..9_999)}"

        puts 'Conference created'
        ap conference
      # If there is a conference, then add the new caller.
      else
        conference.join call_control_id: call.id
      end
    when 'call.hangup'
      puts 'Call ended'
      # Remove the ended call from the active call list.
      calls.reject! { |call| call.call_leg_id == data['payload']['call_leg_id'] }
    when 'conference.participant.joined'
      puts 'Participant joined'
    when 'conference.participant.left'
      puts 'Participant left'
    end
  end
end

# Control the demo with simple rest commands to /command/*
conference_not_started_message = "Conference not running yet, try calling #{CONFIG[:phone_number]} first."
# Example: $ curl localhost:9090/command/list
get '/command/list' do
  return conference_not_started_message unless conference

  Telnyx::Conferences.list
end

# Example: $ curl localhost:9090/command/mute
get '/command/mute' do
  return conference_not_started_message unless conference

  # This will mute all participants
  conference.mute(call_control_ids: calls.map(&:id))
end

# Example: $ curl localhost:9090/command/unmute
get '/command/unmute' do
  return conference_not_started_message unless conference

  conference.unmute(call_control_ids: calls.map(&:id))
end

# Example: $ curl localhost:9090/command/hold
get '/command/hold' do
  return conference_not_started_message unless conference

  conference.hold(call_control_ids: calls.map(&:id), audio_url: CONFIG[:waiting_audio_url])
end

# Example: $ curl localhost:9090/command/unhold
get '/command/unhold' do
  return conference_not_started_message unless conference

  conference.unhold(call_control_ids: calls.map(&:id))
end

# Example: $ curl localhost:9090/command/call/15555555555
get '/command/call/*' do
  to = "+#{params[:splat].first}"
  puts "Calling #{to}"
  Telnyx::Call.create to: to,
                      from: CONFIG[:phone_number],
                      connection_id: CONFIG[:connection_id]
end
