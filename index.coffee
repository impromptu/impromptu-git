git = require 'git-utils'

STATUS_CODE_MAP =
  1:
    desc: 'added'
    staged: true
  2:
    desc: 'modified'
    staged: true
  4:
    desc: 'deleted'
    staged: true
  128:
    desc: 'added'
    staged: false
  256:
    desc: 'modified'
    staged: false
  512:
    desc: 'deleted'
    staged: false

module.exports = (Impromptu) ->
  @name 'git'
  repo = git.open '.'

  @register 'isRepo', (done) =>
    done null, !! repo

  # Root path to the repository
  @register 'root', (done) ->
    root = repo?.getPath().replace /\.git\/$/, ''
    done null, root

  # Branch name
  # Returns commit hash when head is detached
  # Returns null in newly-initialized repos (note that isRepo() still returns true in this case)
  @register 'branch', (done) ->
    branch = repo?.getShortHead()
    done null, branch

  # Determine whether the repo is currently in a detached head state
  # This happens when you checkout, for example, a commit hash
  @register 'isDetachedHead', (done) ->
    branch = repo?.getHead()
    done null, ! /^refs\/heads\//.test branch

  # Returns an object with 'ahead' and 'behind' keys
  # Each has a count of commits that your repo is ahead/behind its upstream
  #
  # This command *must* be passed through a formatter before its displayed
  @register 'aheadBehind', (done) ->
    done null, repo?.getAheadBehindCount()

  # Returns an array of objects with 'path', 'code', 'staged', 'desc'
  #
  # This command *must* be passed through a formatter before its displayed
  @register 'status', (done) ->
    status = repo?.getStatus()
    done null, '' unless status

    statuses = []
    for path, code of status
      statuses.push
        path: path
        code: code
        staged: STATUS_CODE_MAP[code]?.staged
        desc: STATUS_CODE_MAP[code]?.desc

    done null, statuses
