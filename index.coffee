# git.open() returns null when we're not in a repo
#
# We're using false to represent "not yet created" and null to
# represent "created and not in a repo"
repoObj = false

repo = ->
  repoObj = git.open '.' if repoObj is false
  repoObj

module.exports = (Impromptu, register, git) ->
  # Expose the repo object from the git-utils library
  # This will be null when we're not in a repo
  register '_repo',
    update: (done) ->
      done null, repo()

  # Helper to figure out if we're in a repo at all
  register 'isRepo',
    update: (done) ->
      done null, !! repo()

  # Root path to the repository
  register 'root',
    update: (done) ->
      root = repo()?.getPath().replace /\.git\/$/, ''
      done null, root

  # Branch name
  # Returns commit hash when head is detached
  # Returns null in newly-initialized repos (note that isRepo() still returns true in this case)
  register 'branch',
    update: (done) ->
      branch = repo()?.getShortHead()
      done null, branch

  # Determine whether the repo is currently in a detached head state
  # This happens when you checkout, for example, a commit hash
  register 'isDetachedHead',
    update: (done) ->
      branch = repo()?.getHead()
      done null, ! /^refs\/heads\//.test branch

  # Returns an object with 'ahead' and 'behind' keys
  # Each has a count of commits that your repo is ahead/behind its upstream
  #
  # This command *must* be passed through a formatter before its displayed
  register '_aheadBehind',
    update: (done) ->
      done null, repo()?.getAheadBehindCount()

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

  class Status
    # These are the bit codes that correspond to each status entry.
    # There are additional codes to handle submodules that are not documented here.
    @Codes:
      INVALID:              0

      STAGED_ADDED:         1 << 0
      STAGED_MODIFIED:      1 << 1
      STAGED_DELETED:       1 << 2
      STAGED_RENAMED:       1 << 3
      STAGED_TYPE_CHANGE:   1 << 4

      UNSTAGED_ADDED:       1 << 7
      UNSTAGED_MODIFIED:    1 << 8
      UNSTAGED_DELETED:     1 << 9
      UNSTAGED_TYPE_CHANGE: 1 << 10

      IGNORED:              1 << 14
      UNCHANGED:            1 << 15

    constructor: (@path, @code) ->
      @flags = {}
      for key, code of Status.Codes
        @flags[key] = !! (@code & code)

        # If we find a valid flag, assign our internal properties based on the
        # flag's name. Any flag can switch a property to true.
        if @flags[key]
          @staged ||= /^STAGED/.test key
          @unstaged ||= /^UNSTAGED/.test key
          @added ||= /ADDED$/.test key
          @modified ||= /MODIFIED$/.test key
          @deleted ||= /DELETED$/.test key

  class Statuses
    constructor: (@statuses) ->
      properties = ['added', 'modified', 'deleted', 'staged', 'unstaged']

      # Create status arrays.
      for property in properties
        @[property] = []

      # Bind array formatters.
      for property, formatter of Statuses.formatters
        @[property].toString = formatter if @[property]

      # Populate status arrays.
      for status in @statuses
        for property in properties
          @[property].push status if status[property]

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
      return done null, [] unless status = repo()?.getStatus()

      statuses = for path, code of status
        # Hack around weird behavior in libgit2 that treats nested Git repos as submodules
        # https://github.com/libgit2/libgit2/pull/1423
        #
        # Benchmarking suggests this is likely fast enough
        continue if repo().isIgnored path

        new Status path, code

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

  register 'fetch',
    cache: 'repository'
    expire: 60
    update: (done) ->
      git.isRepo (err, isRepo) ->
        return done err, isRepo unless isRepo

        Impromptu.exec 'git fetch --all', (err, results) ->
          done err, results

  # Register the git repository.
  @repository.register 'git',
    root: git.root
    branch: git.branch
