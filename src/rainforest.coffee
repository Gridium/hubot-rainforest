# Description:
#   Interfaces with Rainforest QA to report status
#
# Commands:
#   hubot rf subscribe - Subscribe the current channel to test-run status updates
#   hubot rf unsubscribe - Remove this room from the subscription list
#   hubot rf status - Query the last 5 test runs
#   hubot rf subscriptions - List the rooms that are subscribed to status updates
#   hubot rf tags - List the tags currently in use
#   hubot rf run (tag) [, tag, ...] - Run a tagged set of tests

TREES = ':palm_tree::palm_tree:'
rainforestToken = process.env.HUBOT_RAINFOREST_TOKEN

# Don't report transitions into these states to the chat rooms
ignored_states = [
    'queued',
    'in_progress',
]

module.exports = (robot) ->
    unless rainforestToken?
        console.log "Specify HUBOT_RAINFOREST_TOKEN to enable Rainforest commands"
        return

    sendToRooms = (msg) ->
        for room of robot.brain.data.rainforestRooms
            robot.messageRoom room, msg

    compareByCreationDateReversed = (a,b) ->
        return a.created_at - b.created_at

    decorateState = (state, result) ->
        switch state.toLowerCase()
            when 'complete' then "#{result} " + switch result
                when 'passed' then ":white_check_mark:"
                when 'failed' then ":x:"
            when 'aborted' then "(aborted)"
            else state

    runReport = (run) ->
        state = switch run.state.toLowerCase()
            when 'complete' then "#{run.result} " + switch run.result
                when 'passed' then ":white_check_mark:"
                when 'failed' then ":x:"
            when 'aborted' then "(aborted)"
            else run.state

        "#{TREES} Run is *#{state}*\n" +
            ("\t#{x}" for x in run.sample_test_titles).join('\n') +
            "\n\thttps://app.rainforestqa.com/runs/#{run.id}/tests"

    app = new RainforestApp robot

    testNames = {}
    refreshTestNames = ->
        app.getAllTests (tests) ->
            for test in tests
                testNames[test.id] = test.title

    updateStateAndReport = ->
        app.getRuns 10, (results) ->
            oldruns = robot.brain.data.rainforestRuns
            for run in results
                oldrunstate = oldruns[run.id]
                if oldrunstate != run.state and run.state not in ignored_states
                    sendToRooms runReport(run)
                robot.brain.data.rainforestRuns[run.id] = run.state

    robot.brain.data.rainforest ?= {}
    robot.brain.data.rainforestRooms ?= {}
    robot.brain.data.rainforestRuns ?= {}

    # Refresh test names every 5 minutes
    setInterval refreshTestNames, 5*60*1000
    refreshTestNames()

    # Check the feed every 10 seconds
    setInterval updateStateAndReport, 10*1000
    updateStateAndReport()

    robot.respond /rf subscriptions/i, (msg) ->
        rooms = [k for k of robot.brain.data.rainforestRooms]
        msg.send "#{TREES} Rooms receiving Rainforest updates: [#{rooms.join ', '}]"

    robot.respond /rf subscribe/i, (msg) ->
        msg.send "#{TREES} Subscribing #{msg.envelope.room}"
        robot.brain.data.rainforestRooms[msg.envelope.room] = true

    robot.respond /rf unsubscribe/i, (msg) ->
        msg.send "#{TREES} Unsubscribing #{msg.envelope.room}"
        delete robot.brain.data.rainforestRooms[msg.envelope.room]

    robot.respond /rf stat(us)?/i, (msg) ->
        app.getRuns 5, (res) ->
            for run in res
                msg.send runReport(run)
        , msg

    robot.respond /rf tags/, (msg) ->
        app.getAllTags (json) ->
            msg.send "#{TREES} " + (
                "#{t.name} (#{t.count} test#{if t.count!=1 then 's' else ''})" for t in json
            ).join ' '
        , msg

    robot.respond /rf run (.*)/, (msg) ->
        tags = (x.trim() for x in msg.match[1].split(','))
        unless tags?
            return msg.reply "Please specify a tag. I won't run _all_ the tests for you."

        app.startRun tags, (resp) ->
            if resp.error
                msg.reply "Rainforest error for input [#{tags}]: #{resp.error}"
            msg.send "#{TREES} https://app.rainforestqa.com/runs/#{resp.id}/tests"
        , msg

class RainforestApp
    constructor: (@robot) ->

    requester: (endpoint) ->
        @robot.http("https://app.rainforestqa.com/api/1/#{endpoint}")
            .header('Accept', 'application/json')
            .header('Content-type', 'application/json')
            .header('CLIENT_TOKEN', rainforestToken)

    get: (endpoint, msg, callback) ->
        @requester(endpoint).get() (err, res, body) =>
            try
                json = JSON.parse body
            catch error
                msg.reply "Rainforest error: #{error} / #{res} / #{body}" if msg?
            callback json

    post: (endpoint, data, msg, callback) =>
        unless typeof data == "string"
            data = JSON.stringify data
        @requester(endpoint).post(data) (err, res, body) =>
            try
                json = JSON.parse body
            catch error
                msg.reply "Rainforest error: #{error} / #{res} / #{body}" if msg?
            callback json

    getAllTags: (callback, msg) -> @get 'tests/tags', msg, callback

    getAllTests: (callback, msg) -> @get 'tests?page_size=1000', msg, callback

    getRuns: (n, callback, msg) -> @get "runs?page_size=#{n}", msg, callback

    # tags is an array of strings
    startRun: (tags, callback, msg) -> @post 'runs', {tags: tags}, msg, callback
