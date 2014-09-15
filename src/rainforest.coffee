# Description:
#   Interfaces with Rainforest QA to report status
#
# Commands:
#   hubot rf subscribe - Subscribe the current channel to test-run status updates
#   hubot rf unsubscribe - Remove this room from the subscription list
#   hubot rf status - Query the last 5 test runs
#   hubot rf subscriptions - List the rooms that are subscribed to status updates

module.exports = (robot) ->
    rainforestToken = process.env.HUBOT_RAINFOREST_TOKEN
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

    testNames = {}
    refreshTestNames = ->
        robot.http('https://app.rainforestqa.com/api/1/tests?page_size=1000')
        .header('CLIENT_TOKEN', rainforestToken)
        .header('Content-Type', 'application/json')
        .header('User-Agent', 'rainforest-hubot v0.0.1')
        .get() (err, res, body) ->
            for test in JSON.parse(body)
                testNames[test.id] = test.title

    queryRainforestRuns = (callback, numResults=5) ->
        robot.http('https://app.rainforestqa.com/api/1/runs?page_size=' + numResults)
        .header('CLIENT_TOKEN', rainforestToken)
        .header('Content-Type', 'application/json')
        .header('User-Agent', 'rainforest-hubot v0.0.1')
        .get() (err, res, body) ->
            results = JSON.parse(body).sort(compareByCreationDateReversed)[..numResults]
            for result in results
                result.requested_tests = [testNames[tid] for tid in result.requested_tests]
            callback results

    updateStateAndReport = ->
        queryRainforestRuns (results) ->
            oldruns = robot.brain.data.rainforestRuns
            for run in results
                tests = run.requested_tests.join(', ')
                oldrunstate = oldruns[run.id]
                if oldrunstate != run.state
                    sendToRooms ":palm_tree::palm_tree: [#{tests}] is *#{decorateState run.state, run.result}* "+
                                "( https://app.rainforestqa.com/runs/#{run.id}/tests )"
                robot.brain.data.rainforestRuns[run.id] = run.state

    robot.brain.data.rainforest ?= {}
    robot.brain.data.rainforestRooms ?= {}
    robot.brain.data.rainforestRuns ?= {}

    # Check the feed every 10 seconds
    setInterval updateStateAndReport, 10*1000
    updateStateAndReport()
    # Refresh test names every 5 minutes
    setInterval refreshTestNames, 5*60*1000
    refreshTestNames()

    robot.respond /rf subscriptions/i, (msg) ->
        rooms = [k for k of robot.brain.data.rainforestRooms]
        msg.send ":palm_tree::palm_tree: Rooms receiving Rainforest updates: [#{rooms.join ', '}]"

    robot.respond /rf subscribe/i, (msg) ->
        msg.send ":palm_tree::palm_tree: Subscribing #{msg.envelope.room}"
        robot.brain.data.rainforestRooms[msg.envelope.room] = true

    robot.respond /rf unsubscribe/i, (msg) ->
        msg.send ":palm_tree::palm_tree: Unsubscribing #{msg.envelope.room}"
        delete robot.brain.data.rainforestRooms[msg.envelope.room]

    robot.respond /rf stat(us)?/i, (msg) ->
        queryRainforestRuns (res) ->
            for run in res
                tests = run.requested_tests.join(', ')
                state = decorateState(run.state, run.result)
                msg.send ":palm_tree::palm_tree: Run #{run.id} [`#{tests}`] – *#{state}*" +
                    "\n\t( https://app.rainforestqa.com/runs/#{run.id}/tests )"

    # TODO:
    # robot.respond /rf start (.*)/i
    # robot.respond /rf abort (.*)/i
