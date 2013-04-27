git = require 'git-utils'

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

  @register 'aheadBehind', (done) ->
    done null, repo?.getAheadBehindCount()
