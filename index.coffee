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

  @register 'root', (done) ->
    root = repo?.getPath().replace /\.git\/$/, ''
    done null, root

  @register 'branch', (done) ->
    branch = repo?.getShortHead()
    done null, branch

  @register 'isDetachedHead', (done) ->
    branch = repo?.getHead()
    done null, ! /^refs\/heads\//.test branch

  @register 'aheadBehind', (done) ->
    done null, repo?.getAheadBehindCount()

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
