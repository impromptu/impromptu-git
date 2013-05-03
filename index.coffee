git = require 'git-utils'
_ = require 'underscore'

repo = git.open '.'

module.exports = (Impromptu, register, git) ->
  # Expose the repo object from the git-utils library
  # This will be null when we're not in a repo
  register '_repo',
    update: (done) ->
      done null, repo

  # Helper to figure out if we're in a repo at all
  register 'isRepo',
    update: (done) ->
      done null, !! repo

  # Root path to the repository
  register 'root',
    update: (done) ->
      root = repo?.getPath().replace /\.git\/$/, ''
      done null, root

  # Branch name
  # Returns commit hash when head is detached
  # Returns null in newly-initialized repos (note that isRepo() still returns true in this case)
  register 'branch',
    update: (done) ->
      branch = repo?.getShortHead()
      done null, branch

  # Determine whether the repo is currently in a detached head state
  # This happens when you checkout, for example, a commit hash
  register 'isDetachedHead',
    update: (done) ->
      branch = repo?.getHead()
      done null, ! /^refs\/heads\//.test branch

  # Returns an object with 'ahead' and 'behind' keys
  # Each has a count of commits that your repo is ahead/behind its upstream
  #
  # This command *must* be passed through a formatter before its displayed
  register '_aheadBehind',
    update: (done) ->
      done null, repo?.getAheadBehindCount()

  # Get the number of commits you're ahead of the remote
  register 'ahead',
    update: (done) ->
      git._aheadBehind (err, aheadBehind) ->
        done err, aheadBehind?.ahead

  # Get the number of commits you're behind the remote
  register 'behind',
    update: (done) ->
      git._aheadBehind (err, aheadBehind) ->
        done err, aheadBehind?.behind

  class Statuses
    constructor: (@statuses) ->
      @modified = @_filterByState 'modified'
      @added = @_filterByState 'added'
      @deleted = @_filterByState 'deleted'

    toString: ->
      results = []
      results.push @modified if @modified.length
      results.push @added if @added.length
      results.push @deleted if @deleted.length
      results.join ' '

    _filterByState: (@state) ->
      filtered = _.filter @statuses, (status) ->
        Statuses.CODE_MAP[status.code]?.state is state

      if Statuses.formatters[state]
        filtered.toString = Statuses.formatters[state]

      filtered

    @CODE_MAP:
      1:
        state: 'added'
        staged: true
      2:
        state: 'modified'
        staged: true
      4:
        state: 'deleted'
        staged: true
      128:
        state: 'added'
        staged: false
      256:
        state: 'modified'
        staged: false
      512:
        state: 'deleted'
        staged: false

    @formatters:
      added: ->
        if @length then "+#{@length}" else ""

      modified: ->
        if @length then "∆#{@length}" else ""

      deleted: ->
        if @length then "-#{@length}" else ""

  # Returns an array of objects with 'path', 'code', 'staged', 'state'
  #
  # This command *must* be passed through a formatter before its displayed
  register '_status',
    update: (done) ->
      return done null, [] unless status = repo?.getStatus()

      statuses = for path, code of status
        # Hack around weird behavior in libgit2 that treats nested Git repos as submodules
        # https://github.com/libgit2/libgit2/pull/1423
        #
        # Benchmarking suggests this is likely fast enough
        continue if repo.isIgnored path

        path: path
        code: code
        staged: Statuses.CODE_MAP[code]?.staged
        state: Statuses.CODE_MAP[code]?.state

      done null, statuses

  register 'staged',
    update: (done) ->
      git._status (err, statuses) ->
        done err, new Statuses _.where(statuses, {staged: true})

  register 'unstaged',
    update: (done) ->
      git._status (err, statuses) ->
        done err, new Statuses _.where(statuses, {staged: false})

  # Get the number of "untracked" files
  # Untracked is defined as new files that are not staged
  register 'untracked',
    update: (done) ->
      git._status (err, statuses) ->
        statuses = _filter_statuses_by_state(statuses, 'added')
        count = _.where(statuses, {staged: false}).length
        done err, count

  # Get the number of modified files
  # Does not matter whether or not they are staged
  register 'modified',
    update: (done) ->
      git._status (err, statuses) ->
        count = _filter_statuses_by_state(statuses, 'modified').length
        done err, count

  # Get the number of deleted files
  # Does not matter whether or not they are staged
  register 'deleted',
    update: (done) ->
      git._status (err, statuses) ->
        count = _filter_statuses_by_state(statuses, 'deleted').length
        done err, count

  # Get the number of "added" files
  # Added is defined as new files that are staged
  register 'added',
    update: (done) ->
      git._status (err, statuses) ->
        statuses = _filter_statuses_by_state statuses, 'added'
        count = _.where(statuses, {staged: true}).length
        done err, count
