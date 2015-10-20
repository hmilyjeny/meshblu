_ = require 'lodash'
process.env.MESSAGE_BUS_PORT = "" + _.random 10000, 50000

async = require 'async'
debug = require('debug')('meshblu:worker')
Benchmark = require 'simple-benchmark'
redis = require './lib/redis'
authDevice = require './lib/authDevice'
sendMessageCreator = require './lib/sendMessage'
createMessageIOEmitter = require './lib/createMessageIOEmitter'
MessageIO = require './lib/MessageIO'

class Worker
  constructor: ->
    messageIO = new MessageIO()
    messageIO.start()

    redisStore = redis.createIoStore()
    messageIO.setAdapter redisStore

    @_sendMessage = sendMessageCreator createMessageIOEmitter messageIO.io
    @redis = redis.createClient()

  run: =>
    async.whilst @true, @popMessage, (error) =>
      console.error 'whilst error:', error.stack
      process.exit 1

  true: => true

  popMessage: (callback) =>
    @redis.brpop 'meshblu-messages', 60, (err, result) =>
      return callback err if err?
      return callback() unless result?
      benchmark = new Benchmark label: 'message'
      debug 'start', benchmark.toString()

      [queueName, jobStr] = result
      @processJobStr jobStr, benchmark, callback

  processJobStr: (jobStr, benchmark, callback) =>
    debug 'parseJobStr', benchmark.toString()
    @parseJob jobStr, benchmark, (error, job) =>
      return callback() if error?

      @processJob job, benchmark, callback

  parseJob: (jobStr, benchmark, callback) =>
    debug 'parseJob', benchmark.toString()
    try
      callback null, JSON.parse jobStr
    catch error
      console.error error.stack
      callback()

  processJob: (job, benchmark, callback) =>
    debug 'processJob', benchmark.toString()
    {auth,message,http} = job
    {uuid,token} = auth

    @authDevice uuid, token, benchmark, (error, device) =>
      debug 'authedDevice', benchmark.toString()
      return callback() if error?

      @sendMessage device, message, benchmark, callback

  authDevice: (uuid, token, benchmark, callback) =>
    debug 'authDevice', benchmark.toString()
    authDevice uuid, token, callback

  sendMessage: (device, message, benchmark, callback) =>
    debug 'sendMessage', benchmark.toString()
    @_sendMessage device, message
    callback()

worker = new Worker()
worker.run()