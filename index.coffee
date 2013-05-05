git = require 'git-utils'

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
      # Create status arrays.
      @added = []
      @modified = []
      @deleted = []
      @staged = []
      @unstaged = []

      # Bind array formatters.
      for key, formatter of Statuses.formatters
        @[key].toString = formatter if @[key]

      # Populate status arrays.
      for status in @statuses
        # Each status has a code that maps to how the file has changed and
        # whether they are staged.
        #
        # For example, when `code` is 1, the file is added and staged.
        switch status.code
          when 1
            @added.push status
            @staged.push status
          when 2
            @modified.push status
            @staged.push status
          when 4
            @deleted.push status
            @staged.push status
          when 128
            @added.push status
            @unstaged.push status
          when 256
            @modified.push status
            @unstaged.push status
          when 512
            @deleted.push status
            @unstaged.push status

    toString: ->
      results = []
      results.push @modified if @modified.length
      results.push @added if @added.length
      results.push @deleted if @deleted.length
      results.join ' '

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

      done null, new Statuses statuses

  # Register object and string methods for filtering the statuses.
  #
  # Object methods: `_staged`, `_unstaged`, `_added`, `_modified`, `_deleted`
  # String methods: `staged`, `unstaged`, `added`, `modified`, `deleted`
  #
  # Strings are formatted as "∆2 +1 -3" by default.
  ['staged', 'unstaged', 'added', 'modified', 'deleted'].forEach (type) ->
    # Get an object that has filtered the statuses by type.
    register "_#{type}",
      update: (done) ->
        git._status (err, statuses) ->
          done err, new Statuses statuses[type]

    # Get a string that represents the status.
    # Format: "∆2 +1 -3"
    register type,
      update: (done) ->
        git["_#{type}"] (err, statuses) ->
          done err, statuses.toString()
