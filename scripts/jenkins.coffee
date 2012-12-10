# Description:
#   Interact with your Jenkins CI server
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_JENKINS_URL
#   HUBOT_JENKINS_AUTH
#
# Commands:
#   hubot jenkins build <job> - builds the specified Jenkins job
#   hubot jenkins build <job>, <params> - builds the specified Jenkins job with parameters as key=value&key2=value2
#   hubot jenkins list - lists Jenkins jobs
#   hubot jenkins describe <job> - Describes the specified Jenkins job
#   hubot jenkins <job> <branch_name> - Get the status of the last build for the given branch, checking the given job

#
# Author:
#   dougcole, additions by tjh

querystring = require 'querystring'

jenkinsBuild = (msg) ->
    token  = process.env.HUBOT_JENKINS_BUILD_TOKEN
    url    = process.env.HUBOT_JENKINS_URL

    job    = querystring.escape msg.match[1]
    params = msg.match[3]

    path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/build"
    path = "#{path}?token=#{token}"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.post() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else if res.statusCode == 302
          msg.send "Build started for #{job} #{res.headers.location}"
        else
          msg.send "Jenkins says: #{body}"

jenkinsDescribe = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    path = "#{url}/job/#{job}/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            msg.send "Raw respons: #{body}"
            content = JSON.parse(body)
            response += "JOB: #{content.displayName}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "LAST BUILT: #{content.lastBuild.url}\n"

            response += "ENABLED: #{content.buildable}\n"
            response += "STATUS: #{content.color}\n"

            tmpReport = ""
            if content.healthReport.length > 0
              for report in content.healthReport
                tmpReport += "\n  #{report.description}"
            else
              tmpReport = " unknown"
            response += "HEALTH: #{tmpReport}\n"

            parameters = ""
            for item in content.actions
              if item.parameterDefinitions
                for param in item.parameterDefinitions
                  tmpDescription = if param.description then " - #{param.description} " else ""
                  tmpDefault = if param.defaultParameterValue then " (default=#{param.defaultParameterValue.value})" else ""
                  parameters += "\n  #{param.name}#{tmpDescription}#{tmpDefault}"

            if parameters != ""
              response += "PARAMETERS: #{parameters}\n"

            msg.send response
          catch error
            msg.send error

jenkinsStatus = (job, msg) ->
    url = process.env.HUBOT_JENKINS_URL
    path = "#{url}/job/#{job}/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)

            if content.color == 'blue_anime' or content.color == 'red_anime'
              state = ":arrows_counterclockwise:"
            else
              state = if content.color == "red" then ":rage:" else ":green_heart:"

            response += "#{state}"
            response += " #{content.displayName}: "
            response += " #{content.lastBuild.url}"

            if content.buildable
              msg.send response
          catch error
            msg.send error

buildStatus = (job, num, msg) ->
    url = process.env.HUBOT_JENKINS_URL
    path = "#{url}/job/#{job}/#{num}/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)

            if content.building == true
              state = ":arrows_counterclockwise:"
            else
              state = if content.result == "SUCCESS" then ":green_heart:" else ":rage:"

            response += "#{state}"
            response += " #{content.fullDisplayName}: "
            response += " #{content.url}"

            msg.send response
          catch error
            msg.send error

jenkinsList = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]
    req = msg.http("#{url}/api/json")

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            content = JSON.parse(body)
            for job in content.jobs
              jenkinsStatus(job.name, msg)
          catch error
            msg.send error

jenkinsBranch = (msg) ->
    url         = process.env.HUBOT_JENKINS_URL
    job         = msg.match[1]
    branch_name = msg.match[2]

    # Url to determine what the last job number is
    req = msg.http("#{url}/job/#{job}/lastBuild/api/json")

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            builds_checked = 0
            found_it = false
            content = JSON.parse(body)
            # This index seems to change periodically, as if
            # the json output changes. Grr.
            json_api_index = 3
            for full_branch_name, branch_details of content.actions[json_api_index].buildsByBranchName
              builds_checked = builds_checked + 1
              if full_branch_name == "origin/#{branch_name}"
                found_it = true
                buildStatus(job, branch_details.buildNumber, msg)
            if !found_it
              msg.send "Could not find a build for '#{branch_name}' in '#{job}' out of #{builds_checked} builds"
          catch error
            msg.send error

module.exports = (robot) ->
  robot.respond /jenkins build ([\w\.\-_ ]+)(, (.+))?/i, (msg) ->
    jenkinsBuild(msg)

  robot.respond /jenkins list/i, (msg) ->
    jenkinsList(msg)

  robot.respond /jenkins describe (.*)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.respond /jenkins (.*) (.*)/i, (msg) ->
    jenkinsBranch(msg)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild,
    describe: jenkinsDescribe,
    branch: jenkinsBranch
  }
